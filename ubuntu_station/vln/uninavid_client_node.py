import argparse
import asyncio
import base64
import json
import threading
import time
from uuid import uuid4
from collections import deque
from typing import Any

import rclpy
import websockets
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import CompressedImage
from std_msgs.msg import String

from .mission_api_client import (
    ActiveMission,
    MissionApiClient,
    MissionApiError,
)

CAMERA_TOPIC = "/remote/camera/color/compressed"
ACTION_TOPIC = "/vln/uninavid/actions"
VALID_ACTIONS = {"forward", "left", "right", "stop"}
MISSION_POLL_SEC = 1.0
MISSION_API_FAILURE_LIMIT_SEC = 5.0
VERIFICATION_API_OUTAGE_TIMEOUT_SEC = 60.0
VERIFICATION_HARD_DEADLINE_SEC = 900.0
VERIFICATION_PROGRESS_LOG_SEC = 10.0
STOP_COMPLETION_THRESHOLD = 3
DEFAULT_RECOVERY_TURN_ACTION = "left"
DEFAULT_RECOVERY_TURN_DURATION_SEC = 0.35
DEFAULT_RECOVERY_TURN_REPETITIONS = 36
DEFAULT_VERIFIER_RETRIES = 2


def stamp_to_ns(stamp: Any) -> int:
    return int(stamp.sec) * 1_000_000_000 + int(stamp.nanosec)


class UniNaVidClientNode(Node):
    def __init__(self, server_url: str, instruction: str | None, mission_api_url: str | None,
                 session_id: str = "go2", rate_hz: float = 1.0,
                 verifier_retries: int = DEFAULT_VERIFIER_RETRIES,
                 recovery_turn_action: str = DEFAULT_RECOVERY_TURN_ACTION,
                 recovery_turn_duration_sec: float = DEFAULT_RECOVERY_TURN_DURATION_SEC,
                 recovery_turn_repetitions: int = DEFAULT_RECOVERY_TURN_REPETITIONS,
                 verification_hard_deadline_sec: float = VERIFICATION_HARD_DEADLINE_SEC) -> None:
        super().__init__("uninavid_client")
        if (instruction is None) == (mission_api_url is None):
            raise ValueError("provide exactly one of --instruction or --mission-api-url")
        if instruction is not None and not instruction.strip():
            raise ValueError("--instruction must not be empty")
        if rate_hz <= 0:
            raise ValueError("--rate-hz must be greater than zero")
        if verifier_retries <= 0:
            raise ValueError("--verifier-retries must be greater than zero")
        if recovery_turn_action not in {"left", "right"}:
            raise ValueError("--recovery-turn-action must be left or right")
        if recovery_turn_duration_sec <= 0:
            raise ValueError("--recovery-turn-duration-sec must be greater than zero")
        if recovery_turn_repetitions <= 0:
            raise ValueError("--recovery-turn-repetitions must be greater than zero")
        if verification_hard_deadline_sec <= 0:
            raise ValueError("--verification-hard-deadline-sec must be greater than zero")
        self.server_url = server_url
        self.instruction = instruction or ""
        self.session_id = session_id
        self.rate_hz = rate_hz
        self.mission_mode = mission_api_url is not None
        self.mission_api = MissionApiClient(mission_api_url) if mission_api_url else None
        self.verifier_retries = verifier_retries
        self.recovery_turn_action = recovery_turn_action
        self.recovery_turn_duration_sec = recovery_turn_duration_sec
        self.recovery_turn_repetitions = recovery_turn_repetitions
        self.verification_hard_deadline_sec = verification_hard_deadline_sec

        self.latest_lock = threading.Lock()
        self.latest_jpeg: bytes | None = None
        self.latest_timestamp_ns = 0
        self.infer_lock = threading.Lock()
        self.infer_in_flight = False
        self.frame_seq = 0
        self.loop: asyncio.AbstractEventLoop | None = None
        self.websocket = None
        self.connected = threading.Event()
        self.stop_requested = threading.Event()
        self.mission_wakeup = threading.Event()
        self.mission_stop = threading.Event()
        self.session_closed = threading.Event()
        self.session_closed.set()

        self.mission_lock = threading.Lock()
        self.active_mission: ActiveMission | None = None
        self.runtime_instruction = ""
        self.mission_terminal: str | None = None
        self.mission_terminal_error = ""
        self.consecutive_stop_inferences = 0
        self.non_stop_frames: deque[bytes] = deque(maxlen=3)
        self.first_stop_frame: bytes | None = None
        self.verifier_attempts = 0
        self.active_candidate_id: str | None = None
        self.candidate_submission_state = "none"
        self.candidate_verification_started_at: float | None = None
        self.verification_api_outage_since: float | None = None
        self.verification_last_progress_log = 0.0
        self.runtime_resume_pending = False
        self.runtime_active = threading.Event()
        self.api_unavailable_since: float | None = None
        self.api_failure_logged = False

        image_qos = QoSProfile(reliability=ReliabilityPolicy.BEST_EFFORT,
                               history=HistoryPolicy.KEEP_LAST, depth=1)
        self.create_subscription(CompressedImage, CAMERA_TOPIC, self._on_image, image_qos)
        self.action_pub = self.create_publisher(String, ACTION_TOPIC, 10)
        self.create_timer(1.0 / rate_hz, self._on_timer)
        self.ws_thread = threading.Thread(target=self._run_asyncio_loop,
                                          name="uninavid_ws_client", daemon=True)
        self.ws_thread.start()
        self.mission_thread: threading.Thread | None = None
        if self.mission_mode:
            print(f"[Mission] mode enabled api={mission_api_url}", flush=True)
            self.mission_thread = threading.Thread(target=self._mission_poll_loop,
                                                   name="robotfind_mission_poller", daemon=True)
            self.mission_thread.start()

    def _on_image(self, msg: CompressedImage) -> None:
        jpeg = bytes(msg.data)
        if jpeg:
            with self.latest_lock:
                self.latest_jpeg = jpeg
                self.latest_timestamp_ns = stamp_to_ns(msg.header.stamp)

    def _on_timer(self) -> None:
        if not self.connected.is_set() or self.loop is None:
            return
        if self.mission_mode and not self.runtime_active.is_set():
            return
        with self.infer_lock:
            if self.infer_in_flight:
                print("[VLN] inference still running, skip frame", flush=True)
                return
            with self.latest_lock:
                if self.latest_jpeg is None:
                    return
                jpeg, timestamp_ns = self.latest_jpeg, self.latest_timestamp_ns
            self.frame_seq += 1
            frame_seq = self.frame_seq
            self.infer_in_flight = True
        print(f"[VLN] send frame_seq={frame_seq} bytes={len(jpeg)}", flush=True)
        asyncio.run_coroutine_threadsafe(self._infer(frame_seq, timestamp_ns, jpeg), self.loop)

    def _run_asyncio_loop(self) -> None:
        asyncio.run(self._connection_loop())

    def _mission_needs_connection(self) -> bool:
        if not self.mission_mode:
            return True
        with self.mission_lock:
            return self.active_mission is not None and self.mission_terminal is None

    async def _wait_for_mission_connection(self) -> None:
        await asyncio.to_thread(self.mission_wakeup.wait, 0.2)
        self.mission_wakeup.clear()

    async def _connection_loop(self) -> None:
        self.loop = asyncio.get_running_loop()
        while not self.stop_requested.is_set():
            if not self._mission_needs_connection():
                await self._wait_for_mission_connection()
                continue
            try:
                async with websockets.connect(self.server_url, ping_interval=None,
                                              ping_timeout=None, max_size=10 * 1024 * 1024) as websocket:
                    self.websocket = websocket
                    self.session_closed.clear()
                    await self._ping(websocket)
                    await self._reset(websocket)
                    if self.mission_mode:
                        mission_id = self._mission_id()
                        if mission_id is None or self.mission_stop.is_set():
                            break
                        try:
                            if self.runtime_resume_pending:
                                await asyncio.to_thread(self.mission_api.ack_runtime_resumed, mission_id)
                                self.runtime_resume_pending = False
                                print("[Mission] runtime-resumed acknowledged", flush=True)
                                print("[Mission] search resumed", flush=True)
                            else:
                                await asyncio.to_thread(self.mission_api.ack_runtime_started, mission_id)
                                print("[Mission] runtime-started acknowledged", flush=True)
                        except Exception as exc:  # noqa: BLE001
                            self._begin_terminal("failed", f"runtime-started failed: {exc}")
                            break
                        if self.mission_stop.is_set():
                            break
                        self.runtime_active.set()
                    self.connected.set()
                    print("[VLN] connected", flush=True)
                    while not self.stop_requested.is_set():
                        if self.mission_mode and self.mission_stop.is_set():
                            break
                        await asyncio.sleep(0.2)
                    self.connected.clear()
                    if self.mission_mode and self.mission_stop.is_set():
                        await self._shutdown_session()
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001
                print(f"[VLN][ERROR] {exc}", flush=True)
                self.connected.clear()
                self.websocket = None
                self._clear_in_flight()
                if self.mission_mode and self._mission_id() is not None:
                    self._begin_terminal("failed", f"Uni-NaVid connection failed: {exc}")
                else:
                    await asyncio.sleep(2.0)
            finally:
                self.connected.clear()
                self.websocket = None
                self.session_closed.set()

    async def _ping(self, websocket) -> None:
        await websocket.send(json.dumps({"type": "ping"}))
        response = json.loads(await asyncio.wait_for(websocket.recv(), timeout=15.0))
        if response.get("type") != "pong":
            raise RuntimeError(f"unexpected ping response: {response}")

    async def _reset(self, websocket) -> None:
        instruction = self._current_instruction()
        if not instruction:
            raise RuntimeError("mission instruction is empty")
        await websocket.send(json.dumps({"type": "reset", "session_id": self.session_id,
                                          "instruction": instruction}))
        response = json.loads(await asyncio.wait_for(websocket.recv(), timeout=15.0))
        if response.get("type") != "reset_ack":
            raise RuntimeError(f"unexpected reset response: {response}")
        print(f"[VLN] reset session_id={self.session_id}", flush=True)

    async def _infer(self, frame_seq: int, timestamp_ns: int, jpeg: bytes) -> None:
        try:
            if self.mission_mode and not self.runtime_active.is_set():
                return
            websocket = self.websocket
            if websocket is None:
                raise RuntimeError("not connected")
            payload = {"type": "infer", "session_id": self.session_id, "frame_seq": frame_seq,
                       "timestamp_ns": timestamp_ns,
                       "jpeg_base64": base64.b64encode(jpeg).decode("ascii")}
            await websocket.send(json.dumps(payload))
            response = json.loads(await asyncio.wait_for(websocket.recv(), timeout=120.0))
            if response.get("type") != "inference_result":
                raise RuntimeError(f"unexpected inference response: {response}")
            raw_actions = response.get("actions", [])
            actions = self._sanitize_actions(raw_actions)
            result_frame_seq = int(response.get("frame_seq", frame_seq))
            print(f"[VLN] result frame_seq={result_frame_seq} actions={actions} "
                  f"inference_ms={float(response.get('inference_ms', 0.0)):.1f}", flush=True)
            if self.mission_mode:
                self._record_inference_result(raw_actions, jpeg)
            if not self.mission_mode or self.runtime_active.is_set():
                self._publish_actions({"frame_seq": result_frame_seq, "actions": actions,
                                       "raw_output": str(response.get("raw_output", "")),
                                       "inference_ms": float(response.get("inference_ms", 0.0))})
        except Exception as exc:  # noqa: BLE001
            print(f"[VLN][ERROR] {exc}", flush=True)
            if self.mission_mode and self._mission_id() is not None:
                self._begin_terminal("failed", f"inference failed: {exc}")
            elif isinstance(exc, websockets.exceptions.ConnectionClosed):
                self.connected.clear()
        finally:
            self._clear_in_flight()

    def _sanitize_actions(self, actions: Any) -> list[str]:
        if not isinstance(actions, list):
            return ["stop"]
        cleaned = [str(action).lower() for action in actions if str(action).lower() in VALID_ACTIONS]
        return cleaned or ["stop"]

    def _record_inference_result(self, raw_actions: Any, jpeg: bytes) -> None:
        """Track exact inference input frames and stop-response stability."""
        if not isinstance(raw_actions, list) or not raw_actions:
            all_stop = False
        else:
            all_stop = all(action == "stop" for action in raw_actions)

        with self.mission_lock:
            if self.active_mission is None or self.mission_terminal is not None:
                return
            previous = self.consecutive_stop_inferences
            if all_stop:
                self.consecutive_stop_inferences += 1
                count = self.consecutive_stop_inferences
                if count == 1:
                    self.first_stop_frame = bytes(jpeg)
            else:
                self.non_stop_frames.append(bytes(jpeg))
                self.consecutive_stop_inferences = 0
                self.first_stop_frame = None
                count = 0

        if all_stop:
            suffix = " first-stop frame captured" if count == 1 else ""
            print(f"[Verifier] stop count={count}/{STOP_COMPLETION_THRESHOLD}{suffix}", flush=True)
            if count >= STOP_COMPLETION_THRESHOLD:
                # Initialize candidate state before closing the Uni-NaVid session.
                # The mission poller may begin verification as soon as session_closed is set.
                with self.mission_lock:
                    if self.mission_terminal is None and self.active_mission is not None:
                        self.active_candidate_id = f"cand_{uuid4().hex}"
                        self.candidate_submission_state = "pending"
                        self.candidate_verification_started_at = time.monotonic()
                        candidate_id = self.active_candidate_id
                    else:
                        candidate_id = None
                if candidate_id and self._begin_terminal("verifying", "three consecutive stop inferences"):
                    print(f"[Verifier] candidate_id={candidate_id} created", flush=True)
                    print("[Verifier] candidate stop stable; verification pending", flush=True)
        elif previous:
            print("[Verifier] stop inference counter reset", flush=True)

    def _publish_actions(self, payload: dict[str, Any]) -> None:
        if self.stop_requested.is_set() or not rclpy.ok():
            return
        msg = String()
        msg.data = json.dumps(payload, ensure_ascii=False)
        try:
            self.action_pub.publish(msg)
        except Exception as exc:  # noqa: BLE001
            if not self.stop_requested.is_set():
                print(f"[VLN][ERROR] Failed to publish: {exc}", flush=True)

    def _publish_stop_action(self) -> None:
        self._publish_actions({"frame_seq": self._next_frame_seq(), "actions": ["stop"]})

    def _next_frame_seq(self) -> int:
        self.frame_seq += 1
        return self.frame_seq

    def _clear_in_flight(self) -> None:
        with self.infer_lock:
            self.infer_in_flight = False

    def _current_instruction(self) -> str:
        with self.mission_lock:
            if self.active_mission:
                return self.runtime_instruction or self.active_mission.navigation_instruction
            return self.instruction

    def _mission_id(self) -> str | None:
        with self.mission_lock:
            return self.active_mission.mission_id if self.active_mission else None

    def _mission_poll_loop(self) -> None:
        while not self.stop_requested.is_set():
            try:
                active = self.mission_api.get_active_mission()
                self.api_unavailable_since = None
                self.api_failure_logged = False
                self._handle_active_mission(active)
            except Exception as exc:  # noqa: BLE001
                self._handle_api_failure(exc)
            self._finish_terminal_if_ready()
            self.stop_requested.wait(MISSION_POLL_SEC)

    def _handle_active_mission(self, active: ActiveMission | None) -> None:
        with self.mission_lock:
            current, terminal = self.active_mission, self.mission_terminal
        if terminal is not None:
            if (active is not None and current is not None
                    and active.mission_id == current.mission_id
                    and active.state == "stopping"
                    and terminal in {"verifying", "recovering"}):
                if self._begin_terminal("stopped", "server requested stop"):
                    print("[Mission] manual stop wins over candidate verification", flush=True)
            return
        if current is None:
            if active is None:
                print("[Mission] idle", flush=True)
                return
            if active.state != "starting":
                print(f"[Mission] ignoring unexpected active state={active.state}", flush=True)
                return
            if not active.mission_id or not active.navigation_instruction:
                print("[Mission][ERROR] active mission has invalid id or instruction", flush=True)
                return
            with self.mission_lock:
                self.active_mission = active
                self.runtime_instruction = active.navigation_instruction
                self._reset_evidence_locked()
            print(f"[Mission] active mission detected mission_id={active.mission_id}", flush=True)
            print(f"[Mission] object_id={active.object_id} instruction="
                  f"\"{active.navigation_instruction}\"", flush=True)
            self.mission_wakeup.set()
            return
        if active is None:
            self._begin_terminal("failed", "active mission disappeared")
        elif active.mission_id != current.mission_id:
            self._begin_terminal("failed", "active mission changed unexpectedly")
        elif (active.navigation_instruction != current.navigation_instruction
              or active.object_id != current.object_id):
            self._begin_terminal("failed", "active mission payload changed unexpectedly")
        elif active.state == "stopping":
            print("[Mission] stop requested", flush=True)
            self._begin_terminal("stopped", "server requested stop")
        elif active.state not in {"starting", "running"}:
            self._begin_terminal("failed", f"unexpected mission state={active.state}")

    def _handle_api_failure(self, exc: Exception) -> None:
        now = time.monotonic()
        if self.api_unavailable_since is None:
            self.api_unavailable_since = now
        if not self.api_failure_logged:
            print(f"[Mission][WARN] API unavailable: {exc}", flush=True)
            self.api_failure_logged = True
        with self.mission_lock:
            verifying = self.mission_terminal == "verifying"
        failure_limit = VERIFICATION_API_OUTAGE_TIMEOUT_SEC if verifying else MISSION_API_FAILURE_LIMIT_SEC
        if self._mission_id() is not None and now - self.api_unavailable_since >= failure_limit:
            reason = (f"Mission API unavailable during verification for {failure_limit:.0f}s"
                      if verifying else "Mission API unavailable for 5s")
            self._begin_terminal("failed", reason)

    def _reset_verification_api_outage(self) -> None:
        self.verification_api_outage_since = None

    def _note_verification_api_failure(self, exc: Exception) -> None:
        now = time.monotonic()
        if self.verification_api_outage_since is None:
            self.verification_api_outage_since = now
        outage = now - self.verification_api_outage_since
        print(f"[Verifier][WARN] Mission API temporarily unavailable outage={outage:.1f}s: {exc}", flush=True)
        if outage >= VERIFICATION_API_OUTAGE_TIMEOUT_SEC:
            self._begin_terminal("failed", "Mission API unavailable during verification for 60s")

    def _reset_evidence_locked(self) -> None:
        self.consecutive_stop_inferences = 0
        self.first_stop_frame = None
        self.non_stop_frames.clear()

    def _candidate_evidence(self) -> dict[str, bytes] | None:
        with self.mission_lock:
            if len(self.non_stop_frames) < 3 or self.first_stop_frame is None:
                return None
            frames = list(self.non_stop_frames)
            first_stop = bytes(self.first_stop_frame)
        return {
            "last_non_stop_1": frames[0],
            "last_non_stop_2": frames[1],
            "last_non_stop_3": frames[2],
            "first_stop": first_stop,
        }

    def _begin_terminal(self, outcome: str, error: str) -> bool:
        with self.mission_lock:
            if self.active_mission is None or self.mission_terminal is not None:
                if not (outcome == "stopped" and self.mission_terminal in {"verifying", "recovering"}):
                    return False
            self.mission_terminal, self.mission_terminal_error = outcome, error
            if outcome in {"stopped", "failed"}:
                self._reset_evidence_locked()
        self.runtime_active.clear()
        self.mission_stop.set()
        self.connected.clear()
        self._clear_in_flight()
        self._publish_stop_action()
        self.mission_wakeup.set()
        if outcome in {"verifying", "stopped", "failed"}:
            print("[Mission] shutting down Uni-NaVid session", flush=True)
        print(f"[Mission] safe stop initiated reason={error}", flush=True)
        return True

    def _finish_terminal_if_ready(self) -> None:
        with self.mission_lock:
            mission, outcome, error = self.active_mission, self.mission_terminal, self.mission_terminal_error
        if mission is None or outcome is None or not self.session_closed.is_set():
            return
        try:
            if outcome == "verifying":
                evidence = self._candidate_evidence()
                with self.mission_lock:
                    candidate_id = self.active_candidate_id
                    submission_state = self.candidate_submission_state
                    started = self.candidate_verification_started_at or time.monotonic()
                if evidence is None or not candidate_id:
                    raise MissionApiError("candidate evidence or candidate_id unavailable")
                if time.monotonic() - started >= self.verification_hard_deadline_sec:
                    raise MissionApiError("verification hard deadline exceeded")
                status = None
                if submission_state in {"pending", "none"}:
                    try:
                        print(f"[Verifier] submitting candidate {candidate_id}", flush=True)
                        status = self.mission_api.verify_candidate(mission.mission_id, candidate_id, evidence)
                        self._reset_verification_api_outage()
                        with self.mission_lock:
                            self.candidate_submission_state = "submitted"
                        self._reset_verification_api_outage()
                        print(f"[Verifier] candidate {candidate_id} status={status.status}", flush=True)
                    except MissionApiError as exc:
                        with self.mission_lock:
                            self.candidate_submission_state = "unknown"
                        if exc.status_code == 409:
                            print(f"[Verifier] POST 409; checking candidate {candidate_id}", flush=True)
                        else:
                            print(f"[Verifier] POST timeout/error; checking candidate {candidate_id}: {exc}", flush=True)
                if status is None:
                    try:
                        status = self.mission_api.get_candidate_verification(mission.mission_id, candidate_id)
                    except MissionApiError as exc:
                        self._note_verification_api_failure(exc)
                        return
                    self._reset_verification_api_outage()
                    if status is None:
                        print(f"[Verifier] candidate {candidate_id} not found; retrying same candidate_id", flush=True)
                        status = self.mission_api.verify_candidate(mission.mission_id, candidate_id, evidence)
                        self._reset_verification_api_outage()
                        with self.mission_lock:
                            self.candidate_submission_state = "submitted"
                if status.status == "processing":
                    now = time.monotonic()
                    elapsed = now - started
                    if (self.verification_last_progress_log == 0.0
                            or now - self.verification_last_progress_log >= VERIFICATION_PROGRESS_LOG_SEC):
                        print(f"[Verifier] candidate {candidate_id} still processing elapsed={elapsed:.1f}s", flush=True)
                        self.verification_last_progress_log = now
                    return
                if status.status == "failed":
                    with self.mission_lock:
                        self.mission_terminal = "failed"
                        self.mission_terminal_error = status.error or "server verifier reported failed"
                    print(f"[Verifier][ERROR] candidate {candidate_id} status=failed", flush=True)
                    return
                if status.result not in {"same_object", "different_object", "uncertain"}:
                    raise MissionApiError("completed verification has no valid result")
                print(f"[Verifier] candidate {candidate_id} status=completed result={status.result} "
                      f"elapsed={time.monotonic() - started:.1f}s", flush=True)
                self.verifier_attempts = 0
                if status.result == "same_object":
                    with self.mission_lock:
                        self.mission_terminal = "completed"
                    return
                self._resume_after_rejection(status.result)
                return
            if outcome == "completed":
                state = self.mission_api.ack_runtime_completed(mission.mission_id)
                print(f"[Mission] runtime-completed acknowledged state={state or 'unknown'}", flush=True)
            elif outcome == "stopped":
                self.mission_api.ack_runtime_stopped(mission.mission_id)
                print("[Mission] runtime-stopped acknowledged", flush=True)
            else:
                self.mission_api.report_runtime_failed(mission.mission_id, error)
                print(f"[Mission] runtime-failed reported error={error}", flush=True)
        except MissionApiError as exc:
            with self.mission_lock:
                if self.mission_terminal != outcome:
                    return
            deadline_expired = (outcome == "verifying" and self.candidate_verification_started_at is not None
                                and time.monotonic() - self.candidate_verification_started_at >= self.verification_hard_deadline_sec)
            if outcome == "verifying" and (deadline_expired or self.verifier_attempts >= self.verifier_retries):
                with self.mission_lock:
                    self.mission_terminal = "failed"
                    self.mission_terminal_error = f"candidate verification failed: {exc}"
                    self._reset_evidence_locked()
                print(f"[Mission][ERROR] verifier unavailable: {exc}", flush=True)
            else:
                label = "Verifier" if outcome == "verifying" else "Mission"
                print(f"[{label}][WARN] terminal acknowledgement failed: {exc}", flush=True)
            return
        with self.mission_lock:
            self.active_mission = None
            self.runtime_instruction = ""
            self.mission_terminal = None
            self.mission_terminal_error = ""
            self._reset_evidence_locked()
            self.runtime_resume_pending = False
            self.verifier_attempts = 0
            self.active_candidate_id = None
            self.candidate_submission_state = "none"
            self.candidate_verification_started_at = None
            self.verification_api_outage_since = None
            self.verification_last_progress_log = 0.0
        self.mission_stop.clear()
        self.runtime_active.clear()
        print("[Mission] back to idle", flush=True)

    def _resume_after_rejection(self, reason: str) -> None:
        mission_id = self._mission_id()
        if mission_id is None:
            return
        with self.mission_lock:
            if self.mission_terminal == "verifying":
                self.mission_terminal = "recovering"
        print(f"[Mission] candidate rejected reason={reason}", flush=True)
        print(f"[Mission] recovery start action={self.recovery_turn_action} "
              f"repetitions={self.recovery_turn_repetitions}", flush=True)
        for _ in range(self.recovery_turn_repetitions):
            self._publish_actions({"frame_seq": self._next_frame_seq(),
                                   "actions": [self.recovery_turn_action]})
            self.stop_requested.wait(self.recovery_turn_duration_sec)
        self._publish_stop_action()
        self.stop_requested.wait(0.1)

        try:
            active = self.mission_api.get_active_mission()
        except MissionApiError as exc:
            with self.mission_lock:
                self.mission_terminal = "failed"
                self.mission_terminal_error = f"Mission API unavailable during recovery: {exc}"
                self._reset_evidence_locked()
            return
        if active is not None and active.state == "stopping":
            self._begin_terminal("stopped", "server requested stop during recovery")
            return

        with self.mission_lock:
            canonical = self.active_mission.navigation_instruction
            self.runtime_instruction = (
                "Continue searching. The object just rejected is not the target. "
                + canonical
            )
            self._reset_evidence_locked()
            self.runtime_resume_pending = True
            self.mission_terminal = None
            self.mission_terminal_error = ""
        self.mission_stop.clear()
        self.session_closed.set()
        self.mission_wakeup.set()
        print("[Mission] Uni-NaVid session reset", flush=True)

    def stop(self) -> None:
        if self.mission_mode and self._mission_id() is not None:
            self._begin_terminal("failed", "local runtime shutdown")
        self.stop_requested.set()
        self.mission_wakeup.set()
        self.runtime_active.clear()
        self._publish_stop_action()
        if self.loop is not None and self.websocket is not None:
            future = asyncio.run_coroutine_threadsafe(self._shutdown_session(), self.loop)
            try:
                future.result(timeout=2.0)
            except Exception:
                pass
        if self.mission_thread is not None and self.mission_thread.is_alive():
            self.mission_thread.join(timeout=3.0)
        if self.ws_thread.is_alive():
            self.ws_thread.join(timeout=3.0)

    async def _shutdown_session(self) -> None:
        if self.websocket is None:
            return
        try:
            await self.websocket.send(json.dumps({"type": "shutdown_session", "session_id": self.session_id}))
            await asyncio.wait_for(self.websocket.recv(), timeout=2.0)
        except Exception:
            pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server-url", default="ws://141.3.14.42:19000")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--instruction")
    mode.add_argument("--mission-api-url")
    parser.add_argument("--session-id", default="go2")
    parser.add_argument("--rate-hz", type=float, default=1.0)
    parser.add_argument("--verifier-retries", type=int, default=2)
    parser.add_argument("--recovery-turn-action", choices=("left", "right"), default="left")
    parser.add_argument("--recovery-turn-duration-sec", type=float, default=0.35)
    parser.add_argument("--recovery-turn-repetitions", type=int, default=DEFAULT_RECOVERY_TURN_REPETITIONS)
    parser.add_argument("--verification-hard-deadline-sec", type=float, default=VERIFICATION_HARD_DEADLINE_SEC)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rclpy.init()
    try:
        node = UniNaVidClientNode(args.server_url, args.instruction, args.mission_api_url,
                                  args.session_id, args.rate_hz, args.verifier_retries,
                                  args.recovery_turn_action, args.recovery_turn_duration_sec,
                                  args.recovery_turn_repetitions, args.verification_hard_deadline_sec)
    except Exception:
        if rclpy.ok():
            rclpy.shutdown()
        raise
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        print("[VLN] shutdown requested", flush=True)
    finally:
        node.stop()
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()

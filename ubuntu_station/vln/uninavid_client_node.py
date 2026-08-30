import argparse
import asyncio
import base64
import json
import threading
import time
from typing import Any

import rclpy
import websockets
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import CompressedImage
from std_msgs.msg import String

from .mission_api_client import ActiveMission, MissionApiClient, MissionApiError

CAMERA_TOPIC = "/remote/camera/color/compressed"
ACTION_TOPIC = "/vln/uninavid/actions"
VALID_ACTIONS = {"forward", "left", "right", "stop"}
MISSION_POLL_SEC = 1.0
MISSION_API_FAILURE_LIMIT_SEC = 5.0
STOP_COMPLETION_THRESHOLD = 3


def stamp_to_ns(stamp: Any) -> int:
    return int(stamp.sec) * 1_000_000_000 + int(stamp.nanosec)


class UniNaVidClientNode(Node):
    def __init__(self, server_url: str, instruction: str | None, mission_api_url: str | None,
                 session_id: str = "go2", rate_hz: float = 1.0) -> None:
        super().__init__("uninavid_client")
        if (instruction is None) == (mission_api_url is None):
            raise ValueError("provide exactly one of --instruction or --mission-api-url")
        if instruction is not None and not instruction.strip():
            raise ValueError("--instruction must not be empty")
        if rate_hz <= 0:
            raise ValueError("--rate-hz must be greater than zero")
        self.server_url = server_url
        self.instruction = instruction or ""
        self.session_id = session_id
        self.rate_hz = rate_hz
        self.mission_mode = mission_api_url is not None
        self.mission_api = MissionApiClient(mission_api_url) if mission_api_url else None

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
        self.mission_terminal: str | None = None
        self.mission_terminal_error = ""
        self.consecutive_stop_inferences = 0
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
                            await asyncio.to_thread(self.mission_api.ack_runtime_started, mission_id)
                        except Exception as exc:  # noqa: BLE001
                            self._begin_terminal("failed", f"runtime-started failed: {exc}")
                            break
                        if self.mission_stop.is_set():
                            break
                        self.runtime_active.set()
                        print("[Mission] runtime-started acknowledged", flush=True)
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
                self._record_inference_result(raw_actions)
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

    def _record_inference_result(self, raw_actions: Any) -> None:
        """Count complete inference responses, not individual stop actions."""
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
            else:
                self.consecutive_stop_inferences = 0
                count = 0

        if all_stop:
            print(f"[Mission] stop inference count={count}/{STOP_COMPLETION_THRESHOLD}", flush=True)
            if count >= STOP_COMPLETION_THRESHOLD:
                if self._begin_terminal("completed", "three consecutive stop inferences"):
                    print("[Mission] completion detected", flush=True)
        elif previous:
            print("[Mission] stop inference counter reset", flush=True)

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
        self.frame_seq += 1
        self._publish_actions({"frame_seq": self.frame_seq, "actions": ["stop"]})

    def _clear_in_flight(self) -> None:
        with self.infer_lock:
            self.infer_in_flight = False

    def _current_instruction(self) -> str:
        with self.mission_lock:
            return self.active_mission.navigation_instruction if self.active_mission else self.instruction

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
        if self._mission_id() is not None and now - self.api_unavailable_since >= MISSION_API_FAILURE_LIMIT_SEC:
            self._begin_terminal("failed", "Mission API unavailable for 5s")

    def _begin_terminal(self, outcome: str, error: str) -> None:
        with self.mission_lock:
            if self.active_mission is None or self.mission_terminal is not None:
                return
            self.mission_terminal, self.mission_terminal_error = outcome, error
            if outcome != "completed":
                self.consecutive_stop_inferences = 0
        self.runtime_active.clear()
        self.mission_stop.set()
        self.connected.clear()
        self._clear_in_flight()
        self._publish_stop_action()
        self.mission_wakeup.set()
        print(f"[Mission] safe stop initiated reason={error}", flush=True)

    def _finish_terminal_if_ready(self) -> None:
        with self.mission_lock:
            mission, outcome, error = self.active_mission, self.mission_terminal, self.mission_terminal_error
        if mission is None or outcome is None or not self.session_closed.is_set():
            return
        try:
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
            print(f"[Mission][WARN] terminal acknowledgement failed: {exc}", flush=True)
            return
        with self.mission_lock:
            self.active_mission = None
            self.mission_terminal = None
            self.mission_terminal_error = ""
            self.consecutive_stop_inferences = 0
        self.mission_stop.clear()
        self.runtime_active.clear()
        print("[Mission] back to idle", flush=True)

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
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rclpy.init()
    try:
        node = UniNaVidClientNode(args.server_url, args.instruction, args.mission_api_url,
                                  args.session_id, args.rate_hz)
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

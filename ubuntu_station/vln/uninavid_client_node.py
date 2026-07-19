import argparse
import asyncio
import base64
import json
import threading
from typing import Any

import rclpy
import websockets
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import CompressedImage
from std_msgs.msg import String


CAMERA_TOPIC = "/remote/camera/color/compressed"
ACTION_TOPIC = "/vln/uninavid/actions"
VALID_ACTIONS = {"forward", "left", "right", "stop"}


def stamp_to_ns(stamp: Any) -> int:
    return int(stamp.sec) * 1_000_000_000 + int(stamp.nanosec)


class UniNaVidClientNode(Node):
    def __init__(
        self,
        server_url: str,
        instruction: str,
        session_id: str = "go2",
        rate_hz: float = 1.0,
    ) -> None:
        super().__init__("uninavid_client")
        if not instruction:
            raise ValueError("--instruction must not be empty")
        if rate_hz <= 0:
            raise ValueError("--rate-hz must be greater than zero")

        self.server_url = server_url
        self.instruction = instruction
        self.session_id = session_id
        self.rate_hz = rate_hz

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

        image_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
        )
        self.create_subscription(
            CompressedImage,
            CAMERA_TOPIC,
            self._on_image,
            image_qos,
        )
        self.action_pub = self.create_publisher(String, ACTION_TOPIC, 10)
        self.create_timer(1.0 / self.rate_hz, self._on_timer)

        self.ws_thread = threading.Thread(
            target=self._run_asyncio_loop,
            name="uninavid_ws_client",
            daemon=True,
        )
        self.ws_thread.start()

    def _on_image(self, msg: CompressedImage) -> None:
        jpeg = bytes(msg.data)
        if not jpeg:
            return
        with self.latest_lock:
            self.latest_jpeg = jpeg
            self.latest_timestamp_ns = stamp_to_ns(msg.header.stamp)

    def _on_timer(self) -> None:
        if not self.connected.is_set() or self.loop is None:
            return

        with self.infer_lock:
            if self.infer_in_flight:
                print("[VLN] inference still running, skip frame", flush=True)
                return
            with self.latest_lock:
                if self.latest_jpeg is None:
                    return
                jpeg = self.latest_jpeg
                timestamp_ns = self.latest_timestamp_ns

            self.frame_seq += 1
            frame_seq = self.frame_seq
            self.infer_in_flight = True

        print(f"[VLN] send frame_seq={frame_seq} bytes={len(jpeg)}", flush=True)
        asyncio.run_coroutine_threadsafe(
            self._infer(frame_seq, timestamp_ns, jpeg),
            self.loop,
        )

    def _run_asyncio_loop(self) -> None:
        asyncio.run(self._connection_loop())

    async def _connection_loop(self) -> None:
        self.loop = asyncio.get_running_loop()
        while not self.stop_requested.is_set():
            try:
                async with websockets.connect(
                    self.server_url,
                    ping_interval=None,
                    ping_timeout=None,
                    max_size=10 * 1024 * 1024,
                ) as websocket:
                    self.websocket = websocket
                    await self._ping(websocket)
                    await self._reset(websocket)
                    self.connected.set()
                    print("[VLN] connected", flush=True)

                    while not self.stop_requested.is_set():
                        if not self.connected.is_set():
                            break
                        await asyncio.sleep(0.2)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                print(f"[VLN][ERROR] {exc}", flush=True)
                self.connected.clear()
                self.websocket = None
                self._clear_in_flight()
                await asyncio.sleep(2.0)
            finally:
                self.connected.clear()
                self.websocket = None

    async def _ping(self, websocket) -> None:
        await websocket.send(json.dumps({"type": "ping"}))
        response = json.loads(await asyncio.wait_for(websocket.recv(), timeout=15.0))
        if response.get("type") != "pong":
            raise RuntimeError(f"unexpected ping response: {response}")

    async def _reset(self, websocket) -> None:
        await websocket.send(
            json.dumps(
                {
                    "type": "reset",
                    "session_id": self.session_id,
                    "instruction": self.instruction,
                }
            )
        )
        response = json.loads(await asyncio.wait_for(websocket.recv(), timeout=15.0))
        if response.get("type") != "reset_ack":
            raise RuntimeError(f"unexpected reset response: {response}")
        print(f"[VLN] reset session_id={self.session_id}", flush=True)

    async def _infer(self, frame_seq: int, timestamp_ns: int, jpeg: bytes) -> None:
        try:
            websocket = self.websocket
            if websocket is None:
                raise RuntimeError("not connected")

            payload = {
                "type": "infer",
                "session_id": self.session_id,
                "frame_seq": frame_seq,
                "timestamp_ns": timestamp_ns,
                "jpeg_base64": base64.b64encode(jpeg).decode("ascii"),
            }
            await websocket.send(json.dumps(payload))
            response = json.loads(await asyncio.wait_for(websocket.recv(), timeout=120.0))
            if response.get("type") != "inference_result":
                raise RuntimeError(f"unexpected inference response: {response}")

            actions = self._sanitize_actions(response.get("actions", []))
            raw_output = str(response.get("raw_output", ""))
            inference_ms = float(response.get("inference_ms", 0.0))
            result_frame_seq = int(response.get("frame_seq", frame_seq))

            print(
                "[VLN] result "
                f"frame_seq={result_frame_seq} actions={actions} "
                f"inference_ms={inference_ms:.1f}",
                flush=True,
            )
            self._publish_actions(
                {
                    "frame_seq": result_frame_seq,
                    "actions": actions,
                    "raw_output": raw_output,
                    "inference_ms": inference_ms,
                }
            )
        except Exception as exc:
            print(f"[VLN][ERROR] {exc}", flush=True)
            if isinstance(exc, websockets.exceptions.ConnectionClosed):
                self.connected.clear()
        finally:
            self._clear_in_flight()

    def _sanitize_actions(self, actions: Any) -> list[str]:
        if not isinstance(actions, list):
            return ["stop"]
        cleaned = [
            str(action).lower()
            for action in actions
            if str(action).lower() in VALID_ACTIONS
        ]
        return cleaned or ["stop"]

    def _publish_actions(self, payload: dict[str, Any]) -> None:
        if self.stop_requested.is_set() or not rclpy.ok():
            return
        msg = String()
        msg.data = json.dumps(payload, ensure_ascii=False)
        try:
            self.action_pub.publish(msg)
        except Exception as exc:
            if not self.stop_requested.is_set():
                print(f"[VLN][ERROR] Failed to publish: {exc}", flush=True)

    def _clear_in_flight(self) -> None:
        with self.infer_lock:
            self.infer_in_flight = False

    def stop(self) -> None:
        self.stop_requested.set()
        loop = self.loop
        if loop is not None and self.websocket is not None:
            future = asyncio.run_coroutine_threadsafe(self._shutdown_session(), loop)
            try:
                future.result(timeout=2.0)
            except Exception:
                pass
        if self.ws_thread.is_alive():
            self.ws_thread.join(timeout=3.0)

    async def _shutdown_session(self) -> None:
        websocket = self.websocket
        if websocket is None:
            return
        await websocket.send(
            json.dumps({"type": "shutdown_session", "session_id": self.session_id})
        )
        await websocket.recv()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server-url", default="ws://141.3.14.42:19000")
    parser.add_argument("--instruction", required=True)
    parser.add_argument("--session-id", default="go2")
    parser.add_argument("--rate-hz", type=float, default=1.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rclpy.init()
    node = UniNaVidClientNode(
        server_url=args.server_url,
        instruction=args.instruction,
        session_id=args.session_id,
        rate_hz=args.rate_hz,
    )
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

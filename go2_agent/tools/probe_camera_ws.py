#!/usr/bin/env python3
import asyncio
import json
import sys
import time
import uuid
from pathlib import Path

import rclpy
import websockets
import yaml


PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from camera.frame_source import RosCameraFrameSource  # noqa: E402
from protocol import make_camera_frame  # noqa: E402


def load_config():
    with open(PROJECT_ROOT / "config.yaml", "r", encoding="utf-8") as file_obj:
        return yaml.safe_load(file_obj) or {}


async def run_probe():
    config = load_config()
    server_url = config.get("server_url", "ws://127.0.0.1:8765/go2")
    rate_hz = float(config.get("camera_rate_hz", 1.0))
    interval_sec = 1.0 / rate_hz

    rclpy.init(args=None)
    node = rclpy.create_node("go2_camera_ws_probe")
    source = RosCameraFrameSource(
        node,
        topic=config.get("camera_topic", "/camera/camera/color/image_raw"),
        camera="color",
        jpeg_quality=config.get("camera_jpeg_quality", 70),
    )
    connection_id = uuid.uuid4().hex
    seq = 0
    sent_count = 0
    deadline = time.monotonic() + 10.0

    print(f"[GO2][CAMERA_WS_PROBE] connecting to {server_url}")
    print("[GO2][CAMERA_WS_PROBE] camera-only probe, no robot control")

    try:
        async with websockets.connect(server_url) as websocket:
            while time.monotonic() < deadline and sent_count < 5:
                rclpy.spin_once(node, timeout_sec=0.0)
                frame = source.get_camera_frame()
                if frame is None:
                    await asyncio.sleep(0.01)
                    continue

                seq += 1
                await websocket.send(make_camera_frame(seq, connection_id, frame))
                sent_count += 1
                print(
                    "[GO2][CAMERA_WS_PROBE] sent "
                    + json.dumps(
                        {
                            "seq": seq,
                            "width": frame["width"],
                            "height": frame["height"],
                            "base64_chars": len(frame["jpeg_base64"]),
                        },
                        separators=(",", ":"),
                    )
                )
                await asyncio.sleep(interval_sec)
    finally:
        print(f"[GO2][CAMERA_WS_PROBE] sent_count={sent_count}")
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


def main():
    asyncio.run(run_probe())


if __name__ == "__main__":
    main()

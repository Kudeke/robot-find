#!/usr/bin/env python3
import sys
import time
from pathlib import Path

import rclpy


PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from camera.image_capture import RosImageCapture  # noqa: E402


def main():
    print("[GO2][CAMERA] local JPEG capture probe")
    print("[GO2][CAMERA] no WebSocket, no WebRTC, no robot control")

    output_dir = PROJECT_ROOT / "tools" / "captures"
    output_dir.mkdir(parents=True, exist_ok=True)

    rclpy.init(args=None)
    node = rclpy.create_node("go2_camera_capture_probe")
    capture = RosImageCapture(
        node,
        topic="/camera/camera/color/image_raw",
    )

    deadline = time.monotonic() + 10.0
    next_save_time = None
    saved_count = 0
    frame_announced = False

    try:
        while rclpy.ok() and time.monotonic() < deadline and saved_count < 3:
            rclpy.spin_once(node, timeout_sec=0.1)

            if not capture.has_frame():
                continue

            if not frame_announced:
                print("[GO2][CAMERA] frame received")
                frame_announced = True
                next_save_time = time.monotonic()

            now = time.monotonic()
            if next_save_time is None or now < next_save_time:
                continue

            filename = "capture_{:03d}.jpg".format(saved_count + 1)
            output_path = output_dir / filename
            if capture.save_latest_jpeg(output_path):
                saved_count += 1
                print(f"[GO2][CAMERA] saved {filename}")
                next_save_time = now + 1.0
            else:
                print(f"[GO2][CAMERA] failed to save {filename}")
                next_save_time = now + 0.2
    except KeyboardInterrupt:
        print("[GO2][CAMERA] interrupted")
    finally:
        print(f"[GO2][CAMERA] saved_count={saved_count}")
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()

    if saved_count != 3:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

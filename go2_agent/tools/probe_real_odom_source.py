#!/usr/bin/env python3
import json
import sys
import time
from pathlib import Path

import rclpy


PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from odom_source import RealDdsOdomSource  # noqa: E402


def main():
    print("[GO2][REAL_ODOM_PROBE] read-only local DDS probe")
    print("[GO2][REAL_ODOM_PROBE] no WebSocket and no robot control")

    rclpy.init(args=None)
    node = rclpy.create_node("go2_real_odom_source_probe")
    source = RealDdsOdomSource(node, topic="/lf/sportmodestate")
    deadline = time.monotonic() + 5.0
    printed = 0

    try:
        while rclpy.ok() and time.monotonic() < deadline:
            rclpy.spin_once(node, timeout_sec=0.1)
            odom = source.get_odom()
            if odom is not None and printed < 5:
                printed += 1
                print(
                    "odom_json="
                    + json.dumps(odom, separators=(",", ":"), ensure_ascii=True)
                )
    except KeyboardInterrupt:
        print("[GO2][REAL_ODOM_PROBE] interrupted")
    finally:
        print(f"[GO2][REAL_ODOM_PROBE] printed={printed}")
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
import json
import sys
import time
from pathlib import Path

import rclpy
from rclpy.qos import qos_profile_sensor_data
from unitree_go.msg import LowState, SportModeState


PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from dds.converters import (  # noqa: E402
    lowstate_to_battery_json,
    lowstate_to_imu_json,
    sportstate_to_odom_json,
    sportstate_to_robot_state_json,
)


class RealStateJsonProbe:
    def __init__(self, node, max_prints=3):
        self.node = node
        self.max_prints = max_prints
        self.lowstate_count = 0
        self.sportstate_count = 0
        self.lowstate_subscription = node.create_subscription(
            LowState,
            "/lf/lowstate",
            self._on_lowstate,
            qos_profile_sensor_data,
        )
        self.sportstate_subscription = node.create_subscription(
            SportModeState,
            "/lf/sportmodestate",
            self._on_sportstate,
            qos_profile_sensor_data,
        )

    def _print_json(self, name, payload):
        print(f"{name}={json.dumps(payload, separators=(',', ':'), ensure_ascii=True)}")

    def _on_lowstate(self, message):
        if self.lowstate_count >= self.max_prints:
            return
        self.lowstate_count += 1
        self._print_json("battery_json", lowstate_to_battery_json(message))
        self._print_json("imu_json", lowstate_to_imu_json(message))

    def _on_sportstate(self, message):
        if self.sportstate_count >= self.max_prints:
            return
        self.sportstate_count += 1
        self._print_json("robot_state_json", sportstate_to_robot_state_json(message))
        self._print_json("odom_json", sportstate_to_odom_json(message))


def main():
    print("[GO2][REAL_STATE_PROBE] read-only local DDS probe")
    print("[GO2][REAL_STATE_PROBE] no WebSocket and no robot control")

    rclpy.init()
    node = rclpy.create_node("go2_real_state_json_probe")
    probe = RealStateJsonProbe(node)
    deadline = time.monotonic() + 10.0

    try:
        while rclpy.ok() and time.monotonic() < deadline:
            rclpy.spin_once(node, timeout_sec=0.1)
    except KeyboardInterrupt:
        print("[GO2][REAL_STATE_PROBE] interrupted")
    finally:
        print(
            "[GO2][REAL_STATE_PROBE] received "
            f"lowstate={probe.lowstate_count} sportstate={probe.sportstate_count}"
        )
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()

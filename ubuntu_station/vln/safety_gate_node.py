import argparse
import json
import math
import threading
import time
from typing import Any

import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import PointCloud2
from sensor_msgs_py import point_cloud2
from std_msgs.msg import String
from std_srvs.srv import SetBool, Trigger


CMD_DEBUG_TOPIC = "/cmd_vel_debug"
CMD_VEL_TOPIC = "/cmd_vel"
LIDAR_TOPIC = "/remote/lidar/points"
STATUS_TOPIC = "/vln/safety_gate/status"
SET_ENABLED_SERVICE = "/vln/safety_gate/set_enabled"
EMERGENCY_STOP_SERVICE = "/vln/safety_gate/emergency_stop"
CLEAR_EMERGENCY_STOP_SERVICE = "/vln/safety_gate/clear_emergency_stop"


class SafetyGateNode(Node):
    def __init__(self, args: argparse.Namespace) -> None:
        super().__init__("uninavid_safety_gate")
        self.cmd_timeout_sec = float(args.cmd_timeout_sec)
        self.lidar_timeout_sec = float(args.lidar_timeout_sec)
        self.obstacle_x_min = float(args.obstacle_x_min)
        self.obstacle_x_max = float(args.obstacle_x_max)
        self.obstacle_half_width = float(args.obstacle_half_width)
        self.obstacle_z_min = float(args.obstacle_z_min)
        self.obstacle_z_max = float(args.obstacle_z_max)
        self.min_obstacle_points = int(args.min_obstacle_points)
        self.max_linear_x = float(args.max_linear_x)
        self.max_angular_z = float(args.max_angular_z)

        self.lock = threading.Lock()
        self.enabled = False
        self.emergency_stop_latched = False
        self.latest_cmd: Twist | None = None
        self.last_cmd_time: float | None = None
        self.last_lidar_time: float | None = None
        self.obstacle_point_count = 0
        self.obstacle_detected = False
        self.last_state: str | None = None
        self.last_status_time = 0.0
        self.last_limit_log: tuple[float, float, float, float] | None = None

        self.cmd_pub = self.create_publisher(Twist, CMD_VEL_TOPIC, 10)
        self.status_pub = self.create_publisher(String, STATUS_TOPIC, 10)
        self.create_subscription(Twist, CMD_DEBUG_TOPIC, self._on_cmd, 10)
        self.create_subscription(
            PointCloud2,
            LIDAR_TOPIC,
            self._on_lidar,
            qos_profile_sensor_data,
        )
        self.create_service(SetBool, SET_ENABLED_SERVICE, self._set_enabled)
        self.create_service(Trigger, EMERGENCY_STOP_SERVICE, self._emergency_stop)
        self.create_service(
            Trigger,
            CLEAR_EMERGENCY_STOP_SERVICE,
            self._clear_emergency_stop,
        )
        self.create_timer(0.05, self._on_timer)
        print("[GATE] started disabled", flush=True)

    def _on_cmd(self, msg: Twist) -> None:
        with self.lock:
            self.latest_cmd = self._copy_twist(msg)
            self.last_cmd_time = time.monotonic()

    def _on_lidar(self, msg: PointCloud2) -> None:
        count = self._count_obstacle_points(msg)
        with self.lock:
            self.last_lidar_time = time.monotonic()
            self.obstacle_point_count = count
            self.obstacle_detected = count >= self.min_obstacle_points
        if self.obstacle_detected:
            print(f"[GATE] lidar obstacle points={count}", flush=True)

    def _set_enabled(self, request: SetBool.Request, response: SetBool.Response):
        with self.lock:
            if request.data:
                if self.emergency_stop_latched:
                    self.enabled = False
                    response.success = False
                    response.message = "emergency stop is latched"
                    print("[GATE] enable rejected; emergency stop latched", flush=True)
                    self._publish_zero_locked(repeat=3)
                    return response
                self.enabled = True
                response.success = True
                response.message = "enabled"
                print("[GATE] enabled", flush=True)
            else:
                self.enabled = False
                self.latest_cmd = None
                response.success = True
                response.message = "disabled"
                print("[GATE] disabled, publishing stop", flush=True)
                self._publish_zero_locked(repeat=3)
        return response

    def _emergency_stop(self, request: Trigger.Request, response: Trigger.Response):
        del request
        with self.lock:
            self.emergency_stop_latched = True
            self.enabled = False
            self.latest_cmd = None
            self.last_cmd_time = None
            print("[GATE] emergency stop latched", flush=True)
            self._publish_zero_locked(repeat=3)
            response.success = True
            response.message = "emergency stop latched"
        return response

    def _clear_emergency_stop(
        self,
        request: Trigger.Request,
        response: Trigger.Response,
    ):
        del request
        with self.lock:
            self.emergency_stop_latched = False
            self.enabled = False
            self.latest_cmd = None
            self.last_cmd_time = None
            print("[GATE] emergency stop cleared; gate remains disabled", flush=True)
            self._publish_zero_locked(repeat=3)
            response.success = True
            response.message = "emergency stop cleared; gate remains disabled"
        return response

    def _on_timer(self) -> None:
        with self.lock:
            output, state, input_cmd, cmd_age, lidar_age = self._evaluate_locked()
            self.cmd_pub.publish(output)
            self._log_state_change_locked(state, output)
            now = time.monotonic()
            if now - self.last_status_time >= 0.2:
                self.last_status_time = now
                self._publish_status_locked(state, input_cmd, output, cmd_age, lidar_age)

    def _evaluate_locked(self):
        now = time.monotonic()
        zero = Twist()
        input_cmd = self._copy_twist(self.latest_cmd) if self.latest_cmd else None
        cmd_age = None if self.last_cmd_time is None else now - self.last_cmd_time
        lidar_age = None if self.last_lidar_time is None else now - self.last_lidar_time

        if self.emergency_stop_latched:
            return zero, "emergency_stop", input_cmd, cmd_age, lidar_age
        if not self.enabled:
            return zero, "disabled", input_cmd, cmd_age, lidar_age
        if input_cmd is None:
            return zero, "waiting_for_cmd", input_cmd, cmd_age, lidar_age
        if cmd_age is None or cmd_age > self.cmd_timeout_sec:
            return zero, "cmd_timeout", input_cmd, cmd_age, lidar_age
        if self._is_zero(input_cmd):
            return zero, "stopped", input_cmd, cmd_age, lidar_age
        if self.last_lidar_time is None:
            return zero, "lidar_unavailable", input_cmd, cmd_age, lidar_age
        if lidar_age is None or lidar_age > self.lidar_timeout_sec:
            return zero, "lidar_timeout", input_cmd, cmd_age, lidar_age

        limited = self._limit_cmd(input_cmd)
        if self._is_invalid_input(input_cmd):
            return zero, "invalid_command", input_cmd, cmd_age, lidar_age
        if limited.linear.x > 0.0 and self.obstacle_detected:
            return zero, "obstacle_blocked", input_cmd, cmd_age, lidar_age
        if self._is_zero(limited):
            return zero, "stopped", input_cmd, cmd_age, lidar_age

        return limited, "forwarding", input_cmd, cmd_age, lidar_age

    def _count_obstacle_points(self, msg: PointCloud2) -> int:
        count = 0
        try:
            points = point_cloud2.read_points(
                msg,
                field_names=("x", "y", "z"),
                skip_nans=True,
            )
            for point in points:
                x, y, z = self._extract_xyz(point)
                if (
                    self.obstacle_x_min <= x <= self.obstacle_x_max
                    and abs(y) <= self.obstacle_half_width
                    and self.obstacle_z_min <= z <= self.obstacle_z_max
                ):
                    count += 1
                    if count >= self.min_obstacle_points:
                        return count
        except Exception as exc:
            print(f"[GATE][ERROR] failed to read PointCloud2: {exc}", flush=True)
        return count

    def _extract_xyz(self, point: Any) -> tuple[float, float, float]:
        try:
            return float(point["x"]), float(point["y"]), float(point["z"])
        except Exception:
            return float(point[0]), float(point[1]), float(point[2])

    def _limit_cmd(self, cmd: Twist) -> Twist:
        limited = Twist()
        limited.linear.x = min(max(float(cmd.linear.x), 0.0), self.max_linear_x)
        limited.angular.z = min(
            max(float(cmd.angular.z), -self.max_angular_z),
            self.max_angular_z,
        )
        signature = (
            float(cmd.linear.x),
            float(cmd.angular.z),
            limited.linear.x,
            limited.angular.z,
        )
        if (
            abs(float(cmd.linear.x) - limited.linear.x) > 1e-9
            or abs(float(cmd.angular.z) - limited.angular.z) > 1e-9
            or abs(float(cmd.linear.y)) > 1e-9
            or abs(float(cmd.linear.z)) > 1e-9
            or abs(float(cmd.angular.x)) > 1e-9
            or abs(float(cmd.angular.y)) > 1e-9
        ) and signature != self.last_limit_log:
            self.last_limit_log = signature
            print(
                "[GATE] command limited from "
                f"linear_x={cmd.linear.x} angular_z={cmd.angular.z} "
                f"to linear_x={limited.linear.x} angular_z={limited.angular.z}",
                flush=True,
            )
        return limited

    def _is_invalid_input(self, cmd: Twist) -> bool:
        return (
            float(cmd.linear.x) < 0.0
            or abs(float(cmd.linear.y)) > 1e-9
            or abs(float(cmd.linear.z)) > 1e-9
            or abs(float(cmd.angular.x)) > 1e-9
            or abs(float(cmd.angular.y)) > 1e-9
        )

    def _log_state_change_locked(self, state: str, output: Twist) -> None:
        if state == self.last_state:
            return
        self.last_state = state
        if state == "forwarding":
            print(
                f"[GATE] forwarding linear_x={output.linear.x} "
                f"angular_z={output.angular.z}",
                flush=True,
            )
        elif state == "obstacle_blocked":
            print("[GATE] forward blocked by obstacle", flush=True)
        elif state == "cmd_timeout":
            print("[GATE] cmd timeout, publishing stop", flush=True)
        elif state == "lidar_timeout":
            print("[GATE] lidar timeout, publishing stop", flush=True)
        elif state == "lidar_unavailable":
            print("[GATE] lidar unavailable, publishing stop", flush=True)
        elif state == "disabled":
            print("[GATE] disabled, publishing stop", flush=True)

    def _publish_status_locked(
        self,
        state: str,
        input_cmd: Twist | None,
        output_cmd: Twist,
        cmd_age: float | None,
        lidar_age: float | None,
    ) -> None:
        msg = String()
        msg.data = json.dumps(
            {
                "enabled": self.enabled,
                "emergency_stop_latched": self.emergency_stop_latched,
                "state": state,
                "obstacle_detected": self.obstacle_detected,
                "obstacle_point_count": self.obstacle_point_count,
                "cmd_age_sec": cmd_age,
                "lidar_age_sec": lidar_age,
                "input_cmd": self._cmd_json(input_cmd),
                "output_cmd": self._cmd_json(output_cmd),
            },
            separators=(",", ":"),
        )
        self.status_pub.publish(msg)

    def _publish_zero_locked(self, repeat: int = 1) -> None:
        zero = Twist()
        for _ in range(max(1, repeat)):
            self.cmd_pub.publish(zero)

    def publish_shutdown_stop(self) -> None:
        with self.lock:
            print("[GATE] shutdown, publishing stop", flush=True)
            self.enabled = False
            self.latest_cmd = None
            self._publish_zero_locked(repeat=3)
            self._publish_status_locked("shutdown", None, Twist(), None, None)

    def _copy_twist(self, source: Twist) -> Twist:
        target = Twist()
        target.linear.x = float(source.linear.x)
        target.linear.y = float(source.linear.y)
        target.linear.z = float(source.linear.z)
        target.angular.x = float(source.angular.x)
        target.angular.y = float(source.angular.y)
        target.angular.z = float(source.angular.z)
        return target

    def _cmd_json(self, cmd: Twist | None) -> dict[str, float] | None:
        if cmd is None:
            return None
        return {
            "linear_x": float(cmd.linear.x),
            "linear_y": float(cmd.linear.y),
            "angular_z": float(cmd.angular.z),
        }

    def _is_zero(self, cmd: Twist) -> bool:
        return (
            math.isclose(float(cmd.linear.x), 0.0, abs_tol=1e-9)
            and math.isclose(float(cmd.linear.y), 0.0, abs_tol=1e-9)
            and math.isclose(float(cmd.linear.z), 0.0, abs_tol=1e-9)
            and math.isclose(float(cmd.angular.x), 0.0, abs_tol=1e-9)
            and math.isclose(float(cmd.angular.y), 0.0, abs_tol=1e-9)
            and math.isclose(float(cmd.angular.z), 0.0, abs_tol=1e-9)
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cmd-timeout-sec", type=float, default=0.5)
    parser.add_argument("--lidar-timeout-sec", type=float, default=1.0)
    parser.add_argument("--obstacle-x-min", type=float, default=0.0)
    parser.add_argument("--obstacle-x-max", type=float, default=0.8)
    parser.add_argument("--obstacle-half-width", type=float, default=0.35)
    parser.add_argument("--obstacle-z-min", type=float, default=-0.25)
    parser.add_argument("--obstacle-z-max", type=float, default=0.5)
    parser.add_argument("--min-obstacle-points", type=int, default=3)
    parser.add_argument("--max-linear-x", type=float, default=0.15)
    parser.add_argument("--max-angular-z", type=float, default=0.30)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rclpy.init()
    node = SafetyGateNode(args)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        print("[GATE] shutdown requested", flush=True)
    finally:
        node.publish_shutdown_stop()
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()

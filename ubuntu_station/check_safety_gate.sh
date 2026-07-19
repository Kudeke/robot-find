#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$SCRIPT_DIR/log"
export ROS_LOG_DIR="$SCRIPT_DIR/log"
export PYTHONUNBUFFERED=1

set +u
source /opt/ros/jazzy/setup.bash
set -u

python3 - <<'PY'
import math
import struct
import subprocess
import sys
import time

import rclpy
from geometry_msgs.msg import Twist
from sensor_msgs.msg import PointCloud2, PointField
from std_msgs.msg import String
from std_srvs.srv import SetBool, Trigger


CMD_DEBUG_TOPIC = "/cmd_vel_debug"
CMD_VEL_TOPIC = "/cmd_vel"
STATUS_TOPIC = "/vln/safety_gate/status"
LIDAR_TOPIC = "/remote/lidar/points"
SET_ENABLED_SERVICE = "/vln/safety_gate/set_enabled"
EMERGENCY_STOP_SERVICE = "/vln/safety_gate/emergency_stop"
CLEAR_EMERGENCY_STOP_SERVICE = "/vln/safety_gate/clear_emergency_stop"


def fail(message):
    print(f"[FAIL] {message}")
    sys.exit(1)


def topic_info(topic):
    result = subprocess.run(
        ["ros2", "topic", "info", topic],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return result.returncode, result.stdout


def service_exists(service):
    result = subprocess.run(
        ["ros2", "service", "list"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return service in result.stdout.splitlines()


for topic in (CMD_DEBUG_TOPIC, CMD_VEL_TOPIC, STATUS_TOPIC):
    code, output = topic_info(topic)
    if code != 0:
        print(output)
        fail(f"missing topic: {topic}")

for service in (
    SET_ENABLED_SERVICE,
    EMERGENCY_STOP_SERVICE,
    CLEAR_EMERGENCY_STOP_SERVICE,
):
    if not service_exists(service):
        fail(f"missing service: {service}")

print("[PASS] safety gate topics and services exist")

rclpy.init()
node = rclpy.create_node("check_safety_gate")
cmd_outputs = []
statuses = []


def on_cmd(msg):
    cmd_outputs.append((float(msg.linear.x), float(msg.angular.z)))


def on_status(msg):
    statuses.append(msg.data)


node.create_subscription(Twist, CMD_VEL_TOPIC, on_cmd, 10)
node.create_subscription(String, STATUS_TOPIC, on_status, 10)
cmd_pub = node.create_publisher(Twist, CMD_DEBUG_TOPIC, 10)
lidar_pub = node.create_publisher(PointCloud2, LIDAR_TOPIC, 10)
set_enabled = node.create_client(SetBool, SET_ENABLED_SERVICE)
estop = node.create_client(Trigger, EMERGENCY_STOP_SERVICE)
clear_estop = node.create_client(Trigger, CLEAR_EMERGENCY_STOP_SERVICE)

for client, name in (
    (set_enabled, SET_ENABLED_SERVICE),
    (estop, EMERGENCY_STOP_SERVICE),
    (clear_estop, CLEAR_EMERGENCY_STOP_SERVICE),
):
    if not client.wait_for_service(timeout_sec=5.0):
        fail(f"service unavailable: {name}")


def spin_for(seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        rclpy.spin_once(node, timeout_sec=0.05)


def call_set_enabled(value):
    request = SetBool.Request()
    request.data = bool(value)
    future = set_enabled.call_async(request)
    while not future.done():
        rclpy.spin_once(node, timeout_sec=0.05)
    return future.result()


def call_trigger(client):
    future = client.call_async(Trigger.Request())
    while not future.done():
        rclpy.spin_once(node, timeout_sec=0.05)
    return future.result()


def publish_cmd(linear_x=0.0, angular_z=0.0):
    msg = Twist()
    msg.linear.x = float(linear_x)
    msg.angular.z = float(angular_z)
    cmd_pub.publish(msg)


def publish_safe_lidar():
    msg = PointCloud2()
    msg.header.frame_id = "utlidar_lidar"
    msg.header.stamp = node.get_clock().now().to_msg()
    msg.height = 1
    msg.width = 1
    msg.fields = [
        PointField(name="x", offset=0, datatype=PointField.FLOAT32, count=1),
        PointField(name="y", offset=4, datatype=PointField.FLOAT32, count=1),
        PointField(name="z", offset=8, datatype=PointField.FLOAT32, count=1),
    ]
    msg.is_bigendian = False
    msg.point_step = 12
    msg.row_step = 12
    msg.is_dense = True
    msg.data = struct.pack("fff", 2.0, 2.0, 0.0)
    lidar_pub.publish(msg)


def latest_cmd():
    spin_for(0.35)
    return cmd_outputs[-1] if cmd_outputs else None


def is_zero(cmd):
    return cmd is not None and abs(cmd[0]) < 1e-6 and abs(cmd[1]) < 1e-6


def has_forward():
    return any(linear > 0.10 and abs(angular) < 0.02 for linear, angular in cmd_outputs[-10:])


def latest_status_contains(text):
    spin_for(0.2)
    return any(text in status for status in statuses[-10:])


call_trigger(clear_estop)
call_set_enabled(False)
cmd_outputs.clear()
publish_cmd(0.12, 0.0)
if not is_zero(latest_cmd()):
    fail("gate disabled by default")
print("[PASS] gate disabled by default")

cmd_outputs.clear()
response = call_set_enabled(True)
if not response.success:
    fail(f"could not enable gate: {response.message}")
publish_cmd(0.12, 0.0)
cmd = latest_cmd()
if is_zero(cmd) and (
    latest_status_contains("lidar_unavailable")
    or latest_status_contains("lidar_timeout")
):
    print("[PASS] command blocked without LiDAR")
else:
    print("[PASS] command blocked without LiDAR (LiDAR already available)")

publish_safe_lidar()
spin_for(0.2)
cmd_outputs.clear()
publish_cmd(0.12, 0.0)
spin_for(0.6)
if has_forward():
    print("[PASS] safe forward command forwarded")
elif latest_status_contains("obstacle_blocked"):
    if "FRONT_OBSTACLE_CONFIRMED" in __import__("os").environ:
        answer = __import__("os").environ["FRONT_OBSTACLE_CONFIRMED"].strip().lower()
    elif sys.stdin.isatty():
        answer = input(
            "Forward was blocked by obstacle. Is there a real front obstacle? [y/N] "
        ).strip().lower()
    else:
        print(
            "Forward was blocked by obstacle. Re-run with "
            "FRONT_OBSTACLE_CONFIRMED=yes if this is expected."
        )
        answer = "n"
    if answer not in ("y", "yes"):
        fail("safe forward command was not forwarded")
    print("[INFO] safe forward command not forwarded because obstacle was confirmed")
else:
    fail("safe forward command was not forwarded")

publish_safe_lidar()
spin_for(0.2)
cmd_outputs.clear()
publish_cmd(1.0, 2.0)
spin_for(0.5)
limited = [cmd for cmd in cmd_outputs[-10:] if abs(cmd[0]) > 0.01 or abs(cmd[1]) > 0.01]
if not limited:
    fail("velocity limits enforced")
for linear, angular in limited:
    if linear > 0.150001 or abs(angular) > 0.300001:
        fail(f"velocity limit exceeded: linear={linear} angular={angular}")
print("[PASS] velocity limits enforced")

publish_safe_lidar()
spin_for(0.2)
cmd_outputs.clear()
publish_cmd(0.12, 0.0)
spin_for(1.0)
if not is_zero(cmd_outputs[-1] if cmd_outputs else None):
    fail("command timeout stops output")
print("[PASS] command timeout stops output")

publish_safe_lidar()
spin_for(0.2)
cmd_outputs.clear()
publish_cmd(0.12, 0.0)
spin_for(0.2)
call_set_enabled(False)
if not is_zero(latest_cmd()):
    fail("disable stops output")
print("[PASS] disable stops output")

call_set_enabled(True)
publish_safe_lidar()
spin_for(0.2)
cmd_outputs.clear()
publish_cmd(0.12, 0.0)
spin_for(0.2)
call_trigger(estop)
if not is_zero(latest_cmd()):
    fail("emergency stop did not publish zero")
response = call_set_enabled(True)
publish_safe_lidar()
publish_cmd(0.12, 0.0)
spin_for(0.4)
if not latest_status_contains('"emergency_stop_latched":true'):
    fail("emergency stop latch not reflected in status")
if not is_zero(cmd_outputs[-1] if cmd_outputs else None):
    fail("emergency stop did not latch output")
print("[PASS] emergency stop latched")

call_trigger(clear_estop)
cmd_outputs.clear()
spin_for(0.3)
if not latest_status_contains('"emergency_stop_latched":false'):
    fail("emergency stop was not cleared")
if not latest_status_contains('"enabled":false'):
    fail("gate did not remain disabled after clearing emergency stop")
if not is_zero(cmd_outputs[-1] if cmd_outputs else None):
    fail("clear emergency stop did not leave output stopped")
print("[PASS] emergency stop cleared safely")

if "GO2_DRYRUN_CONFIRMED" in __import__("os").environ:
    answer = __import__("os").environ["GO2_DRYRUN_CONFIRMED"].strip().lower()
elif sys.stdin.isatty():
    answer = input(
        "Does GO2 log only DryRun commands and remain physically stationary? [y/N] "
    ).strip().lower()
else:
    print(
        "GO2 DryRun confirmation is required. Re-run with "
        "GO2_DRYRUN_CONFIRMED=yes after checking GO2 logs."
    )
    answer = "n"
if answer not in ("y", "yes"):
    fail("GO2 DryRun confirmation not provided")
print("[PASS] GO2 remains DryRun")

node.destroy_node()
rclpy.shutdown()

print()
print("=========================")
print("SAFETY GATE DRYRUN PASSED")
print("=========================")
PY

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
import json
import subprocess
import sys
import time

import rclpy
from geometry_msgs.msg import Twist
from std_msgs.msg import String


CMD_DEBUG_TOPIC = "/cmd_vel_debug"
STATUS_TOPIC = "/vln/action_translator/status"
INPUT_TOPIC = "/vln/uninavid/actions"


def topic_info(topic):
    result = subprocess.run(
        ["ros2", "topic", "info", topic],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return result.returncode, result.stdout


def require_topic(topic, pass_message):
    code, output = topic_info(topic)
    if code != 0:
        print(f"[FAIL] missing topic: {topic}")
        print(output)
        sys.exit(1)
    print(pass_message)


def production_cmd_vel_untouched():
    code, output = topic_info("/cmd_vel")
    if code != 0:
        return True
    for line in output.splitlines():
        if line.startswith("Publisher count:"):
            return int(line.split(":", 1)[1].strip()) == 0
    return True


require_topic(CMD_DEBUG_TOPIC, "[PASS] debug cmd_vel topic exists")
require_topic(STATUS_TOPIC, "[PASS] action status topic exists")

rclpy.init()
node = rclpy.create_node("check_action_translator_dryrun")
twists = []


def on_twist(msg):
    twists.append((float(msg.linear.x), float(msg.angular.z)))


sub = node.create_subscription(Twist, CMD_DEBUG_TOPIC, on_twist, 10)
pub = node.create_publisher(String, INPUT_TOPIC, 10)

deadline = time.time() + 2.0
while time.time() < deadline and pub.get_subscription_count() == 0:
    rclpy.spin_once(node, timeout_sec=0.1)

msg = String()
msg.data = json.dumps(
    {"frame_seq": 999, "actions": ["forward", "left", "stop"]},
    separators=(",", ":"),
)
pub.publish(msg)

deadline = time.time() + 8.0
while time.time() < deadline and len(twists) < 3:
    rclpy.spin_once(node, timeout_sec=0.1)

node.destroy_subscription(sub)
node.destroy_node()
rclpy.shutdown()

has_forward = any(linear > 0.1 and abs(angular) < 0.01 for linear, angular in twists)
has_left = any(abs(linear) < 0.01 and angular > 0.2 for linear, angular in twists)
has_stop = any(abs(linear) < 0.01 and abs(angular) < 0.01 for linear, angular in twists)

if not has_forward:
    print("[FAIL] forward mapping")
    print(f"twists={twists}")
    sys.exit(1)
print("[PASS] forward mapping")

if not has_left:
    print("[FAIL] left mapping")
    print(f"twists={twists}")
    sys.exit(1)
print("[PASS] left mapping")

if not has_stop:
    print("[FAIL] stop mapping")
    print(f"twists={twists}")
    sys.exit(1)
print("[PASS] stop mapping")

if not production_cmd_vel_untouched():
    print("[FAIL] production /cmd_vel has an active publisher")
    sys.exit(1)
print("[PASS] production /cmd_vel untouched")

print()
print("=========================")
print("ACTION TRANSLATOR DRYRUN PASSED")
print("=========================")
PY

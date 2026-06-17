#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$SCRIPT_DIR/log"
export ROS_LOG_DIR="$SCRIPT_DIR/log"

set +u
source /opt/ros/jazzy/setup.bash
set -u

require_topic() {
    topic="$1"
    if ! ros2 topic list | grep -Fxq "$topic"; then
        echo "[CHECK] missing topic: $topic" >&2
        exit 1
    fi
    echo "[CHECK] found topic: $topic"
}

require_topic /go2/state
require_topic /remote/odom
require_topic /remote/imu
require_topic /tf

echo "[CHECK] echo /go2/state"
ros2 topic echo --once /go2/state

echo "[CHECK] echo /remote/odom"
ros2 topic echo --once /remote/odom

echo "[CHECK] echo /remote/imu"
ros2 topic echo --once /remote/imu

echo "[CHECK] tf2_echo odom base_link"
tf_output="$(mktemp)"
trap 'rm -f "$tf_output"' EXIT
set +e
timeout 3s ros2 run tf2_ros tf2_echo odom base_link >"$tf_output" 2>&1
tf_status="$?"
set -e
cat "$tf_output"

if grep -Eq "At time|Translation:" "$tf_output"; then
    echo "[CHECK] tf odom -> base_link ok"
elif [ "$tf_status" -eq 124 ]; then
    echo "[CHECK] tf2_echo timed out before receiving odom -> base_link" >&2
    exit 1
else
    echo "[CHECK] tf2_echo failed with status $tf_status" >&2
    exit "$tf_status"
fi

echo "[CHECK] Phase1 topics ok"

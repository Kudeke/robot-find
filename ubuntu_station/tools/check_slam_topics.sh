#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p "$STATION_DIR/log"
export ROS_LOG_DIR="$STATION_DIR/log"

set +u
source /opt/ros/jazzy/setup.bash
set -u

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

typed_topics_file="$tmp_dir/topics.txt"
if ! timeout 10s ros2 topic list -t >"$typed_topics_file" 2>"$tmp_dir/topics.err"; then
    echo "[FAIL] unable to list ROS2 topics"
    cat "$tmp_dir/topics.err" >&2
    exit 1
fi

failures=0

check_topic() {
    local topic="$1"
    local expected_type="$2"

    if grep -Fxq "$topic [$expected_type]" "$typed_topics_file"; then
        echo "[PASS] $topic [$expected_type]"
    else
        echo "[FAIL] $topic [$expected_type]"
        failures=$((failures + 1))
    fi
}

check_topic "/remote/imu" "sensor_msgs/msg/Imu"
check_topic "/remote/odom" "nav_msgs/msg/Odometry"
check_topic "/remote/camera/color/compressed" "sensor_msgs/msg/CompressedImage"
check_topic "/remote/lidar/points" "sensor_msgs/msg/PointCloud2"

if [ "$failures" -eq 0 ]; then
    echo
    echo "[PASS] all SLAM input topics exist"
    exit 0
fi

echo
echo "[FAIL] SLAM input topics ($failures)"
exit 1

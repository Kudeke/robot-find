#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$SCRIPT_DIR/log"
export ROS_LOG_DIR="$SCRIPT_DIR/log"
export PYTHONUNBUFFERED=1

set +u
source /opt/ros/jazzy/setup.bash
set -u

topic="/remote/lidar/points"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

topic_list_file="$tmp_dir/topic_list.txt"
if ! timeout 10s ros2 topic list >"$topic_list_file" 2>"$tmp_dir/topic_list.err"; then
    echo "[FAIL] unable to list ROS2 topics"
    cat "$tmp_dir/topic_list.err" >&2
    exit 1
fi

if ! grep -Fxq "$topic" "$topic_list_file"; then
    echo "[FAIL] lidar topic missing: $topic"
    exit 1
fi

echo "[PASS] lidar topic exists"

hz_output="$tmp_dir/hz.out"
timeout --signal=INT --kill-after=2s 5s \
    ros2 topic hz --wall-time "$topic" >"$hz_output" 2>&1
hz_status=$?
cat "$hz_output"

rate="$(
    awk '/average rate:/ { value=$3 } END { print value }' "$hz_output"
)"

if [ -z "$rate" ] || ! awk -v rate="$rate" 'BEGIN { exit !(rate > 0) }'; then
    echo "[FAIL] lidar frequency"
    if [ "$hz_status" -ne 0 ] && [ "$hz_status" -ne 124 ]; then
        echo "[FAIL] ros2 topic hz exit code: $hz_status" >&2
    fi
    exit 1
fi

echo "[PASS] lidar frequency"
echo "lidar_rate_hz=$rate"

echo_output="$tmp_dir/echo.out"
timeout --signal=INT --kill-after=2s 3s \
    ros2 topic echo "$topic" --no-arr >"$echo_output" 2>&1
echo_status=$?
cat "$echo_output"

if grep -Eq "header:|height:|width:|point_step:|row_step:" "$echo_output"; then
    echo "[PASS] lidar echo"
    exit 0
fi

echo "[FAIL] lidar echo"
if [ "$echo_status" -ne 0 ] && [ "$echo_status" -ne 124 ]; then
    echo "[FAIL] ros2 topic echo exit code: $echo_status" >&2
fi
exit 1

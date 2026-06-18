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

topic="/remote/camera/color/compressed"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

topic_list_file="$tmp_dir/topic_list.txt"
if ! timeout 10s ros2 topic list >"$topic_list_file" 2>"$tmp_dir/topic_list.err"; then
    echo "[FAIL] unable to list ROS2 topics"
    cat "$tmp_dir/topic_list.err" >&2
    exit 1
fi

if ! grep -Fxq "$topic" "$topic_list_file"; then
    echo "[FAIL] topic missing: $topic"
    exit 1
fi

echo "[PASS] topic exists"

hz_output="$tmp_dir/hz.out"
timeout --signal=INT --kill-after=2s 10s \
    ros2 topic hz --wall-time "$topic" >"$hz_output" 2>&1
hz_status=$?

cat "$hz_output"

rate="$(
    awk '/average rate:/ { value=$3 } END { print value }' "$hz_output"
)"

if [ -z "$rate" ]; then
    echo "[FAIL] no camera frequency data"
    if [ "$hz_status" -ne 0 ] && [ "$hz_status" -ne 124 ]; then
        echo "[FAIL] ros2 topic hz exit code: $hz_status" >&2
    fi
    exit 1
fi

if ! awk -v rate="$rate" 'BEGIN { exit !(rate > 0) }'; then
    echo "[FAIL] camera frequency is not greater than zero: $rate Hz"
    exit 1
fi

echo "[PASS] camera frequency"
echo "camera_rate_hz=$rate"

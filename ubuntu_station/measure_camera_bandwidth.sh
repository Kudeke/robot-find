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

bw_output="$tmp_dir/bw.out"
timeout --signal=INT --kill-after=2s 10s \
    ros2 topic bw --window 100 "$topic" >"$bw_output" 2>&1
bw_status=$?

cat "$bw_output"

bw_value="$(
    awk '/\/s from [0-9]+ messages/ { value=$1 } END { print value }' \
        "$bw_output"
)"
bw_unit="$(
    awk '/\/s from [0-9]+ messages/ { unit=$2 } END { print unit }' \
        "$bw_output"
)"
size_value="$(
    awk '/Message size mean:/ { value=$4 } END { print value }' \
        "$bw_output"
)"
size_unit="$(
    awk '/Message size mean:/ { unit=$5 } END { print unit }' \
        "$bw_output"
)"

if [ -z "$bw_value" ] || [ -z "$bw_unit" ] ||
    [ -z "$size_value" ] || [ -z "$size_unit" ]; then
    echo "[FAIL] no camera bandwidth data"
    if [ "$bw_status" -ne 0 ] && [ "$bw_status" -ne 124 ]; then
        echo "[FAIL] ros2 topic bw exit code: $bw_status" >&2
    fi
    exit 1
fi

avg_size_kb="$(
    awk -v value="$size_value" -v unit="$size_unit" '
        BEGIN {
            if (unit == "B") {
                result = value / 1000
            } else if (unit == "KB") {
                result = value
            } else if (unit == "MB") {
                result = value * 1000
            } else {
                exit 1
            }
            printf "%.2f", result
        }
    '
)" || {
    echo "[FAIL] unsupported message-size unit: $size_unit"
    exit 1
}

avg_bw_mbps="$(
    awk -v value="$bw_value" -v unit="$bw_unit" '
        BEGIN {
            sub("/s$", "", unit)
            if (unit == "B") {
                bytes_per_second = value
            } else if (unit == "KB") {
                bytes_per_second = value * 1000
            } else if (unit == "MB") {
                bytes_per_second = value * 1000 * 1000
            } else {
                exit 1
            }
            printf "%.6f", bytes_per_second * 8 / 1000 / 1000
        }
    '
)" || {
    echo "[FAIL] unsupported bandwidth unit: $bw_unit"
    exit 1
}

if ! awk -v size="$avg_size_kb" -v bw="$avg_bw_mbps" \
    'BEGIN { exit !(size > 0 && bw > 0) }'; then
    echo "[FAIL] bandwidth statistics are not greater than zero"
    exit 1
fi

echo "[PASS] bandwidth statistics"
echo "avg_size_kb=$avg_size_kb"
echo "avg_bw_mbps=$avg_bw_mbps"

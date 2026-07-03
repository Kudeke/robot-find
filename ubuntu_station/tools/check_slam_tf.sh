#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p "$STATION_DIR/log"
export ROS_LOG_DIR="$STATION_DIR/log"
export PYTHONUNBUFFERED=1

set +u
source /opt/ros/jazzy/setup.bash
set -u

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
failures=0

check_transform() {
    local parent="$1"
    local child="$2"
    local label="$3"
    local output_file="$tmp_dir/${parent}_${child}.out"

    timeout --signal=INT --kill-after=2s 5s \
        ros2 run tf2_ros tf2_echo "$parent" "$child" >"$output_file" 2>&1
    local status=$?
    cat "$output_file"

    if grep -Eq 'At time|Translation:' "$output_file"; then
        echo "[PASS] $label"
    else
        echo "[FAIL] $label"
        failures=$((failures + 1))
        if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
            echo "[FAIL] tf2_echo exit code: $status" >&2
        fi
    fi
}

echo "[SLAM][TF] checking odom -> base_link"
check_transform "odom" "base_link" "TF odom -> base_link"

echo
echo "[SLAM][TF] checking odom -> utlidar_lidar"
lidar_failures_before="$failures"
check_transform "odom" "utlidar_lidar" "TF odom -> utlidar_lidar"
if [ "$failures" -gt "$lidar_failures_before" ]; then
    echo "[HINT] Start the LiDAR static TF first:"
    echo "[HINT] cd $STATION_DIR"
    echo "[HINT] ./start_lidar_tf.sh"
fi

if [ "$failures" -eq 0 ]; then
    echo
    echo "[PASS] SLAM TF tree"
    exit 0
fi

echo
echo "[FAIL] SLAM TF tree ($failures)"
exit 1

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

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
failures=0

check_transform() {
    local parent="$1"
    local child="$2"
    local output_file="$tmp_dir/${parent}_${child}.out"

    timeout --signal=INT --kill-after=2s 5s \
        ros2 run tf2_ros tf2_echo "$parent" "$child" >"$output_file" 2>&1
    local status=$?
    cat "$output_file"

    if grep -Eq 'At time|Translation:' "$output_file"; then
        echo "[PASS] TF $parent -> $child"
    else
        echo "[FAIL] TF $parent -> $child"
        failures=$((failures + 1))
        if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
            echo "[FAIL] tf2_echo exit code: $status" >&2
        fi
    fi
}

echo "[LIDAR][TF] checking base_link -> utlidar_lidar"
check_transform "base_link" "utlidar_lidar"

echo
echo "[LIDAR][TF] checking odom -> utlidar_lidar"
check_transform "odom" "utlidar_lidar"

if [ "$failures" -eq 0 ]; then
    echo
    echo "========================="
    echo "LIDAR TF PASSED"
    echo "========================="
    exit 0
fi

echo
echo "========================="
echo "LIDAR TF FAILED ($failures)"
echo "========================="
exit 1

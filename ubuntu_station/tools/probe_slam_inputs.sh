#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$STATION_DIR"

mkdir -p "$STATION_DIR/log"
export ROS_LOG_DIR="$STATION_DIR/log"
export PYTHONUNBUFFERED=1

set +u
source /opt/ros/jazzy/setup.bash
set -u

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
failures=0

measure_rate() {
    local label="$1"
    local topic="$2"
    local key="$3"
    local output_file="$tmp_dir/${key}_hz.out"

    timeout --signal=INT --kill-after=2s 5s \
        ros2 topic hz --wall-time "$topic" >"$output_file" 2>&1
    local status=$?
    local rate
    rate="$(
        awk '/average rate:/ { value=$3 } END { print value }' "$output_file"
    )"

    echo
    echo "===== $label ====="
    echo "topic=$topic"
    cat "$output_file"

    if [ -n "$rate" ] && awk -v rate="$rate" 'BEGIN { exit !(rate > 0) }'; then
        echo "[PASS] $label"
        echo "rate=${rate}Hz"
    else
        echo "[FAIL] $label"
        failures=$((failures + 1))
        if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
            echo "[FAIL] ros2 topic hz exit code: $status" >&2
        fi
    fi
}

echo "[SLAM] read-only input probe"
echo "[SLAM] no SLAM node is started"

echo
echo "===== Topic Check ====="
if "$SCRIPT_DIR/check_slam_topics.sh"; then
    echo "[PASS] SLAM topics"
else
    echo "[FAIL] SLAM topics"
    failures=$((failures + 1))
fi

measure_rate "Battery" "/battery_state" "battery"
measure_rate "IMU" "/remote/imu" "imu"
measure_rate "Odom" "/remote/odom" "odom"
measure_rate "Camera" "/remote/camera/color/compressed" "camera"

echo
echo "===== Camera Bandwidth ====="
camera_bw_output="$tmp_dir/camera_bw.out"
timeout --signal=INT --kill-after=2s 5s \
    ros2 topic bw --window 100 \
    "/remote/camera/color/compressed" >"$camera_bw_output" 2>&1
camera_bw_status=$?
cat "$camera_bw_output"

camera_bandwidth="$(
    awk '/\/s from [0-9]+ messages/ { value=$1 " " $2 } END { print value }' \
        "$camera_bw_output"
)"
camera_message_size="$(
    awk '/Message size mean:/ { value=$4 " " $5 } END { print value }' \
        "$camera_bw_output"
)"

if [ -n "$camera_bandwidth" ] && [ -n "$camera_message_size" ]; then
    echo "[PASS] Camera bandwidth"
    echo "bandwidth=$camera_bandwidth"
    echo "average_message_size=$camera_message_size"
else
    echo "[FAIL] Camera bandwidth"
    failures=$((failures + 1))
    if [ "$camera_bw_status" -ne 0 ] && [ "$camera_bw_status" -ne 124 ]; then
        echo "[FAIL] ros2 topic bw exit code: $camera_bw_status" >&2
    fi
fi

measure_rate "PointCloud" "/remote/lidar/points" "pointcloud"

echo
echo "===== TF Check ====="
if "$SCRIPT_DIR/check_slam_tf.sh"; then
    echo "[PASS] TF"
else
    echo "[FAIL] TF"
    failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
    echo
    echo "========================="
    echo "SLAM INPUTS PASSED"
    echo "========================="
    exit 0
fi

echo
echo "========================="
echo "SLAM INPUTS FAILED ($failures)"
echo "========================="
exit 1

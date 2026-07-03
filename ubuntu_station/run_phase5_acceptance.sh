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
failures=0
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

pass() {
    echo "[PASS] $1"
}

fail() {
    echo "[FAIL] $1"
    failures=$((failures + 1))
}

echo "[PHASE5] checking LiDAR topic"
topic_list_file="$tmp_dir/topic_list.txt"
if timeout 10s ros2 topic list >"$topic_list_file" 2>"$tmp_dir/topic_list.err" &&
    grep -Fxq "$topic" "$topic_list_file"; then
    pass "lidar topic exists"
    topic_exists=1
else
    fail "lidar topic exists"
    cat "$tmp_dir/topic_list.err" >&2
    topic_exists=0
fi

echo
echo "[PHASE5] measuring LiDAR frequency for 5 seconds"
hz_output="$tmp_dir/hz.out"
rate=""
if [ "$topic_exists" -eq 1 ]; then
    timeout --signal=INT --kill-after=2s 5s \
        ros2 topic hz --wall-time "$topic" >"$hz_output" 2>&1
    hz_status=$?
    cat "$hz_output"
    rate="$(
        awk '/average rate:/ { value=$3 } END { print value }' "$hz_output"
    )"

    if [ -n "$rate" ] && awk -v rate="$rate" 'BEGIN { exit !(rate >= 4.0) }'; then
        echo "lidar_rate_hz=$rate"
        pass "lidar frequency"
    else
        fail "lidar frequency"
        if [ "$hz_status" -ne 0 ] && [ "$hz_status" -ne 124 ]; then
            echo "[FAIL] ros2 topic hz exit code: $hz_status" >&2
        fi
    fi
else
    fail "lidar frequency"
fi

echo
echo "[PHASE5] checking PointCloud2 message"
echo_output="$tmp_dir/pointcloud.out"
pointcloud_ok=1
if [ "$topic_exists" -eq 1 ]; then
    timeout --signal=INT --kill-after=2s 3s \
        ros2 topic echo "$topic" --no-arr >"$echo_output" 2>&1
    echo_status=$?
    cat "$echo_output"

    for pattern in \
        'frame_id:.*utlidar_lidar' \
        '^height:' \
        '^width:' \
        '^point_step:' \
        '^row_step:' \
        '^is_dense:'; do
        if ! grep -Eq "$pattern" "$echo_output"; then
            pointcloud_ok=0
        fi
    done

    if [ "$pointcloud_ok" -eq 1 ]; then
        pass "pointcloud message"
    else
        fail "pointcloud message"
        if [ "$echo_status" -ne 0 ] && [ "$echo_status" -ne 124 ]; then
            echo "[FAIL] ros2 topic echo exit code: $echo_status" >&2
        fi
    fi
else
    fail "pointcloud message"
fi

echo
echo "[PHASE5] checking TF lidar_view -> utlidar_lidar"
tf_output="$tmp_dir/tf.out"
timeout --signal=INT --kill-after=2s 5s \
    ros2 run tf2_ros tf2_echo lidar_view utlidar_lidar >"$tf_output" 2>&1
tf_status=$?
cat "$tf_output"

if grep -Eq 'At time|Translation:' "$tf_output"; then
    pass "lidar tf"
else
    fail "lidar tf"
    if [ "$tf_status" -ne 0 ] && [ "$tf_status" -ne 124 ]; then
        echo "[FAIL] tf2_echo exit code: $tf_status" >&2
    fi
fi

echo
if [ "${RVIZ_CONFIRMED:-}" = "yes" ]; then
    rviz_answer="y"
elif [ -t 0 ]; then
    read -r -p "Does RViz2 display the point cloud continuously? [y/N] " \
        rviz_answer
else
    rviz_answer="n"
    echo "[MANUAL] RViz2 confirmation is required"
fi

case "$rviz_answer" in
    y|Y|yes|YES)
        pass "RViz2 displays point cloud"
        ;;
    *)
        fail "RViz2 displays point cloud"
        ;;
esac

if [ "$failures" -eq 0 ]; then
    echo
    echo "========================="
    echo "PHASE5 PASSED"
    echo "========================="
    exit 0
fi

echo
echo "========================="
echo "PHASE5 FAILED ($failures)"
echo "========================="
exit 1

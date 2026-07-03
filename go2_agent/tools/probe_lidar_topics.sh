#!/usr/bin/env bash
set -uo pipefail

set +u
# shellcheck disable=SC1091
source /opt/ros/foxy/setup.bash
set -u

echo "[GO2][LIDAR] read-only ROS2 topic probe"
echo "[GO2][LIDAR] this script does not start any driver"
echo
echo "===== ros2 topic list -t ====="

typed_topics="$(ros2 topic list -t 2>/dev/null || true)"
if [ -n "$typed_topics" ]; then
  printf '%s\n' "$typed_topics"
else
  echo "[GO2][LIDAR] no ROS2 topics found"
fi

topic_hz_supports_qos=0
if ros2 topic hz --help 2>&1 | grep -q -- "--qos-profile"; then
  topic_hz_supports_qos=1
fi

is_lidar_candidate() {
  local topic="$1"
  local topic_type="$2"
  local topic_lower="${topic,,}"

  case "$topic_type" in
    sensor_msgs/msg/LaserScan|sensor_msgs/msg/PointCloud2|sensor_msgs/msg/PointCloud)
      return 0
      ;;
  esac

  case "$topic_lower" in
    *scan*|*cloud*|*point*|*lidar*|*utlidar*|*velodyne*|*livox*)
      return 0
      ;;
  esac

  return 1
}

run_topic_hz() {
  local topic="$1"
  local -a command=(ros2 topic hz "$topic")

  if [ "$topic_hz_supports_qos" -eq 1 ]; then
    command+=(--qos-profile sensor_data)
  fi

  timeout --signal=INT --kill-after=2s 5s \
    env PYTHONUNBUFFERED=1 "${command[@]}"
}

echo
echo "===== LiDAR candidates ====="

found=0
while IFS= read -r line; do
  [ -n "$line" ] || continue

  topic="${line%% *}"
  topic_type="${line#* [}"
  topic_type="${topic_type%]}"

  if ! is_lidar_candidate "$topic" "$topic_type"; then
    continue
  fi

  found=$((found + 1))
  echo
  echo "[FOUND] topic=$topic"
  echo "[FOUND] type=$topic_type"
  echo "----- topic info -----"
  ros2 topic info "$topic" || true
  echo "----- topic hz (5 seconds) -----"
  run_topic_hz "$topic" || true
done <<<"$typed_topics"

if [ "$found" -eq 0 ]; then
  echo "[GO2][LIDAR] no LaserScan, PointCloud2, PointCloud, or LiDAR-named topics found"
fi

echo
echo "[GO2][LIDAR] candidate_count=$found"

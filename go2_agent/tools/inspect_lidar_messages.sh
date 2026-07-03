#!/usr/bin/env bash
set -uo pipefail

set +u
# shellcheck disable=SC1091
source /opt/ros/foxy/setup.bash
set -u

echo "[GO2][LIDAR] read-only message definition inspection"
echo "[GO2][LIDAR] this script does not start any driver"

typed_topics="$(ros2 topic list -t 2>/dev/null || true)"

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
  echo "===== $topic [$topic_type] ====="
  ros2 interface show "$topic_type" || true
done <<<"$typed_topics"

if [ "$found" -eq 0 ]; then
  echo "[GO2][LIDAR] no candidate message definitions found"
fi

echo
echo "[GO2][LIDAR] inspected_topic_count=$found"

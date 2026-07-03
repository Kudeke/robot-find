#!/usr/bin/env bash
set -uo pipefail

set +u
# shellcheck disable=SC1091
source /opt/ros/foxy/setup.bash
set -u

echo "[GO2][LIDAR] read-only LaserScan sample probe"
echo "[GO2][LIDAR] this script does not start any driver"

typed_topics="$(ros2 topic list -t 2>/dev/null || true)"

topic_echo_supports_qos=0
if ros2 topic echo --help 2>&1 | grep -q -- "--qos-profile"; then
  topic_echo_supports_qos=1
fi

echo_once() {
  local topic="$1"
  local -a command=(ros2 topic echo --once "$topic")

  if [ "$topic_echo_supports_qos" -eq 1 ]; then
    command+=(--qos-profile sensor_data)
  fi

  timeout --signal=INT --kill-after=2s 10s "${command[@]}"
}

found=0
while IFS= read -r line; do
  [ -n "$line" ] || continue

  topic="${line%% *}"
  topic_type="${line#* [}"
  topic_type="${topic_type%]}"

  if [ "$topic_type" != "sensor_msgs/msg/LaserScan" ]; then
    continue
  fi

  found=$((found + 1))
  echo
  echo "===== LaserScan: $topic ====="
  echo_once "$topic" || true
done <<<"$typed_topics"

if [ "$found" -eq 0 ]; then
  echo "[GO2][LIDAR] no sensor_msgs/msg/LaserScan topic found"
fi

echo
echo "[GO2][LIDAR] laserscan_topic_count=$found"

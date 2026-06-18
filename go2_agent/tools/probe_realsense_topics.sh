#!/usr/bin/env bash
set -uo pipefail

set +u
# shellcheck disable=SC1091
source /opt/ros/foxy/setup.bash
set -u

typed_topics="$(ros2 topic list -t 2>/dev/null || true)"

topic_hz_supports_qos=0
if ros2 topic hz --help 2>&1 | grep -q -- "--qos-profile"; then
  topic_hz_supports_qos=1
fi

run_topic_hz() {
  local topic="$1"
  local -a command=(ros2 topic hz "$topic")

  if [ "$topic_hz_supports_qos" -eq 1 ]; then
    command+=(--qos-profile sensor_data)
  fi

  timeout --signal=INT --kill-after=2s 5s \
    env PYTHONUNBUFFERED=1 "${command[@]}"
}

echo "[GO2][REALSENSE] auto-discovering camera topics"
echo "[GO2][REALSENSE] this script does not start the camera driver"

found=0
while IFS= read -r line; do
  [ -n "$line" ] || continue

  topic="${line%% *}"
  topic_type="${line#* [}"
  topic_type="${topic_type%]}"

  case "$topic_type" in
    sensor_msgs/msg/Image|sensor_msgs/msg/CompressedImage|sensor_msgs/msg/CameraInfo)
      ;;
    *)
      continue
      ;;
  esac

  case "$topic" in
    *camera*color*|*camera*depth*|*camera*infra*)
      ;;
    *)
      continue
      ;;
  esac

  found=$((found + 1))
  echo
  echo "[FOUND] $topic [$topic_type]"
  ros2 topic info "$topic" || true

  case "$topic_type" in
    sensor_msgs/msg/Image|sensor_msgs/msg/CompressedImage)
      echo "[GO2][REALSENSE] measuring image rate for 5 seconds"
      run_topic_hz "$topic" || true
      ;;
    sensor_msgs/msg/CameraInfo)
      echo "[GO2][REALSENSE] echoing camera info for 5 seconds"
      timeout 5s ros2 topic echo "$topic" || true
      ;;
  esac
done <<<"$typed_topics"

if [ "$found" -eq 0 ]; then
  echo "[GO2][REALSENSE] no matching camera topics found"
fi

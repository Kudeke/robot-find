#!/usr/bin/env bash
set -uo pipefail

set +u
# shellcheck disable=SC1091
source /opt/ros/foxy/setup.bash
set -u

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

find_topic() {
  local stream_name="$1"
  local wanted_kind="$2"
  local fallback=""

  while IFS= read -r line; do
    [ -n "$line" ] || continue

    local topic="${line%% *}"
    local topic_type="${line#* [}"
    topic_type="${topic_type%]}"

    case "$topic" in
      *camera*"$stream_name"*)
        ;;
      *)
        continue
        ;;
    esac

    if [ "$wanted_kind" = "info" ]; then
      if [ "$topic_type" = "sensor_msgs/msg/CameraInfo" ]; then
        echo "$topic"
        return 0
      fi
    else
      if [ "$topic_type" = "sensor_msgs/msg/Image" ]; then
        echo "$topic"
        return 0
      fi
      if [ "$topic_type" = "sensor_msgs/msg/CompressedImage" ] && [ -z "$fallback" ]; then
        fallback="$topic"
      fi
    fi
  done <<<"$typed_topics"

  if [ -n "$fallback" ]; then
    echo "$fallback"
    return 0
  fi
  return 1
}

check_image_topic() {
  local label="$1"
  local topic="$2"
  local output_file="$tmp_dir/${label// /_}_hz.txt"

  ros2 topic info "$topic" >"$tmp_dir/${label// /_}_info.txt" 2>&1 || true
  run_topic_hz "$topic" >"$output_file" 2>&1 || true

  if grep -Eq "average rate:|min:.*max:|std dev:" "$output_file"; then
    pass "$label topic: $topic"
  else
    fail "$label topic: $topic (no frequency data)"
    cat "$output_file" >&2
  fi
}

check_info_topic() {
  local label="$1"
  local topic="$2"
  local output_file="$tmp_dir/${label// /_}_echo.txt"

  ros2 topic info "$topic" >"$tmp_dir/${label// /_}_info.txt" 2>&1 || true
  timeout 5s ros2 topic echo "$topic" >"$output_file" 2>&1 || true

  if [ -s "$output_file" ] && grep -Eq "header:|height:|width:|distortion_model:|k:" "$output_file"; then
    pass "$label: $topic"
  else
    fail "$label: $topic (no CameraInfo data)"
    cat "$output_file" >&2
  fi
}

color_image="$(find_topic color image || true)"
depth_image="$(find_topic depth image || true)"
color_info="$(find_topic color info || true)"
depth_info="$(find_topic depth info || true)"

if [ -n "$color_image" ]; then
  check_image_topic "color image" "$color_image"
else
  fail "color image topic"
fi

if [ -n "$depth_image" ]; then
  check_image_topic "depth image" "$depth_image"
else
  fail "depth image topic"
fi

if [ -n "$color_info" ]; then
  check_info_topic "color camera_info" "$color_info"
else
  fail "color camera_info"
fi

if [ -n "$depth_info" ]; then
  check_info_topic "depth camera_info" "$depth_info"
else
  fail "depth camera_info"
fi

if [ "$failures" -eq 0 ]; then
  echo
  echo "========================="
  echo "REALSENSE PIPELINE PASSED"
  echo "========================="
  exit 0
fi

echo
echo "========================="
echo "REALSENSE PIPELINE FAILED"
echo "========================="
exit 1

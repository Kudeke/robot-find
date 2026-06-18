#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /topic_name" >&2
  exit 2
fi

topic_name="$1"

source_if_exists() {
  local setup_file="$1"
  if [ -f "$setup_file" ]; then
    # shellcheck disable=SC1090
    source "$setup_file"
    echo "[GO2][DDS_PROBE] sourced $setup_file"
  else
    echo "[GO2][DDS_PROBE] missing $setup_file"
  fi
}

set +u
source_if_exists /opt/ros/foxy/setup.bash
source_if_exists /opt/mybotshop/setup.bash
set -u

echo "[GO2][DDS_PROBE] ros2 topic info $topic_name"
ros2 topic info "$topic_name"

echo "[GO2][DDS_PROBE] ros2 topic echo --once $topic_name"
timeout 3s ros2 topic echo --once "$topic_name"

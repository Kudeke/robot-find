#!/usr/bin/env bash
set -u

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

echo "[GO2][DDS_PROBE] ros2 topic list"
ros2 topic list || true

echo "[GO2][DDS_PROBE] ros2 topic list -t"
ros2 topic list -t || true

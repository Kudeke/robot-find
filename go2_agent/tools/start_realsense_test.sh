#!/usr/bin/env bash
set -euo pipefail

set +u
# shellcheck disable=SC1091
source /opt/ros/foxy/setup.bash
set -u

echo "[GO2][REALSENSE] starting read-only camera driver"
echo "[GO2][REALSENSE] no robot control"
echo "[GO2][REALSENSE] no WebSocket streaming yet"

if ! ros2 pkg prefix realsense2_camera >/dev/null 2>&1; then
  echo "[GO2][REALSENSE] realsense2_camera package not found" >&2
  exit 1
fi

if ros2 launch realsense2_camera rs_launch.py; then
  exit 0
fi

echo "[GO2][REALSENSE] rs_launch.py failed, trying rs_camera.launch.py" >&2
exec ros2 launch realsense2_camera rs_camera.launch.py

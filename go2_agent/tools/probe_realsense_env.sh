#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/realsense_env_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

run_section() {
  local title="$1"
  shift
  echo
  echo "===== $title ====="
  "$@" || true
}

{
  echo "[GO2][REALSENSE] environment probe"
  echo "[GO2][REALSENSE] read-only, no robot control, no WebSocket streaming"
  echo "[GO2][REALSENSE] timestamp=$(date --iso-8601=seconds)"

  run_section "uname -a" uname -a

  echo
  echo "===== operating system ====="
  if command -v lsb_release >/dev/null 2>&1; then
    lsb_release -a || true
  elif [ -f /etc/os-release ]; then
    cat /etc/os-release
  else
    echo "No lsb_release or /etc/os-release found"
  fi

  run_section "lsusb" lsusb

  echo
  echo "===== video devices ====="
  ls -l /dev/video* 2>/dev/null || true

  echo
  echo "===== v4l2 tools ====="
  command -v v4l2-ctl || true
  if command -v v4l2-ctl >/dev/null 2>&1; then
    v4l2-ctl --list-devices || true
  fi

  echo
  echo "===== RealSense tools ====="
  command -v realsense-viewer || true
  command -v rs-enumerate-devices || true
  if command -v rs-enumerate-devices >/dev/null 2>&1; then
    rs-enumerate-devices || true
  fi

  echo
  echo "===== ROS2 Foxy RealSense packages ====="
  if [ -f /opt/ros/foxy/setup.bash ]; then
    set +u
    # shellcheck disable=SC1091
    source /opt/ros/foxy/setup.bash
    set -u
    ros2 pkg list 2>/dev/null | grep -i realsense || true
    ros2 pkg list 2>/dev/null | grep -i librealsense || true
  else
    echo "missing /opt/ros/foxy/setup.bash"
  fi

  echo
  echo "===== current ROS2 topics ====="
  if command -v ros2 >/dev/null 2>&1; then
    ros2 topic list -t || true
  else
    echo "ros2 command not found"
  fi
} 2>&1 | tee "$LOG_FILE"

echo "[GO2][REALSENSE] log saved to $LOG_FILE"

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
log_dir="$script_dir/logs"
timestamp="$(date +%Y%m%d_%H%M%S)"
log_file="$log_dir/unitree_messages_${timestamp}.log"

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

mkdir -p "$log_dir"

set +u
source_if_exists /opt/ros/foxy/setup.bash
source_if_exists /opt/mybotshop/setup.bash
set -u

{
  echo "===== unitree_go/msg/LowState ====="
  ros2 interface show unitree_go/msg/LowState
  echo
  echo "===== unitree_go/msg/SportModeState ====="
  ros2 interface show unitree_go/msg/SportModeState
} 2>&1 | tee "$log_file"

echo "[GO2][DDS_PROBE] message definitions saved to $log_file"

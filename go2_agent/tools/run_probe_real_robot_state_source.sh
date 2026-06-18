#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

set +u
source /opt/ros/foxy/setup.bash
set -u

python3 tools/probe_real_robot_state_source.py

#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

set +u
# shellcheck disable=SC1091
source /opt/ros/foxy/setup.bash
set -u

python3 tools/probe_camera_capture.py

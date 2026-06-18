#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

set +u
source /opt/ros/foxy/setup.bash
set -u

exec python3 main.py

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RVIZ_FILE="$SCRIPT_DIR/rviz/lidar_only.rviz"

if [ -f "$RVIZ_FILE" ]; then
    echo "[OK] RViz configuration exists:"
    echo "$RVIZ_FILE"
    exit 0
fi

echo "Please save the current RViz configuration to:"
echo "$RVIZ_FILE"
exit 1

#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

failures=0

echo "[PHASE4] checking camera topic and frequency"
if "$SCRIPT_DIR/check_camera_pipeline.sh"; then
    echo "[PASS] camera pipeline"
else
    echo "[FAIL] camera pipeline"
    failures=$((failures + 1))
fi

echo
echo "[PHASE4] measuring camera bandwidth"
if "$SCRIPT_DIR/measure_camera_bandwidth.sh"; then
    echo "[PASS] camera bandwidth"
else
    echo "[FAIL] camera bandwidth"
    failures=$((failures + 1))
fi

echo
if [ "${RVIZ_CONFIRMED:-}" = "yes" ]; then
    rviz_answer="y"
elif [ -t 0 ]; then
    read -r -p "Does RViz2 continuously display the remote color image? [y/N] " \
        rviz_answer
else
    rviz_answer="n"
    echo "[MANUAL] RViz2 confirmation is required"
fi

case "$rviz_answer" in
    y|Y|yes|YES)
        echo "[PASS] RViz2 displays the camera image"
        ;;
    *)
        echo "[FAIL] RViz2 display not confirmed"
        failures=$((failures + 1))
        ;;
esac

if [ "$failures" -eq 0 ]; then
    echo
    echo "========================="
    echo "PHASE4 PASSED"
    echo "========================="
    exit 0
fi

echo
echo "========================="
echo "PHASE4 FAILED ($failures)"
echo "========================="
exit 1

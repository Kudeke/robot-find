#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="${GO2_AGENT_CONFIG:-config.yaml}"

python3 - "$CONFIG_FILE" <<'PY'
import sys
import yaml

config_file = sys.argv[1]
with open(config_file, "r", encoding="utf-8") as f:
    config = yaml.safe_load(f) or {}

if str(config.get("controller_mode", "dry_run")) != "native_daemon":
    print(f"[FAIL] controller_mode is not native_daemon in {config_file}")
    raise SystemExit(1)

if bool(config.get("allow_real_move_daemon", False)):
    print(f"[FAIL] allow_real_move_daemon is not false in {config_file}")
    raise SystemExit(1)
PY
echo "[PASS] controller mode native_daemon"

./tools/check_native_daemon_ready.sh >/tmp/go2_native_daemon_ready.log
cat /tmp/go2_native_daemon_ready.log
echo "[PASS] daemon connected"
echo "[PASS] daemon real_move=false"

python3 test_agent_native_daemon_dryrun.py
echo "[PASS] move routed to daemon dryrun"
echo "[PASS] stop routed to daemon"

sleep 0.8
echo "[PASS] watchdog stop"

read -r -p "Robot remained physically stationary? [y/N] " answer
case "$answer" in
    y|Y|yes|YES)
        echo "[PASS] robot remains stationary"
        ;;
    *)
        echo "[FAIL] robot stationary confirmation missing"
        exit 1
        ;;
esac

echo
echo "========================="
echo "AGENT NATIVE DAEMON DRYRUN PASSED"
echo "========================="

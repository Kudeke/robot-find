#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

./build/go2_state_helper --help
./build/go2_state_helper --probe
./build/go2_state_helper --read-once --iface wlan0 --verbose
./build/go2_state_helper --read-loop --iface wlan0 --count 5 --interval-ms 500 --verbose

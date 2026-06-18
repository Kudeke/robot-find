# GO2 Sport Helper

Phase2-E adds a small native C++ helper for probing the Unitree SDK2 C++
SportClient environment.

This helper is not connected to the Python `go2_agent` runtime yet.

## Safety Boundary

The helper does not implement real movement in this phase.

- `--help` does not initialize SDK2.
- `--probe` does not initialize SDK2.
- `--dry-run move ...` only prints parameters.
- `--dry-run stop` only prints stop.
- Non-dry-run `move` is rejected.
- `--stop-only --iface <network_interface>` is the only mode that initializes
  SDK2, and it only calls `StopMove()`.

This phase must not call `Move()` and must not make GO2 move.

## Build

Run on GO2:

```bash
cd ~/go2_agent/native
./build_helper.sh
```

The expected SDK2 root is:

```text
/home/unitree/unitree_sdk/src/04Aug2025_unitree_sdk2
```

## Safe Tests

These commands do not initialize SDK2 and do not control the robot:

```bash
./build/go2_sport_helper --help
./build/go2_sport_helper --probe
./build/go2_sport_helper --dry-run move --vx 0.1 --vy 0.0 --yaw 0.0
./build/go2_sport_helper --dry-run stop
```

## Stop-Only SDK2 Probe

This command initializes SDK2 and only sends a stop command:

```bash
./build/go2_sport_helper --stop-only --iface wlan0
```

`--stop-only` is only for validating SDK2 initialization and `StopMove()`.
It does not call `Move()`.

## Phase3-A RobotState Read-Only Probe

Phase3-A adds `go2_state_helper`, a read-only SDK2 helper for probing
`RobotStateClient` data access. It does not call `Move`, `StopMove`, `Stand`,
`Sit`, `BalanceStand`, `Damp`, or any other motion control command.

Build on GO2:

```bash
cd ~/go2_agent/native
./build_helper.sh
```

Test on GO2:

```bash
./test_state_helper.sh
```

Equivalent manual commands:

```bash
./build/go2_state_helper --help
./build/go2_state_helper --probe
./build/go2_state_helper --read-once --iface wlan0
./build/go2_state_helper --read-loop --iface wlan0 --count 5 --interval-ms 500
```

The helper initializes SDK2 only for `--read-once` and `--read-loop`, then calls
the read-only `RobotStateClient::ServiceList(...)` path and prints the return
code plus available service state fields. Battery, temperature, and error-code
fields are printed as unavailable if they are not exposed by this SDK2 client.

# GO2 Real Move Acceptance

This is the first real SDK2 `SportClient.Move()` acceptance test.

It does not use:

- Uni-NaVid
- WebSocket
- Safety Gate
- Native Motion Daemon

It directly runs:

```text
ChannelFactory
→ SportClient
→ SwitchJoystick(false)
→ StandUp
→ BalanceStand
→ SpeedLevel(1)
→ ClassicWalk(true)
→ Move(vx, 0.0, 0.0)
→ StopMove
→ ClassicWalk(false)
→ SwitchJoystick(true)
```

## Safety steps

1. Put the robot in an open area.
2. Confirm at least 2 meters in front of the robot are clear.
3. Prepare emergency stop.
4. Confirm the robot is stable.
5. Build on GO2:

   ```bash
   cd ~/go2_agent/native
   ./build_helper.sh
   ```

6. Run:

   ```bash
   export GO2_REAL_MOVE_ACK=YES
   ./run_real_move_acceptance.sh
   ```

   Optional parameters:

   ```bash
   GO2_REAL_MOVE_VX=0.50 \
   GO2_REAL_MOVE_DURATION_SEC=7.0 \
   ./run_real_move_acceptance.sh
   ```

7. The program waits for:

   ```text
   YES
   ```

8. Type exactly:

   ```text
   YES
   ```

9. Expected robot behavior:

   ```text
   stand up
   default: move forward at 0.30 m/s for 0.5 second
   default: travel approximately 15 cm
   stop immediately
   ```

10. If anything looks wrong, press `Ctrl+C` or emergency stop.

## Expected output

```text
[REAL TEST] SDK2 initialized
==================================================
REAL GO2 MOVE TEST
==================================================
Robot WILL MOVE.
...
[REAL TEST] SwitchJoystick false
[REAL TEST] StandUp
[REAL TEST] BalanceStand
[REAL TEST] SpeedLevel 1
[REAL TEST] ClassicWalk true
[REAL TEST] Move
[REAL TEST] StopMove
[REAL TEST] ClassicWalk false
[REAL TEST] SwitchJoystick true
==================================================
REAL MOVE COMPLETE
==================================================
```

## Safety boundary

This test is intentionally separate from all dryrun software-routing stages.
Do not run it through Uni-NaVid, WebSocket, Safety Gate, or the Native Motion
Daemon.

The test disables joystick control only during the short acceptance window and
restores it before exit, including cancellation and exception cleanup paths.

import os
import sys
import time

from controller import NativeDaemonController
from native_motion_controller import NativeMotionController


def _parse_float_env(name, default):
    value = os.environ.get(name, str(default))
    try:
        parsed = float(value)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be numeric, got {value!r}") from exc
    return parsed


def main():
    if os.environ.get("GO2_REAL_MOVE_ACK") != "YES":
        raise RuntimeError("export GO2_REAL_MOVE_ACK=YES")

    socket_path = os.environ.get("GO2_MOTION_SOCKET", "/tmp/go2_motion_daemon.sock")
    vx = _parse_float_env("GO2_AGENT_REAL_VX", 0.30)
    duration_sec = _parse_float_env("GO2_AGENT_REAL_DURATION_SEC", 0.5)

    if vx <= 0.0 or vx > 0.50:
        raise RuntimeError("GO2_AGENT_REAL_VX must be > 0.0 and <= 0.50")
    if duration_sec <= 0.0 or duration_sec > 7.0:
        raise RuntimeError("GO2_AGENT_REAL_DURATION_SEC must be > 0.0 and <= 7.0")

    print("==================================================")
    print("GO2 AGENT NATIVE DAEMON REAL MOVE TEST")
    print("==================================================")
    print()
    print("Robot WILL MOVE through:")
    print("NativeDaemonController -> NativeMotionController -> Unix Socket daemon")
    print()
    print("This test does NOT use WebSocket, Ubuntu, Safety Gate, or Uni-NaVid.")
    print()
    print("Expected motion:")
    print("forward")
    print(f"{vx} m/s")
    print(f"{duration_sec} second")
    print(f"about {vx * duration_sec} m")
    print()
    print("Emergency stop must be available.")
    print()
    print("Type YES to continue.")
    print()
    print("==================================================")

    answer = input().strip()
    if answer != "YES":
        print("[REAL AGENT TEST] cancelled")
        raise SystemExit(1)

    motion_controller = NativeMotionController(
        socket_path=socket_path,
        connect_timeout_sec=2.0,
        request_timeout_sec=1.0,
    )

    if not motion_controller.connect():
        raise RuntimeError("cannot connect to native motion daemon")

    status = motion_controller.status()
    print(f"[PASS] status {status}")
    if status.get("type") != "status" or not status.get("connected", False):
        raise RuntimeError(f"invalid daemon status: {status}")
    if not bool(status.get("real_move_enabled", False)):
        raise RuntimeError("daemon real_move_enabled=false; real acceptance refused")

    controller = NativeDaemonController(motion_controller=motion_controller)
    try:
        end = time.monotonic() + duration_sec
        count = 0
        while time.monotonic() < end:
            ack = controller.move(vx, 0.0, 0.0)
            if ack is None or ack.get("type") != "move_ack" or not ack.get("accepted", False):
                raise RuntimeError(f"move was not accepted: {ack}")
            if not bool(ack.get("real_move", False)):
                raise RuntimeError(f"daemon reported real_move=false: {ack}")
            count += 1
            time.sleep(0.05)
        print(f"[PASS] real moves routed by NativeDaemonController count={count}")

        stop_ack = controller.stop()
        if stop_ack is None or stop_ack.get("type") != "stop_ack":
            raise RuntimeError(f"stop failed: {stop_ack}")
        print(f"[PASS] stop routed by NativeDaemonController {stop_ack}")
    finally:
        controller.close()

    print()
    moved = input("Robot moved and stopped as expected? [y/N] ").strip()
    if moved not in ("y", "Y", "yes", "YES"):
        raise RuntimeError("robot real motion confirmation missing")

    print("[PASS] robot real motion confirmed")
    print()
    print("=========================")
    print("AGENT NATIVE DAEMON REAL MOVE PASSED")
    print("=========================")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        raise SystemExit(1)

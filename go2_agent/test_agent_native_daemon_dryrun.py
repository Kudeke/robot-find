import time

from controller import NativeDaemonController
from native_motion_controller import NativeMotionController


def main():
    motion_controller = NativeMotionController(
        socket_path="/tmp/go2_motion_daemon.sock",
        connect_timeout_sec=2.0,
        request_timeout_sec=1.0,
    )

    if not motion_controller.connect():
        raise RuntimeError("cannot connect to native motion daemon")

    status = motion_controller.status()
    print(f"[PASS] status {status}")
    if status.get("type") != "status" or not status.get("connected", False):
        raise RuntimeError(f"invalid daemon status: {status}")
    if bool(status.get("real_move_enabled", False)):
        raise RuntimeError("daemon real_move_enabled=true; dryrun test refused")

    controller = NativeDaemonController(motion_controller=motion_controller)
    try:
        ack = controller.move(0.05, 0.0, 0.0)
        if ack is None or ack.get("type") != "move_ack" or not ack.get("accepted", False):
            raise RuntimeError(f"move was not accepted: {ack}")
        if bool(ack.get("real_move", False)):
            raise RuntimeError(f"daemon reported real_move=true: {ack}")
        print(f"[PASS] move routed to daemon dryrun {ack}")

        time.sleep(0.8)
        print("[PASS] watchdog window elapsed")

        stop_ack = controller.stop()
        if stop_ack is None or stop_ack.get("type") != "stop_ack":
            raise RuntimeError(f"stop failed: {stop_ack}")
        print(f"[PASS] stop routed to daemon {stop_ack}")
    finally:
        controller.close()

    print()
    print("=========================")
    print("AGENT NATIVE DAEMON DRYRUN PASSED")
    print("=========================")


if __name__ == "__main__":
    main()

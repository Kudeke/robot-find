from native_motion_controller import NativeMotionController


def main():
    controller = NativeMotionController(
        socket_path="/tmp/go2_motion_daemon.sock",
        connect_timeout_sec=2.0,
        request_timeout_sec=1.0,
    )
    try:
        if not controller.connect():
            raise SystemExit("[FAIL] connect")
        status = controller.status()
        print(f"[PASS] status {status}")
        move_ack = controller.move(0.05, 0.0, 0.0)
        print(f"[PASS] move {move_ack}")
        stop_ack = controller.stop()
        print(f"[PASS] stop {stop_ack}")
    finally:
        controller.close()

    print()
    print("=========================")
    print("NATIVE MOTION CONTROLLER DRYRUN PASSED")
    print("=========================")


if __name__ == "__main__":
    main()

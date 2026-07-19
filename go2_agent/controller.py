class DryRunController:
    def __init__(self, dry_run=True):
        self.dry_run = bool(dry_run)
        self._stopped = True

    def move(self, vx, vy, yaw_rate):
        if not self.dry_run:
            print("[GO2][WARN] real controller not implemented yet")
            return
        self._stopped = (
            abs(float(vx)) <= 1e-6
            and abs(float(vy)) <= 1e-6
            and abs(float(yaw_rate)) <= 1e-6
        )
        print(f"[GO2][DRYRUN] move vx={vx} vy={vy} yaw_rate={yaw_rate}")

    def stop(self):
        if not self.dry_run:
            print("[GO2][WARN] real controller not implemented yet")
            return
        if self._stopped:
            return
        self._stopped = True
        print("[GO2][DRYRUN] stop")


class SafeController:
    def __init__(self, dry_run_controller, native_stop_controller=None):
        self.dry_run_controller = dry_run_controller
        self.native_stop_controller = native_stop_controller

    def move(self, vx, vy, yaw_rate):
        self.dry_run_controller.move(vx, vy, yaw_rate)

    def stop(self):
        self.dry_run_controller.stop()
        if self.native_stop_controller is not None:
            self.native_stop_controller.stop()


class NativeDaemonController:
    def __init__(self, motion_controller, fallback_stop_controller=None, native_stop_controller=None):
        self.motion_controller = motion_controller
        self.fallback_stop_controller = (
            fallback_stop_controller
            if fallback_stop_controller is not None
            else native_stop_controller
        )
        self._closed = False

    def move(self, vx, vy, yaw_rate):
        print(f"[GO2][NATIVE_DAEMON] move vx={vx} vy={vy} yaw_rate={yaw_rate}")
        try:
            ack = self.motion_controller.move(vx, vy, yaw_rate)
        except Exception as exc:
            print(f"[GO2][NATIVE_DAEMON][ERROR] move failed: {exc}")
            self.stop()
            return None

        if ack.get("type") != "move_ack" or not ack.get("accepted", False):
            print(f"[GO2][NATIVE_DAEMON][ERROR] move rejected: {ack}")
            self.stop()
            return ack

        seq = ack.get("seq")
        real_move = bool(ack.get("real_move", False))
        print(f"[GO2][NATIVE_DAEMON] move ack seq={seq} real_move={str(real_move).lower()}")
        if real_move:
            print("[GO2][NATIVE_DAEMON][WARN] daemon reports real_move=true")
        return ack

    def stop(self):
        print("[GO2][NATIVE_DAEMON] stop")
        try:
            return self.motion_controller.stop()
        except Exception as exc:
            print(f"[GO2][NATIVE_DAEMON][ERROR] stop failed: {exc}")
            if self.fallback_stop_controller is not None:
                self.fallback_stop_controller.stop()
                print("[GO2][NATIVE_DAEMON] fallback NativeStopController used")
            return None

    def close(self):
        if self._closed:
            return
        self._closed = True
        try:
            self.stop()
        finally:
            self.motion_controller.close()

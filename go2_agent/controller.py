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

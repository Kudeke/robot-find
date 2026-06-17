import os
import subprocess
from pathlib import Path


class NativeStopController:
    def __init__(self, helper_path, network_interface, enabled=True, timeout_sec=15.0):
        self.helper_path = helper_path
        self.network_interface = network_interface
        self.enabled = bool(enabled)
        self.timeout_sec = float(timeout_sec)

    def stop(self):
        if not self.enabled:
            print("[GO2][NATIVE_STOP] disabled")
            return

        resolved_helper_path = Path(self.helper_path).resolve()
        helper_cwd = resolved_helper_path.parent
        command = [
            str(resolved_helper_path),
            "--stop-only",
            "--iface",
            self.network_interface,
        ]

        print("[GO2][NATIVE_STOP] executing helper")
        print(f"[GO2][NATIVE_STOP] helper_path={self.helper_path}")
        print(f"[GO2][NATIVE_STOP] resolved_helper_path={resolved_helper_path}")
        print(f"[GO2][NATIVE_STOP] cwd={os.getcwd()}")
        print(f"[GO2][NATIVE_STOP] helper_cwd={helper_cwd}")
        print(f"[GO2][NATIVE_STOP] command={command}")
        print(f"[GO2][NATIVE_STOP] timeout_sec={self.timeout_sec}")

        if not resolved_helper_path.is_file():
            print(f"[GO2][NATIVE_STOP] error: helper file does not exist: {resolved_helper_path}")
            return

        try:
            result = subprocess.run(
                command,
                cwd=str(helper_cwd),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=self.timeout_sec,
                text=True,
                check=False,
            )
            print(f"[GO2][NATIVE_STOP] returncode={result.returncode}")
            print("[GO2][NATIVE_STOP] stdout:")
            print(result.stdout.rstrip() if result.stdout else "")
            print("[GO2][NATIVE_STOP] stderr:")
            print(result.stderr.rstrip() if result.stderr else "")
        except subprocess.TimeoutExpired as exc:
            print(f"[GO2][NATIVE_STOP] timeout after {self.timeout_sec}s")
            print("[GO2][NATIVE_STOP] stdout:")
            if exc.stdout:
                print(exc.stdout.rstrip() if isinstance(exc.stdout, str) else exc.stdout)
            else:
                print("")
            print("[GO2][NATIVE_STOP] stderr:")
            if exc.stderr:
                print(exc.stderr.rstrip() if isinstance(exc.stderr, str) else exc.stderr)
            else:
                print("")
        except Exception as exc:
            print(f"[GO2][NATIVE_STOP] error: {exc}")

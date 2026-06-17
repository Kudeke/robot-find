import os

import yaml

from native_stop_controller import NativeStopController


def load_config(path="config.yaml"):
    with open(path, "r", encoding="utf-8") as file_obj:
        return yaml.safe_load(file_obj) or {}


def main():
    config = load_config()
    helper_path = config.get("native_stop_helper_path", "./native/build/go2_sport_helper")
    network_interface = config.get("native_stop_interface", "wlan0")
    timeout_sec = float(config.get("native_stop_timeout_sec", 15.0))

    print(f"[GO2][TEST_NATIVE_STOP] cwd={os.getcwd()}")
    print(f"[GO2][TEST_NATIVE_STOP] helper_path={helper_path}")
    print(f"[GO2][TEST_NATIVE_STOP] native_stop_interface={network_interface}")
    print(f"[GO2][TEST_NATIVE_STOP] native_stop_timeout_sec={timeout_sec}")

    controller = NativeStopController(
        helper_path=helper_path,
        network_interface=network_interface,
        enabled=True,
        timeout_sec=timeout_sec,
    )
    controller.stop()


if __name__ == "__main__":
    main()

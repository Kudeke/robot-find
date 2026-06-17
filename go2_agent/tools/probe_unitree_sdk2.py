#!/usr/bin/env python3
import importlib
import platform
import sys


CANDIDATE_PATHS = [
    "/home/unitree/repo/qre_go2-foxy-nvidia/src/third_party/unitree/20Jan2026_unitree_sdk2_python",
    "/home/unitree/quadruped_repo/unitree/20Jan2026_unitree_sdk2_python",
]


def print_python_environment():
    print("[PROBE] Python version:")
    print(sys.version)
    print(f"[PROBE] platform: {platform.platform()}")
    print("[PROBE] sys.path:")
    for path in sys.path:
        print(f"  {path}")


def try_import(module_name):
    try:
        module = importlib.import_module(module_name)
        print(f"[PROBE] import ok: {module_name}")
        return module
    except Exception as exc:
        print(f"[PROBE] import failed: {module_name}: {exc}")
        return None


def add_candidate_paths():
    print("[PROBE] adding candidate SDK2 Python paths:")
    for path in CANDIDATE_PATHS:
        if path not in sys.path:
            sys.path.insert(0, path)
            print(f"  added: {path}")
        else:
            print(f"  already in sys.path: {path}")


def main():
    print("[PROBE] Unitree SDK2 Python import probe")
    print("[PROBE] safe mode: no InitChannel, no SportClient call, no robot control")
    print_python_environment()

    sdk_module = try_import("unitree_sdk2py")
    if sdk_module is None:
        add_candidate_paths()
        sdk_module = try_import("unitree_sdk2py")

    channel_module = try_import("unitree_sdk2py.core.channel")
    sport_module = try_import("unitree_sdk2py.go2.sport.sport_client")
    robot_state_module = try_import("unitree_sdk2py.go2.robot_state.robot_state_client")

    if sdk_module is not None:
        print("[PROBE] unitree_sdk2py import ok")
    else:
        print("[PROBE] unitree_sdk2py import failed")

    sport_client = getattr(sport_module, "SportClient", None) if sport_module is not None else None
    robot_state_client = (
        getattr(robot_state_module, "RobotStateClient", None)
        if robot_state_module is not None
        else None
    )

    print(f"[PROBE] SportClient exists: {sport_client is not None}")
    print(f"[PROBE] RobotStateClient exists: {robot_state_client is not None}")

    if channel_module is not None:
        print("[PROBE] channel module import ok")

    print("[PROBE] done")


if __name__ == "__main__":
    main()

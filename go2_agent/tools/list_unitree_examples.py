#!/usr/bin/env python3
import os


EXAMPLE_DIRS = [
    "/home/unitree/unitree_sdk/src/04Aug2025_unitree_sdk2/example/go2",
    "/home/unitree/unitree_sdk/src/04Aug2025_unitree_sdk2/build/bin",
    "/home/unitree/repo/qre_go2-foxy-nvidia/src/third_party/unitree/20Jan2026_unitree_sdk2_python/example/go2",
    "/home/unitree/quadruped_repo/unitree/20Jan2026_unitree_sdk2_python/example/go2",
]

KEYWORDS = ("sport", "robot_state", "robotstate", "video", "lowlevel", "low_level")


def is_interesting_file(filename):
    lower_name = filename.lower()
    return any(keyword in lower_name for keyword in KEYWORDS)


def list_interesting_files(root_dir):
    matches = []
    for current_root, _dirs, files in os.walk(root_dir):
        for filename in files:
            if is_interesting_file(filename):
                matches.append(os.path.join(current_root, filename))
    return sorted(matches)


def main():
    print("[PROBE] Unitree SDK2 example directory scan")
    print("[PROBE] safe mode: listing files only, no SDK initialization, no robot control")

    for directory in EXAMPLE_DIRS:
        print(f"[PROBE] directory: {directory}")
        if not os.path.isdir(directory):
            print("  missing")
            continue

        print("  exists")
        matches = list_interesting_files(directory)
        if not matches:
            print("  no sport / robot_state / video / lowlevel files found")
            continue

        for path in matches:
            print(f"  {path}")

    print("[PROBE] done")


if __name__ == "__main__":
    main()

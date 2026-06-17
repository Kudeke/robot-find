#!/usr/bin/env python3
import os


EXAMPLE_FILES = [
    "/home/unitree/repo/qre_go2-foxy-nvidia/src/third_party/unitree/20Jan2026_unitree_sdk2_python/example/go2/high_level/go2_sport_client.py",
    "/home/unitree/quadruped_repo/unitree/20Jan2026_unitree_sdk2_python/example/go2/high_level/go2_sport_client.py",
]

KEYWORDS = [
    "import ",
    "InitChannel",
    "SportClient",
    "Move",
    ".move",
    "move(",
    "Stop",
    ".stop",
    "stop(",
    "StandDown",
    "BalanceStand",
    "Damp",
]


def line_matches(line):
    return any(keyword in line for keyword in KEYWORDS)


def inspect_file(path):
    print(f"[PROBE] file: {path}")
    if not os.path.isfile(path):
        print("  missing")
        return

    print("  exists")
    print("  matched lines:")
    found = False
    with open(path, "r", encoding="utf-8", errors="replace") as file_obj:
        for line_number, line in enumerate(file_obj, start=1):
            stripped = line.rstrip("\n")
            if line_matches(stripped):
                found = True
                print(f"  {line_number}: {stripped}")

    if not found:
        print("  no matching lines found")


def main():
    print("[PROBE] GO2 Python sport example inspector")
    print("[PROBE] safe mode: reading files only, examples are not executed")
    print("[PROBE] no InitChannel call, no SportClient instance, no robot control")

    for path in EXAMPLE_FILES:
        inspect_file(path)

    print("[PROBE] done")


if __name__ == "__main__":
    main()

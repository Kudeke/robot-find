#!/usr/bin/env python3
import os
import re


CPP_PATH = "/home/unitree/unitree_sdk/src/04Aug2025_unitree_sdk2/example/go2/go2_robot_state_client.cpp"

KEYWORDS = (
    "#include",
    "RobotStateClient",
    "Init",
    "InitChannel",
    "ChannelFactory",
    "SetTimeout",
    "ServiceList",
    "ServiceSwitch",
    "GetRobotState",
    "GetBattery",
    "Get",
)

CALL_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_:.\->]*\s*\(")


def should_print_key_line(line):
    return any(keyword in line for keyword in KEYWORDS)


def looks_like_call(line):
    stripped = line.strip()
    if not stripped or stripped.startswith("//"):
        return False
    if stripped.startswith("#"):
        return False
    return CALL_PATTERN.search(stripped) is not None


def print_section(title):
    print(f"[INSPECT] {title}")


def main():
    print("[INSPECT] RobotState C++ example inspector")
    print("[INSPECT] safe mode: reads cpp file only, does not execute SDK code")
    print(f"[INSPECT] cpp_path={CPP_PATH}")

    if not os.path.isfile(CPP_PATH):
        print(f"[INSPECT] missing file: {CPP_PATH}")
        return

    with open(CPP_PATH, "r", encoding="utf-8", errors="replace") as file_obj:
        lines = list(enumerate(file_obj, start=1))

    print_section("include lines")
    for line_number, line in lines:
        if "#include" in line:
            print(f"{line_number}: {line.rstrip()}")

    print_section("RobotStateClient / Init / state API related lines")
    for line_number, line in lines:
        if should_print_key_line(line):
            print(f"{line_number}: {line.rstrip()}")

    print_section("all function call looking lines")
    for line_number, line in lines:
        if looks_like_call(line):
            print(f"{line_number}: {line.rstrip()}")


if __name__ == "__main__":
    main()

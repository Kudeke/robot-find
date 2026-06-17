#!/usr/bin/env python3
import fnmatch
import os
import platform
import sys
import importlib


SEARCH_ROOTS = [
    "/usr/lib/python3.8",
    "/usr/local/lib/python3.8",
    "/home/unitree/.local/lib/python3.8/site-packages",
    "/home/unitree/repo/qre_go2-foxy-nvidia/src/third_party/unitree/20Jan2026_unitree_sdk2_python",
    "/home/unitree/quadruped_repo/unitree/20Jan2026_unitree_sdk2_python",
    "/home/unitree/unitree_sdk/src/04Aug2025_unitree_sdk2",
]

IMPORT_TARGETS = [
    "cyclonedds",
    "cyclonedds.domain",
    "cyclonedds.sub",
    "cyclonedds.pub",
]


def print_python_environment():
    print("[PROBE] CycloneDDS Python import probe")
    print("[PROBE] safe mode: import/search only, no DDS initialization")
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


def is_match(path):
    basename = os.path.basename(path)
    if basename == "cyclonedds" and os.path.isdir(path):
        return True
    if fnmatch.fnmatch(basename, "cyclonedds*.so"):
        return True
    if fnmatch.fnmatch(basename, "*_cyclonedds*.so"):
        return True
    return False


def search_cyclonedds_files():
    print("[PROBE] searching for cyclonedds Python package or shared libraries:")
    matches = []
    for root in SEARCH_ROOTS:
        print(f"[PROBE] search root: {root}")
        if not os.path.exists(root):
            print("  missing")
            continue

        for current_root, dirs, files in os.walk(root):
            for dirname in dirs:
                full_path = os.path.join(current_root, dirname)
                if is_match(full_path):
                    matches.append(full_path)
            for filename in files:
                full_path = os.path.join(current_root, filename)
                if is_match(full_path):
                    matches.append(full_path)

    if not matches:
        print("[PROBE] no cyclonedds package or .so matches found")
        return

    print("[PROBE] matches:")
    for path in sorted(set(matches)):
        print(f"  {path}")


def main():
    print_python_environment()
    try_import("cyclonedds")
    search_cyclonedds_files()

    print("[PROBE] module import checks:")
    for module_name in IMPORT_TARGETS:
        try_import(module_name)

    print("[PROBE] done")


if __name__ == "__main__":
    main()

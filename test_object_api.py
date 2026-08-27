import argparse
import json
import sys

import httpx


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    parser.add_argument("--base-url", default="http://127.0.0.1:8765")
    parser.add_argument("videos", nargs="+", help="one to four local MP4 paths")
    args = parser.parse_args()
    if not 1 <= len(args.videos) <= 4:
        parser.error("provide one to four videos")
    files = [("videos", (path.rsplit("/", 1)[-1], open(path, "rb"), "video/mp4")) for path in args.videos]
    try:
        response = httpx.post(
            args.base_url + "/api/v1/objects",
            data={"name": args.name}, files=files, timeout=900.0,
        )
    finally:
        for _, item in files:
            item[1].close()
    print("POST status:", response.status_code)
    response.raise_for_status()
    profile = response.json()
    print(json.dumps(profile, indent=2, ensure_ascii=False))
    required = {"object_id", "name", "category", "visual_description", "distinctive_features", "navigation_description", "created_at"}
    if set(profile) != required:
        raise SystemExit("unexpected ObjectProfile keys")
    get_response = httpx.get(args.base_url + "/api/v1/objects/" + profile["object_id"], timeout=30.0)
    print("GET status:", get_response.status_code)
    get_response.raise_for_status()
    if get_response.json() != profile:
        raise SystemExit("GET profile differs from POST profile")
    print("GET reload: PASS")


if __name__ == "__main__":
    main()

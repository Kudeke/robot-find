import argparse
import json

import httpx


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8765")
    parser.add_argument("--object-id", required=True)
    args = parser.parse_args()

    response = httpx.post(
        args.base_url + "/api/v1/missions",
        json={"object_id": args.object_id},
        timeout=30,
    )
    print("POST status:", response.status_code)
    response.raise_for_status()
    mission = response.json()
    print(json.dumps(mission, indent=2, ensure_ascii=False))
    required = {
        "mission_id", "object_id", "object_name", "state",
        "navigation_instruction", "created_at", "error",
    }
    if set(mission) != required or mission["state"] != "ready":
        raise SystemExit("invalid ready mission response")

    loaded = httpx.get(
        args.base_url + "/api/v1/missions/" + mission["mission_id"], timeout=30
    )
    print("GET status:", loaded.status_code)
    loaded.raise_for_status()
    if loaded.json() != mission:
        raise SystemExit("GET mission differs from POST mission")
    print("GET mission reload: PASS")


if __name__ == "__main__":
    main()

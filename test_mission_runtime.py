#!/usr/bin/env python3
"""Exercise Phase 3B-S mission runtime control without Ubuntu or robot services."""
import argparse
import json
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def request_json(base_url, method, path, body=None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    request = Request(base_url.rstrip("/") + path, data=data, headers={"Content-Type": "application/json"} if data else {}, method=method)
    try:
        with urlopen(request, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {path}: HTTP {exc.code}: {detail}") from exc
    except URLError as exc:
        raise RuntimeError(f"cannot reach {base_url}: {exc}") from exc


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8765")
    parser.add_argument("--mission-id", required=True)
    args = parser.parse_args()
    path = f"/api/v1/missions/{args.mission_id}"

    mission = request_json(args.base_url, "GET", path)
    if mission["state"] != "ready":
        raise RuntimeError(f"test requires ready mission, got {mission['state']}")
    instruction = mission["navigation_instruction"]

    started = request_json(args.base_url, "POST", path + "/start")
    assert started["state"] == "starting" and started["navigation_instruction"] == instruction
    active = request_json(args.base_url, "GET", "/api/v1/missions/active")
    assert active["mission_id"] == args.mission_id and active["state"] == "starting"
    running = request_json(args.base_url, "POST", path + "/runtime-started")
    assert running["state"] == "running"
    stopping = request_json(args.base_url, "POST", path + "/stop")
    assert stopping["state"] == "stopping"
    stopped = request_json(args.base_url, "POST", path + "/runtime-stopped")
    assert stopped["state"] == "stopped"
    final = request_json(args.base_url, "GET", path)
    assert final["state"] == "stopped" and final["navigation_instruction"] == instruction
    print(json.dumps(final, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

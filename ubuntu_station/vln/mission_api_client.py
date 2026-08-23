"""Small standard-library HTTP client for the RobotFind Mission API."""
from __future__ import annotations

import json
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


class MissionApiError(RuntimeError):
    pass


@dataclass(frozen=True)
class ActiveMission:
    mission_id: str
    object_id: str
    navigation_instruction: str
    state: str


class MissionApiClient:
    def __init__(self, base_url: str, timeout_sec: float = 5.0) -> None:
        self.base_url = base_url.strip().rstrip("/")
        self.timeout_sec = timeout_sec
        if not self.base_url:
            raise ValueError("mission API URL must not be empty")

    def get_active_mission(self) -> ActiveMission | None:
        return self._parse_active(self._request("GET", "/api/v1/missions/active"))

    def get_mission(self, mission_id: str) -> ActiveMission:
        mission = self._parse_mission(self._request("GET", f"/api/v1/missions/{mission_id}"))
        if mission is None:
            raise MissionApiError(f"mission {mission_id!r} was not returned")
        return mission

    def ack_runtime_started(self, mission_id: str) -> None:
        self._request("POST", f"/api/v1/missions/{mission_id}/runtime-started")

    def ack_runtime_stopped(self, mission_id: str) -> None:
        self._request("POST", f"/api/v1/missions/{mission_id}/runtime-stopped")

    def report_runtime_failed(self, mission_id: str, error: str) -> None:
        self._request("POST", f"/api/v1/missions/{mission_id}/runtime-failed", {"error": error[:500]})

    def _request(self, method: str, path: str, payload: dict | None = None) -> object:
        body = json.dumps(payload).encode() if payload is not None else None
        headers = {"Accept": "application/json"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        request = Request(f"{self.base_url}{path}", data=body, headers=headers, method=method)
        try:
            with urlopen(request, timeout=self.timeout_sec) as response:
                raw = response.read()
        except HTTPError as exc:
            if method == "GET" and path.endswith("/missions/active") and exc.code == 404:
                return None
            detail = exc.read().decode(errors="replace")[:300]
            raise MissionApiError(f"HTTP {exc.code} for {path}: {detail}") from exc
        except (URLError, OSError, TimeoutError) as exc:
            raise MissionApiError(f"Mission API unavailable for {path}: {exc}") from exc
        if not raw:
            return {}
        try:
            return json.loads(raw.decode())
        except json.JSONDecodeError as exc:
            raise MissionApiError(f"invalid JSON response from {path}") from exc

    def _parse_active(self, response: object) -> ActiveMission | None:
        if response is None:
            return None
        if not isinstance(response, dict):
            raise MissionApiError("active mission response must be a JSON object")
        response = response.get("active_mission", response.get("mission", response))
        if response in ({}, None):
            return None
        return self._parse_mission(response)

    def _parse_mission(self, response: object) -> ActiveMission | None:
        if not isinstance(response, dict):
            raise MissionApiError("mission response must be a JSON object")
        mission_id = str(response.get("mission_id") or response.get("id") or "").strip()
        if not mission_id:
            return None
        object_id = str(response.get("object_id") or "").strip()
        instruction = str(response.get("navigation_instruction") or response.get("instruction") or "").strip()
        state = str(response.get("state") or "").strip().lower()
        return ActiveMission(mission_id, object_id, instruction, state)

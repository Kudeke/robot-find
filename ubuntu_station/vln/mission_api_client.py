"""Small standard-library HTTP client for the RobotFind Mission API."""
from __future__ import annotations

import json
from dataclasses import dataclass
from uuid import uuid4
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


@dataclass(frozen=True)
class CandidateVerification:
    result: str
    confidence: float | None


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

    def ack_runtime_completed(self, mission_id: str) -> str | None:
        response = self._request("POST", f"/api/v1/missions/{mission_id}/runtime-completed")
        if not isinstance(response, dict):
            return None
        mission = response.get("mission")
        if isinstance(mission, dict):
            response = mission
        state = response.get("state")
        return str(state).strip().lower() if state is not None else None

    def verify_candidate(
        self,
        mission_id: str,
        evidence: dict[str, bytes],
    ) -> CandidateVerification:
        response = self._request_multipart(
            "POST", f"/api/v1/missions/{mission_id}/verify-candidate", evidence
        )
        if not isinstance(response, dict):
            raise MissionApiError("verify-candidate response must be a JSON object")
        nested = response.get("verification")
        if isinstance(nested, dict):
            response = nested
        result = str(response.get("result") or response.get("verification_result") or "").strip().lower()
        if result not in {"same_object", "different_object", "uncertain"}:
            raise MissionApiError(f"invalid verify-candidate result: {result!r}")
        confidence_value = response.get("confidence")
        try:
            confidence = float(confidence_value) if confidence_value is not None else None
        except (TypeError, ValueError):
            confidence = None
        return CandidateVerification(result, confidence)

    def ack_runtime_resumed(self, mission_id: str) -> None:
        self._request("POST", f"/api/v1/missions/{mission_id}/runtime-resumed")

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

    def _request_multipart(self, method: str, path: str, files: dict[str, bytes]) -> object:
        boundary = f"----RobotFind{uuid4().hex}"
        parts: list[bytes] = []
        for field_name, content in files.items():
            parts.extend(
                [
                    f"--{boundary}\r\n".encode(),
                    f'Content-Disposition: form-data; name="{field_name}"; filename="{field_name}.jpg"\r\n'.encode(),
                    b"Content-Type: image/jpeg\r\n\r\n",
                    bytes(content),
                    b"\r\n",
                ]
            )
        parts.append(f"--{boundary}--\r\n".encode())
        request = Request(
            f"{self.base_url}{path}",
            data=b"".join(parts),
            headers={
                "Accept": "application/json",
                "Content-Type": f"multipart/form-data; boundary={boundary}",
            },
            method=method,
        )
        try:
            with urlopen(request, timeout=self.timeout_sec) as response:
                raw = response.read()
        except HTTPError as exc:
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

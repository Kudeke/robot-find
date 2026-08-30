from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from .runtime_manager import RuntimeConflict, RuntimeInvalidTransition, RuntimeManager, RuntimeMissionNotFound
from .schemas import Mission

router = APIRouter()
manager = RuntimeManager()


class RuntimeFailedRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    error: str = Field(min_length=1, max_length=1000)


def _payload(mission: Mission):
    return mission.model_dump(mode="json")


def _run(operation, mission_id: str):
    try:
        return operation(mission_id)
    except RuntimeMissionNotFound:
        raise HTTPException(404, "mission not found")
    except RuntimeConflict as exc:
        raise HTTPException(409, str(exc))
    except RuntimeInvalidTransition as exc:
        raise HTTPException(409, str(exc))


@router.post("/api/v1/missions/{mission_id}/start")
def start_mission(mission_id: str):
    return _payload(_run(manager.start, mission_id))


@router.get("/api/v1/missions/active")
def get_active_mission():
    mission = manager.get_active()
    if mission is None:
        raise HTTPException(404, "no active mission")
    return _payload(mission)


@router.post("/api/v1/missions/{mission_id}/runtime-started")
def runtime_started(mission_id: str):
    return _payload(_run(manager.runtime_started, mission_id))


@router.post("/api/v1/missions/{mission_id}/runtime-completed")
def runtime_completed(mission_id: str):
    return _payload(_run(manager.runtime_completed, mission_id))


@router.post("/api/v1/missions/{mission_id}/stop")
def stop_mission(mission_id: str):
    return _payload(_run(manager.stop, mission_id))


@router.post("/api/v1/missions/{mission_id}/runtime-stopped")
def runtime_stopped(mission_id: str):
    return _payload(_run(manager.runtime_stopped, mission_id))


@router.post("/api/v1/missions/{mission_id}/runtime-failed")
def runtime_failed(mission_id: str, request: RuntimeFailedRequest):
    try:
        return _payload(manager.runtime_failed(mission_id, request.error))
    except RuntimeMissionNotFound:
        raise HTTPException(404, "mission not found")
    except RuntimeInvalidTransition as exc:
        raise HTTPException(409, str(exc))

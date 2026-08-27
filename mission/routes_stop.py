from fastapi import APIRouter, HTTPException

from .mission_manager_stop import InvalidObjectProfileError, MissionManager, ObjectNotFoundError
from .schemas import CreateMissionRequest

router = APIRouter()
manager = MissionManager()


@router.post("/api/v1/missions", status_code=201)
def create_mission(request: CreateMissionRequest):
    if not request.object_id.startswith("obj_"):
        raise HTTPException(404, "object not found")
    try:
        return manager.create_mission(request.object_id).model_dump(mode="json")
    except ObjectNotFoundError:
        raise HTTPException(404, "object not found")
    except InvalidObjectProfileError as exc:
        raise HTTPException(422, str(exc))


@router.get("/api/v1/missions/{mission_id}")
def get_mission(mission_id: str):
    mission = manager.get_mission(mission_id)
    if mission is None:
        raise HTTPException(404, "mission not found")
    return mission.model_dump(mode="json")

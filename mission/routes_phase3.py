import logging

from fastapi import APIRouter, HTTPException

from .mission_manager import InvalidObjectProfileError, MissionManager, ObjectNotFoundError
from .schemas import CreateMissionRequest

router = APIRouter()
manager = MissionManager()
logger = logging.getLogger("mission")


@router.post("/api/v1/missions", status_code=201)
def create_mission(request: CreateMissionRequest):
    # Any unknown/malformed object identifier is a missing object from the API's perspective.
    if not request.object_id.startswith("obj_"):
        raise HTTPException(404, "object not found")
    try:
        mission = manager.create_mission(request.object_id)
    except ObjectNotFoundError:
        raise HTTPException(404, "object not found")
    except InvalidObjectProfileError as exc:
        raise HTTPException(422, str(exc))
    except Exception as exc:
        logger.exception("[MissionAPI] mission creation failed object_id=%s", request.object_id)
        raise HTTPException(500, "mission creation failed") from exc
    return mission.model_dump(mode="json")


@router.get("/api/v1/missions/{mission_id}")
def get_mission(mission_id: str):
    mission = manager.get_mission(mission_id)
    if mission is None:
        raise HTTPException(404, "mission not found")
    return mission.model_dump(mode="json")

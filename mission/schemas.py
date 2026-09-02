from datetime import datetime, timezone
from enum import Enum

from pydantic import BaseModel, ConfigDict, Field


class MissionState(str, Enum):
    CREATED = "created"
    READY = "ready"
    STARTING = "starting"
    RUNNING = "running"
    VERIFYING = "verifying"
    RESUMING = "resuming"
    STOPPING = "stopping"
    STOPPED = "stopped"
    TARGET_FOUND = "target_found"
    FAILED = "failed"


class CreateMissionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    object_id: str = Field(min_length=1)


class Mission(BaseModel):
    model_config = ConfigDict(extra="forbid")
    mission_id: str
    object_id: str
    object_name: str
    state: MissionState
    navigation_instruction: str
    created_at: str
    error: str | None = None

    @classmethod
    def ready(cls, mission_id: str, object_id: str, object_name: str, instruction: str):
        return cls(
            mission_id=mission_id,
            object_id=object_id,
            object_name=object_name,
            state=MissionState.READY,
            navigation_instruction=instruction,
            created_at=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            error=None,
        )

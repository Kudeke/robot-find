import logging

from object_store import load_profile
from schemas import ObjectProfile

from .instruction_builder_stop import build_navigation_instruction
from .mission_store import load_mission, new_mission_id, save_mission
from .schemas import Mission

logger = logging.getLogger("mission")


class ObjectNotFoundError(Exception):
    pass


class InvalidObjectProfileError(Exception):
    pass


class MissionManager:
    def create_mission(self, object_id: str) -> Mission:
        try:
            raw_profile = load_profile(object_id)
        except ValueError as exc:
            raise ObjectNotFoundError(object_id) from exc
        except (OSError, TypeError) as exc:
            raise InvalidObjectProfileError("stored ObjectProfile is invalid") from exc
        if raw_profile is None:
            raise ObjectNotFoundError(object_id)
        try:
            profile = ObjectProfile.model_validate(raw_profile)
            instruction = build_navigation_instruction(profile)
        except Exception as exc:
            raise InvalidObjectProfileError("stored ObjectProfile is incomplete or invalid") from exc
        mission = Mission.ready(new_mission_id(), profile.object_id, profile.name, instruction)
        save_mission(mission)
        logger.info("[MissionAPI] ready mission_id=%s", mission.mission_id)
        return mission

    def get_mission(self, mission_id: str) -> Mission | None:
        try:
            return load_mission(mission_id)
        except (ValueError, OSError, TypeError):
            return None

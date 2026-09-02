import logging
from threading import RLock

from .mission_store import list_mission_ids, load_mission, save_mission
from .schemas import Mission, MissionState

logger = logging.getLogger("mission.runtime")
ACTIVE_STATES = frozenset({
    MissionState.STARTING,
    MissionState.RUNNING,
    MissionState.VERIFYING,
    MissionState.RESUMING,
    MissionState.STOPPING,
})


class RuntimeErrorBase(Exception):
    """Base class for expected runtime-control errors."""


class RuntimeMissionNotFound(RuntimeErrorBase):
    pass


class RuntimeConflict(RuntimeErrorBase):
    pass


class RuntimeInvalidTransition(RuntimeErrorBase):
    pass


class RuntimeManager:
    def __init__(self):
        self._lock = RLock()
        self.recover_incomplete_missions()

    def _load(self, mission_id: str) -> Mission:
        try:
            mission = load_mission(mission_id)
        except (ValueError, OSError, TypeError) as exc:
            raise RuntimeMissionNotFound(mission_id) from exc
        if mission is None:
            raise RuntimeMissionNotFound(mission_id)
        return mission

    def _active_locked(self, exclude_id: str | None = None) -> Mission | None:
        for mission_id in list_mission_ids():
            if exclude_id and mission_id == exclude_id:
                continue
            try:
                mission = load_mission(mission_id)
            except (ValueError, OSError, TypeError) as exc:
                logger.warning("[RuntimeManager] ignoring invalid mission %s: %s", mission_id, exc)
                continue
            if mission is not None and mission.state in ACTIVE_STATES:
                return mission
        return None

    def recover_incomplete_missions(self) -> None:
        with self._lock:
            for mission_id in list_mission_ids():
                try:
                    mission = load_mission(mission_id)
                except (ValueError, OSError, TypeError) as exc:
                    logger.warning("[RuntimeManager] cannot inspect mission %s: %s", mission_id, exc)
                    continue
                if mission is None or mission.state not in ACTIVE_STATES:
                    continue
                mission.state = MissionState.FAILED
                mission.error = "recovered after Mission API restart; runtime acknowledgement is required"
                save_mission(mission)
                logger.warning("[RuntimeManager] recovered mission_id=%s to failed", mission_id)

    def get_mission(self, mission_id: str) -> Mission | None:
        try:
            return load_mission(mission_id)
        except (ValueError, OSError, TypeError):
            return None

    def get_active(self) -> Mission | None:
        with self._lock:
            return self._active_locked()

    def start(self, mission_id: str) -> Mission:
        with self._lock:
            mission = self._load(mission_id)
            if not mission.navigation_instruction.strip():
                raise RuntimeInvalidTransition("mission has no valid navigation_instruction")
            if mission.state != MissionState.READY:
                raise RuntimeInvalidTransition(f"mission cannot start from state {mission.state.value}")
            active = self._active_locked(exclude_id=mission_id)
            if active is not None:
                raise RuntimeConflict(f"mission {active.mission_id} is already active")
            mission.state = MissionState.STARTING
            mission.error = None
            save_mission(mission)
            logger.info("[RuntimeManager] mission_id=%s ready -> starting", mission_id)
            return mission

    def runtime_started(self, mission_id: str) -> Mission:
        with self._lock:
            mission = self._load(mission_id)
            if mission.state != MissionState.STARTING:
                raise RuntimeInvalidTransition(f"runtime-started requires state starting, got {mission.state.value}")
            mission.state = MissionState.RUNNING
            mission.error = None
            save_mission(mission)
            logger.info("[RuntimeManager] mission_id=%s starting -> running", mission_id)
            return mission

    def begin_verification(self, mission_id: str) -> Mission:
        with self._lock:
            mission = self._load(mission_id)
            if mission.state != MissionState.RUNNING:
                raise RuntimeInvalidTransition(
                    f"candidate verification requires state running, got {mission.state.value}"
                )
            mission.state = MissionState.VERIFYING
            mission.error = None
            save_mission(mission)
            logger.info("[RuntimeManager] mission_id=%s running -> verifying", mission_id)
            return mission

    def apply_verification(self, mission_id: str, result: str) -> Mission:
        with self._lock:
            mission = self._load(mission_id)
            if mission.state != MissionState.VERIFYING:
                raise RuntimeInvalidTransition(
                    f"verification result requires state verifying, got {mission.state.value}"
                )
            if result == "same_object":
                next_state = MissionState.VERIFYING
            elif result in {"different_object", "uncertain"}:
                next_state = MissionState.RESUMING
            else:
                raise RuntimeInvalidTransition(f"unsupported verification result {result}")
            mission.state = next_state
            mission.error = None
            save_mission(mission)
            logger.info("[RuntimeManager] mission_id=%s verification=%s -> %s", mission_id, result, next_state.value)
            return mission

    def fail_verification(self, mission_id: str, error: str) -> Mission:
        with self._lock:
            mission = self._load(mission_id)
            if mission.state != MissionState.VERIFYING:
                raise RuntimeInvalidTransition(
                    f"verification failure requires state verifying, got {mission.state.value}"
                )
            mission.state = MissionState.FAILED
            mission.error = (error.strip() or "target verification failed")[:1000]
            save_mission(mission)
            logger.warning("[RuntimeManager] mission_id=%s -> failed", mission_id)
            return mission

    def runtime_resumed(self, mission_id: str) -> Mission:
        with self._lock:
            mission = self._load(mission_id)
            if mission.state != MissionState.RESUMING:
                raise RuntimeInvalidTransition(
                    f"runtime-resumed requires state resuming, got {mission.state.value}"
                )
            mission.state = MissionState.RUNNING
            mission.error = None
            save_mission(mission)
            logger.info("[RuntimeManager] mission_id=%s resuming -> running", mission_id)
            return mission

    def runtime_completed(self, mission_id: str) -> Mission:
        with self._lock:
            mission = self._load(mission_id)
            if mission.state not in {MissionState.RUNNING, MissionState.VERIFYING}:
                raise RuntimeInvalidTransition(
                    f"runtime-completed requires state running or verifying, got {mission.state.value}"
                )
            mission.state = MissionState.TARGET_FOUND
            mission.error = None
            save_mission(mission)
            logger.info("[RuntimeManager] mission_id=%s -> target_found", mission_id)
            return mission

    def stop(self, mission_id: str) -> Mission:
        with self._lock:
            mission = self._load(mission_id)
            if mission.state not in {
                MissionState.STARTING,
                MissionState.RUNNING,
                MissionState.VERIFYING,
                MissionState.RESUMING,
            }:
                raise RuntimeInvalidTransition(f"mission cannot stop from state {mission.state.value}")
            mission.state = MissionState.STOPPING
            mission.error = None
            save_mission(mission)
            logger.info("[RuntimeManager] mission_id=%s -> stopping", mission_id)
            return mission

    def runtime_stopped(self, mission_id: str) -> Mission:
        with self._lock:
            mission = self._load(mission_id)
            if mission.state not in {MissionState.STOPPING, MissionState.RUNNING}:
                raise RuntimeInvalidTransition(f"runtime-stopped requires stopping/running, got {mission.state.value}")
            mission.state = MissionState.STOPPED
            mission.error = None
            save_mission(mission)
            logger.info("[RuntimeManager] mission_id=%s -> stopped", mission_id)
            return mission

    def runtime_failed(self, mission_id: str, error: str) -> Mission:
        with self._lock:
            mission = self._load(mission_id)
            if mission.state not in ACTIVE_STATES:
                raise RuntimeInvalidTransition(f"runtime-failed requires active state, got {mission.state.value}")
            message = error.strip()
            if not message:
                raise RuntimeInvalidTransition("error must be non-empty")
            mission.state = MissionState.FAILED
            mission.error = message[:1000]
            save_mission(mission)
            logger.warning("[RuntimeManager] mission_id=%s -> failed: %s", mission_id, mission.error)
            return mission

import io
import logging
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, ConfigDict, Field
from PIL import Image

from object_store import object_dir
from .runtime_manager import (
    RuntimeConflict,
    RuntimeInvalidTransition,
    RuntimeManager,
    RuntimeMissionNotFound,
)
from .schemas import Mission
from .verification_manager import VerificationJobManager
from .verification_store import (
    CANDIDATE_FILES,
    VerificationStatus,
    candidate_path_map,
    create_candidate_files,
    create_verification,
    load_verification,
    update_failed,
)

router = APIRouter()
manager = RuntimeManager()
verification_jobs = VerificationJobManager(manager)
logger = logging.getLogger("mission.runtime.api")
MAX_CANDIDATE_BYTES = 12 * 1024 * 1024


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


def _record_payload(record):
    return record.model_dump(mode="json")


def _record_response(record):
    from fastapi.responses import JSONResponse
    status_code = 202 if record.status == VerificationStatus.PROCESSING else 200
    return JSONResponse(status_code=status_code, content=_record_payload(record))


def _read_candidate(upload: UploadFile) -> bytes:
    label = upload.filename or "candidate"
    if upload.content_type != "image/jpeg":
        raise HTTPException(400, f"{label} must have content type image/jpeg")
    data = upload.file.read(MAX_CANDIDATE_BYTES + 1)
    if not data:
        raise HTTPException(400, f"{label} is empty")
    if len(data) > MAX_CANDIDATE_BYTES:
        raise HTTPException(413, "candidate image exceeds size limit")
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.format != "JPEG":
                raise ValueError("not JPEG")
            image.verify()
    except Exception as exc:
        raise HTTPException(400, f"{label} is not a valid JPEG") from exc
    return data


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


@router.post("/api/v1/missions/{mission_id}/runtime-resumed")
def runtime_resumed(mission_id: str):
    return _payload(_run(manager.runtime_resumed, mission_id))


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


@router.post("/api/v1/missions/{mission_id}/verify-candidate")
def verify_mission_candidate(
    mission_id: str,
    candidate_id: str = Form(...),
    last_non_stop_1: UploadFile = File(...),
    last_non_stop_2: UploadFile = File(...),
    last_non_stop_3: UploadFile = File(...),
    first_stop: UploadFile = File(...),
):
    try:
        with verification_jobs.lock:
            try:
                existing = load_verification(mission_id, candidate_id)
            except ValueError as exc:
                raise HTTPException(400, "invalid candidate_id") from exc
            if existing is not None:
                return _record_response(existing)

            mission = manager.get_mission(mission_id)
            if mission is None:
                raise HTTPException(404, "mission not found")
            if mission.state.value != "running":
                raise HTTPException(
                    409,
                    f"candidate verification requires state running, got {mission.state.value}",
                )

            try:
                directory = object_dir(mission.object_id)
            except (ValueError, OSError, TypeError) as exc:
                raise HTTPException(422, "stored object directory is unavailable") from exc
            if not directory.is_dir():
                raise HTTPException(422, "stored object directory is unavailable")
            reference_paths = sorted(directory.glob("clip_*.mp4"))
            if not reference_paths:
                raise HTTPException(422, "no teaching reference videos found")
            if any(not path.is_file() or path.stat().st_size == 0 for path in reference_paths):
                raise HTTPException(422, "teaching reference videos are incomplete")

            uploads = {
                "last_non_stop_1": last_non_stop_1,
                "last_non_stop_2": last_non_stop_2,
                "last_non_stop_3": last_non_stop_3,
                "first_stop": first_stop,
            }
            images = {name: _read_candidate(upload) for name, upload in uploads.items()}
            try:
                create_candidate_files(mission_id, candidate_id, images)
                record = create_verification(mission_id, candidate_id, mission.object_id)
            except FileExistsError:
                existing = load_verification(mission_id, candidate_id)
                if existing is not None:
                    return _record_response(existing)
                raise HTTPException(409, "candidate already exists")
            except HTTPException:
                raise
            except Exception as exc:
                logger.exception("[TargetVerifier] candidate persistence failed candidate_id=%s", candidate_id)
                raise HTTPException(500, "candidate persistence failed") from exc

            try:
                manager.begin_verification(mission_id)
            except RuntimeInvalidTransition as exc:
                update_failed(record, "mission state changed before verification started")
                raise HTTPException(409, "mission state changed before verification started") from exc

            try:
                verification_jobs.submit(record, reference_paths)
            except Exception as exc:
                logger.exception("[TargetVerifier] could not schedule candidate_id=%s", candidate_id)
                update_failed(record, "target verification could not be scheduled")
                try:
                    manager.fail_verification(mission_id, "target verification could not be scheduled")
                except RuntimeInvalidTransition:
                    pass
                raise HTTPException(500, "candidate verification could not be scheduled") from exc
            logger.info(
                "[TargetVerifier] accepted candidate_id=%s mission_id=%s status=processing",
                candidate_id, mission_id,
            )
            return _record_response(record)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("[MissionRuntimeAPI] candidate request failed mission_id=%s", mission_id)
        raise HTTPException(500, "candidate verification request failed") from exc


@router.get("/api/v1/missions/{mission_id}/verifications/{candidate_id}")
def get_verification(mission_id: str, candidate_id: str):
    try:
        record = load_verification(mission_id, candidate_id)
    except ValueError as exc:
        raise HTTPException(400, "invalid candidate_id") from exc
    if record is None:
        raise HTTPException(404, "verification candidate not found")
    return _record_payload(record)

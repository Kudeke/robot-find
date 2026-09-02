import json
import os
import re
import tempfile
import uuid
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field


CANDIDATE_FILES = (
    "last_non_stop_1",
    "last_non_stop_2",
    "last_non_stop_3",
    "first_stop",
)


class VerificationStatus(str, Enum):
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


class VerificationRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")
    candidate_id: str
    mission_id: str
    object_id: str
    status: VerificationStatus
    stage: str | None = None
    updated_at: str | None = None
    progress_detail: str | None = None
    result: str | None = None
    confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    evidence: list[str] = Field(default_factory=list)
    reason: str | None = None
    error: str | None = None
    created_at: str
    completed_at: str | None = None
    candidate_files: dict[str, str] = Field(default_factory=dict)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _root() -> Path:
    data_root = Path(os.environ.get(
        "FINDMYTHINGS_DATA_DIR",
        "/cvhci/temp/squan/qwen_object_service/data",
    )).resolve()
    return data_root / "missions"


def _validate_id(value: str, prefix: str) -> None:
    if not re.fullmatch(prefix + r"[A-Za-z0-9_-]+", value):
        raise ValueError("invalid identifier")


def candidate_dir(mission_id: str, candidate_id: str) -> Path:
    _validate_id(mission_id, r"mission_")
    _validate_id(candidate_id, r"cand_")
    return _root() / mission_id / "verifications" / candidate_id


def candidate_path_map(mission_id: str, candidate_id: str) -> dict[str, Path]:
    directory = candidate_dir(mission_id, candidate_id)
    return {name: directory / (name + ".jpg") for name in CANDIDATE_FILES}


def create_candidate_files(mission_id: str, candidate_id: str, images: dict[str, bytes]) -> Path:
    paths = candidate_path_map(mission_id, candidate_id)
    if set(images) != set(CANDIDATE_FILES):
        raise ValueError("candidate image fields are incomplete")
    root = paths[CANDIDATE_FILES[0]].parent.parent
    root.mkdir(parents=True, exist_ok=True)
    target = paths[CANDIDATE_FILES[0]].parent
    if target.exists():
        raise FileExistsError(candidate_id)
    temporary = Path(tempfile.mkdtemp(prefix="." + candidate_id + ".", dir=root))
    try:
        for name in CANDIDATE_FILES:
            (temporary / (name + ".jpg")).write_bytes(images[name])
        temporary.rename(target)
    except Exception:
        import shutil
        shutil.rmtree(temporary, ignore_errors=True)
        raise
    return target


def _atomic_write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(text)
        temporary = Path(handle.name)
    temporary.replace(path)


def create_verification(mission_id: str, candidate_id: str, object_id: str) -> VerificationRecord:
    now = now_iso()
    record = VerificationRecord(
        candidate_id=candidate_id,
        mission_id=mission_id,
        object_id=object_id,
        status=VerificationStatus.PROCESSING,
        stage="queued",
        updated_at=now,
        progress_detail="candidate accepted; waiting for verification worker",
        created_at=now,
        candidate_files={name: name + ".jpg" for name in CANDIDATE_FILES},
    )
    _atomic_write(candidate_dir(mission_id, candidate_id) / "verification.json", record.model_dump(mode="json"))
    return record


def load_verification(mission_id: str, candidate_id: str) -> VerificationRecord | None:
    path = candidate_dir(mission_id, candidate_id) / "verification.json"
    if not path.is_file():
        return None
    return VerificationRecord.model_validate_json(path.read_text(encoding="utf-8"))


def save_verification_record(record: VerificationRecord) -> Path:
    path = candidate_dir(record.mission_id, record.candidate_id) / "verification.json"
    _atomic_write(path, record.model_dump(mode="json"))
    return path


def update_progress(record: VerificationRecord, stage: str, detail: str | None = None) -> VerificationRecord:
    record.stage = stage
    record.updated_at = now_iso()
    record.progress_detail = detail
    save_verification_record(record)
    return record


def update_completed(record: VerificationRecord, result, completed_at: str | None = None) -> VerificationRecord:
    record.status = VerificationStatus.COMPLETED
    record.stage = "completed"
    record.updated_at = now_iso()
    record.progress_detail = "verification completed"
    record.result = result.result.value
    record.confidence = result.confidence
    record.evidence = list(result.evidence)
    record.reason = result.reason
    record.error = None
    record.completed_at = completed_at or record.updated_at
    save_verification_record(record)
    return record


def update_failed(record: VerificationRecord, error: str) -> VerificationRecord:
    record.status = VerificationStatus.FAILED
    record.stage = "failed"
    record.updated_at = now_iso()
    record.progress_detail = "verification failed"
    record.result = None
    record.confidence = None
    record.evidence = []
    record.reason = None
    record.error = (error.strip() or "target verification failed")[:1000]
    record.completed_at = record.updated_at
    save_verification_record(record)
    return record


def list_processing_records() -> list[VerificationRecord]:
    records = []
    for path in _root().glob("mission_*/verifications/cand_*/verification.json"):
        try:
            record = VerificationRecord.model_validate_json(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if record.status == VerificationStatus.PROCESSING:
            records.append(record)
    return records

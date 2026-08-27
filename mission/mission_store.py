import json
import os
import tempfile
import uuid
from pathlib import Path

from .schemas import Mission


def missions_root() -> Path:
    data_root = Path(os.environ.get(
        "FINDMYTHINGS_DATA_DIR",
        "/cvhci/temp/squan/qwen_object_service/data",
    )).resolve()
    return data_root / "missions"


def new_mission_id() -> str:
    return "mission_" + uuid.uuid4().hex


def _mission_path(mission_id: str) -> Path:
    if not mission_id.startswith("mission_") or "/" in mission_id or "\\" in mission_id or ".." in mission_id:
        raise ValueError("invalid mission id")
    return missions_root() / f"{mission_id}.json"


def save_mission(mission: Mission) -> Path:
    root = missions_root()
    root.mkdir(parents=True, exist_ok=True)
    target = _mission_path(mission.mission_id)
    payload = json.dumps(mission.model_dump(mode="json"), indent=2, ensure_ascii=False) + "\n"
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=root, delete=False) as handle:
        handle.write(payload)
        temporary = Path(handle.name)
    temporary.replace(target)
    return target


def load_mission(mission_id: str) -> Mission | None:
    path = _mission_path(mission_id)
    if not path.is_file():
        return None
    return Mission.model_validate_json(path.read_text(encoding="utf-8"))


def list_mission_ids() -> list[str]:
    root = missions_root()
    if not root.is_dir():
        return []
    return sorted(path.stem for path in root.glob("mission_*.json") if path.is_file())

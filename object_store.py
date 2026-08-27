import json
import os
import shutil
import uuid
from pathlib import Path


DATA_ROOT = Path(os.environ.get(
    "FINDMYTHINGS_DATA_DIR",
    "/cvhci/temp/squan/qwen_object_service/data",
)).resolve()
OBJECTS_ROOT = DATA_ROOT / "objects"


def new_object_id():
    return "obj_" + uuid.uuid4().hex


def object_dir(object_id):
    if not object_id.startswith("obj_") or "/" in object_id or "\\" in object_id or ".." in object_id:
        raise ValueError("invalid object id")
    return OBJECTS_ROOT / object_id


def save_object(object_id, profile, uploads):
    target = object_dir(object_id)
    if target.exists():
        raise FileExistsError(object_id)
    temp = OBJECTS_ROOT / ("." + object_id + ".partial")
    temp.mkdir(parents=True, exist_ok=False)
    try:
        for index, source in enumerate(uploads, 1):
            destination = temp / f"clip_{index:02d}.mp4"
            with destination.open("wb") as out:
                shutil.copyfileobj(source, out)
        (temp / "profile.json").write_text(
            json.dumps(profile, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        temp.rename(target)
    except Exception:
        shutil.rmtree(temp, ignore_errors=True)
        raise
    return target


def load_profile(object_id):
    path = object_dir(object_id) / "profile.json"
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))

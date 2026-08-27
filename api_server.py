import os
from pathlib import Path
from threading import Lock

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse

from object_store import load_profile, new_object_id, save_object
from qwen_object_service import MODEL_PATH, generate_profile, load_model
from schemas import ObjectProfile

app = FastAPI(title="FindMyThings Object Service")
inference_lock = Lock()
MAX_VIDEOS = 4
MAX_FILE_BYTES = 512 * 1024 * 1024


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model_available": Path(MODEL_PATH).is_dir(),
        "model": "Qwen/Qwen3-VL-8B-Instruct",
    }


@app.post("/api/v1/objects", status_code=201)
def create_object(name: str = Form(...), videos: list[UploadFile] = File(...)):
    name = name.strip()
    if not name:
        raise HTTPException(400, "name must be non-empty")
    if not 1 <= len(videos) <= MAX_VIDEOS:
        raise HTTPException(400, "videos must contain between 1 and 4 files")
    for upload in videos:
        filename = (upload.filename or "").lower()
        if not filename.endswith(".mp4"):
            raise HTTPException(400, "only .mp4 videos are accepted")

    object_id = new_object_id()
    staging = []
    try:
        # Read uploads into an isolated staging directory so Qwen sees server paths.
        from tempfile import TemporaryDirectory
        with TemporaryDirectory(dir="/cvhci/temp/squan/qwen_object_service") as temp_dir:
            for index, upload in enumerate(videos, 1):
                path = Path(temp_dir) / f"clip_{index:02d}.mp4"
                total = 0
                with path.open("wb") as out:
                    while chunk := upload.file.read(1024 * 1024):
                        total += len(chunk)
                        if total > MAX_FILE_BYTES:
                            raise HTTPException(413, "video exceeds per-file size limit")
                        out.write(chunk)
                if total == 0:
                    raise HTTPException(400, "zero-byte video upload")
                staging.append(path)
            with inference_lock:
                generated, _raw = generate_profile(staging)
            profile = ObjectProfile.new(object_id, name, generated).model_dump()
            save_object(object_id, profile, [path.open("rb") for path in staging])
            return JSONResponse(status_code=201, content=profile)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, f"object inference failed: {exc}") from exc


@app.get("/api/v1/objects/{object_id}")
def get_object(object_id: str):
    try:
        profile = load_profile(object_id)
    except ValueError:
        profile = None
    if profile is None:
        raise HTTPException(404, "object not found")
    return profile


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host=os.environ.get("FINDMYTHINGS_OBJECT_HOST", "127.0.0.1"),
        port=int(os.environ.get("FINDMYTHINGS_OBJECT_PORT", "8765")),
    )

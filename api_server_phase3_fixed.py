"""Phase 3A/3B-S entry point with mission runtime control."""
import os

import api_server
from api_server import app
from mission.routes_phase3 import router as mission_router
from mission.runtime_routes import router as runtime_router
from qwen_object_service import load_model
from qwen_object_service_sequential import generate_profile as _generate_profile


def generate_profile(video_paths):
    generated, raw, _clip_descriptions = _generate_profile(video_paths)
    return generated, raw


api_server.generate_profile = generate_profile
app.include_router(runtime_router)
app.include_router(mission_router)


if __name__ == "__main__":
    print("[Startup] Loading Qwen3-VL model before starting API...", flush=True)
    load_model()
    print("[Startup] Qwen3-VL model loaded; starting API.", flush=True)
    import uvicorn
    uvicorn.run(app, host=os.environ.get("FINDMYTHINGS_OBJECT_HOST", "127.0.0.1"), port=int(os.environ.get("FINDMYTHINGS_OBJECT_PORT", "8765")))

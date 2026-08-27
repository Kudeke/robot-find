"""Phase 3A entry point: existing object API plus local mission routes."""
import os

import api_server
from api_server import app
from mission.routes import router as mission_router
from qwen_object_service_sequential import generate_profile as _generate_profile


def generate_profile(video_paths):
    generated, raw, _clip_descriptions = _generate_profile(video_paths)
    return generated, raw


# Keep the existing object API behavior while using its memory-bounded profile path.
api_server.generate_profile = generate_profile
app.include_router(mission_router)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host=os.environ.get("FINDMYTHINGS_OBJECT_HOST", "127.0.0.1"),
        port=int(os.environ.get("FINDMYTHINGS_OBJECT_PORT", "8765")),
    )

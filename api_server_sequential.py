"""API entry point using the memory-bounded sequential multi-video inference."""
from api_server import app
import api_server
from qwen_object_service import MODEL_PATH
from qwen_object_service_sequential import generate_profile

api_server.generate_profile = generate_profile

if __name__ == "__main__":
    import os
    import uvicorn
    uvicorn.run(
        app,
        host=os.environ.get("FINDMYTHINGS_OBJECT_HOST", "127.0.0.1"),
        port=int(os.environ.get("FINDMYTHINGS_OBJECT_PORT", "8765")),
    )

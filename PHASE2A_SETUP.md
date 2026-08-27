# Phase 2A runtime and API validation

- PyTorch: `2.11.0+cu128`; Torch CUDA: `12.8`; Transformers: `5.15.1`; qwen-vl-utils: `0.0.14`.
- Video backend: `decord 0.6.0` (Python-only).
- Selected physical GPU: `0` (Quadro RTX 6000, 24576 MiB); approximate peak VRAM: `17.27 GiB`.
- Local video inference: PASS. Four clips were processed sequentially in one process and their real Qwen descriptions were summarized by the same model. A simultaneous four-video request exceeded 24 GiB VRAM.
- API dependencies: `fastapi 0.141.1`, `uvicorn 0.52.4`, `python-multipart 0.0.32`, `pydantic 2.13.4`, `httpx 0.28.1`.
- Endpoints: `GET /health`, `POST /api/v1/objects`, `GET /api/v1/objects/{object_id}`.
- Storage: `/cvhci/temp/squan/qwen_object_service/data/objects/obj_<uuid>/{profile.json,clip_01.mp4,...}`.
- Startup: `CUDA_VISIBLE_DEVICES=0 FORCE_QWENVL_VIDEO_READER=decord ./run_object_service.sh` (foreground, localhost only).
- API validation: health, four-file multipart POST, and GET reload passed.
- Example: `obj_a7f2d7cf57fd443996fffae3cff1a31e`; category `computer mouse`; navigation description `white ergonomic mouse with 'inphic' branding and ribbed underside`.

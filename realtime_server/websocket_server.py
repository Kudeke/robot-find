# coding: utf-8
import argparse
import asyncio
import base64
import json
import time
from typing import Any

import cv2
import numpy as np
import websockets

from realtime_server.uninavid_engine import DEFAULT_MODEL_PATH, UniNaVidEngine


def error_response(message: str) -> dict:
    return {"type": "error", "error": message, "actions": ["stop"]}


def require_nonempty_str(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{key} must not be empty")
    return value


def decode_jpeg_base64(jpeg_base64: Any) -> np.ndarray:
    if not isinstance(jpeg_base64, str) or not jpeg_base64:
        raise ValueError("jpeg_base64 must not be empty")
    try:
        jpeg_bytes = base64.b64decode(jpeg_base64, validate=True)
    except Exception as exc:  # noqa: BLE001
        raise ValueError(f"invalid base64 JPEG: {exc}") from exc

    arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    image_bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if image_bgr is None:
        raise ValueError("JPEG decode failed")
    return image_bgr


async def handle_message(engine: UniNaVidEngine, payload: dict[str, Any]) -> dict:
    message_type = payload.get("type")

    if message_type == "ping":
        return {"type": "pong", "server_time_ns": time.time_ns()}

    if message_type == "reset":
        session_id = require_nonempty_str(payload, "session_id")
        instruction = require_nonempty_str(payload, "instruction")
        engine.reset_session(session_id, instruction)
        print(f"[SERVER] reset session_id={session_id}", flush=True)
        return {"type": "reset_ack", "session_id": session_id}

    if message_type == "infer":
        session_id = require_nonempty_str(payload, "session_id")
        frame_seq = payload.get("frame_seq")
        source_timestamp_ns = payload.get("timestamp_ns")
        instruction = payload.get("instruction")
        if instruction is not None and not isinstance(instruction, str):
            raise ValueError("instruction must be a string")

        image_bgr = decode_jpeg_base64(payload.get("jpeg_base64"))
        result = engine.predict(session_id, image_bgr, instruction=instruction)
        response = {
            "type": "inference_result",
            "session_id": session_id,
            "frame_seq": frame_seq,
            "source_timestamp_ns": source_timestamp_ns,
            "server_timestamp_ns": time.time_ns(),
            "actions": result.get("actions", ["stop"]),
            "raw_output": result.get("raw_output", ""),
            "path": result.get("path", []),
            "step": result.get("step", 0),
            "inference_ms": result.get("inference_ms", 0.0),
        }
        if "error" in result:
            response["error"] = result["error"]
            print(f"[SERVER][ERROR] inference error: {result['error']}", flush=True)
        print(
            "[SERVER] inference "
            f"frame_seq={frame_seq} actions={response['actions']} "
            f"inference_ms={response['inference_ms']:.1f}",
            flush=True,
        )
        return response

    if message_type == "shutdown_session":
        session_id = require_nonempty_str(payload, "session_id")
        engine.close_session(session_id)
        return {"type": "shutdown_session_ack", "session_id": session_id}

    raise ValueError(f"unsupported message type: {message_type!r}")


async def client_handler(websocket, engine: UniNaVidEngine) -> None:
    remote = getattr(websocket, "remote_address", None)
    print(f"[SERVER] client connected remote={remote}", flush=True)
    try:
        async for message in websocket:
            try:
                payload = json.loads(message)
                if not isinstance(payload, dict):
                    raise ValueError("message must be a JSON object")
                response = await handle_message(engine, payload)
            except Exception as exc:  # noqa: BLE001 - protocol errors must not kill server
                print(f"[SERVER][ERROR] {exc}", flush=True)
                response = error_response(str(exc))
            await websocket.send(json.dumps(response, ensure_ascii=False))
    finally:
        print(f"[SERVER] client disconnected remote={remote}", flush=True)


async def run_server(host: str, port: int, model_path: str) -> None:
    print("[SERVER] loading Uni-NaVid", flush=True)
    engine = UniNaVidEngine(model_path=model_path)
    print("[SERVER] model loaded", flush=True)

    async with websockets.serve(
        lambda websocket: client_handler(websocket, engine),
        host,
        port,
        ping_interval=None,
        ping_timeout=None,
        max_size=10 * 1024 * 1024,
    ):
        print(f"[SERVER] listening on ws://{host}:{port}", flush=True)
        await asyncio.Future()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=9000)
    parser.add_argument("--model-path", default=DEFAULT_MODEL_PATH)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    asyncio.run(run_server(args.host, args.port, args.model_path))


if __name__ == "__main__":
    main()

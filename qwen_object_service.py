"""Local Qwen3-VL inference for one to four teaching videos."""

import json
import os
import re
from pathlib import Path
from threading import Lock

import torch
from qwen_vl_utils import process_vision_info
from transformers import AutoProcessor, Qwen3VLForConditionalGeneration

MODEL_PATH = os.environ.get(
    "QWEN3_VL_MODEL", "/cvhci/temp/squan/models/Qwen3-VL-8B-Instruct"
)

VIDEO_PROMPT = """The video shows one target physical object from multiple viewpoints.

Analyze only the target object.

Describe visually observable characteristics that would help recognize the exact same physical object later.

Focus on:
- generic object category
- primary and secondary colors
- shape
- material or surface appearance
- distinctive parts
- logos
- stickers
- visible text
- scratches
- labels
- patterns
- unusual geometry or markings

Ignore the surrounding environment, table, room, hands, and unrelated objects.

Do not invent features that are not clearly visible.

Return a concise description."""

PROFILE_PROMPT = """The provided videos show the same personal target object from different viewpoints.

Build a stable visual profile for this specific physical object.

Focus only on the target object.
Ignore the room, background, table, hands, and unrelated objects.

Identify:

1. category
   The generic object category.

2. visual_description
   A concise description of the object's visible appearance.

3. distinctive_features
   A list of the most useful visible characteristics for distinguishing this exact object from other objects of the same category.

Prioritize:
- unusual color combinations
- material
- shape
- stickers
- logos
- visible text
- scratches
- labels
- patterns
- unusual parts
- distinctive geometry

Do not invent details.
Do not infer ownership, location, purpose, or hidden properties.

4. navigation_description
   A short visually grounded noun phrase suitable for telling a robot what object to search for.

The navigation_description must contain only visible characteristics and should be concise.

Return ONLY valid JSON in exactly this form:

{
  "category": "...",
  "visual_description": "...",
  "distinctive_features": [
    "...",
    "..."
  ],
  "navigation_description": "..."
}"""

_model = None
_processor = None
_model_lock = Lock()
_inference_lock = Lock()


def load_model():
    global _model, _processor
    with _model_lock:
        if _model is None:
            _model = Qwen3VLForConditionalGeneration.from_pretrained(
                MODEL_PATH, dtype="auto", device_map="auto"
            )
            _processor = AutoProcessor.from_pretrained(MODEL_PATH)
    return _model, _processor


def is_model_loaded():
    return _model is not None and _processor is not None


def _messages(video_paths, prompt):
    return [{
        "role": "user",
        "content": [
            *({"type": "video", "video": f"file://{Path(p).resolve()}"} for p in video_paths),
            {"type": "text", "text": prompt},
        ],
    }]


def generate_for_videos(video_paths, prompt=VIDEO_PROMPT, max_new_tokens=256):
    paths = [str(Path(p).resolve()) for p in video_paths]
    if not 1 <= len(paths) <= 4:
        raise ValueError("expected between 1 and 4 videos")
    for path in paths:
        if not Path(path).is_file():
            raise FileNotFoundError(path)

    model, processor = load_model()
    messages = _messages(paths, prompt)
    with _inference_lock, torch.inference_mode():
        text = processor.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )
        image_inputs, video_inputs = process_vision_info(messages)
        inputs = processor(
            text=[text], images=image_inputs, videos=video_inputs,
            padding=True, return_tensors="pt"
        ).to(model.device)
        generated = model.generate(**inputs, max_new_tokens=max_new_tokens)
        trimmed = [out[len(inp):] for inp, out in zip(inputs.input_ids, generated)]
        return processor.batch_decode(
            trimmed, skip_special_tokens=True, clean_up_tokenization_spaces=False
        )[0].strip()


def parse_profile(raw_text):
    text = raw_text.strip()
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text, flags=re.IGNORECASE)
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        start, end = text.find("{"), text.rfind("}")
        if start < 0 or end <= start:
            raise ValueError("model output did not contain a JSON object")
        value = json.loads(text[start:end + 1])
    if not isinstance(value, dict):
        raise ValueError("model output JSON must be an object")
    required = ("category", "visual_description", "distinctive_features", "navigation_description")
    if any(not isinstance(value.get(k), str) or not value[k].strip() for k in required if k != "distinctive_features"):
        raise ValueError("profile text fields must be non-empty strings")
    features = value.get("distinctive_features")
    if not isinstance(features, list) or not features or any(not isinstance(x, str) or not x.strip() for x in features):
        raise ValueError("distinctive_features must be a non-empty list of strings")
    return {
        "category": value["category"].strip(),
        "visual_description": value["visual_description"].strip(),
        "distinctive_features": [x.strip() for x in features],
        "navigation_description": value["navigation_description"].strip(),
    }


def generate_profile(video_paths):
    raw = generate_for_videos(video_paths, prompt=PROFILE_PROMPT)
    return parse_profile(raw), raw

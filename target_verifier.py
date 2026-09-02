"""Memory-conscious Qwen3-VL candidate verification using teaching videos only."""
import json
import logging
from enum import Enum
from pathlib import Path

import torch
from pydantic import BaseModel, ConfigDict, Field
from qwen_vl_utils import process_vision_info

import qwen_object_service as base

logger = logging.getLogger("target_verifier")


class VerificationResultType(str, Enum):
    SAME_OBJECT = "same_object"
    DIFFERENT_OBJECT = "different_object"
    UNCERTAIN = "uncertain"


class VerificationResult(BaseModel):
    model_config = ConfigDict(extra="forbid")
    result: VerificationResultType
    confidence: float = Field(ge=0.0, le=1.0)
    evidence: list[str] = Field(min_length=1)
    reason: str = Field(min_length=1)

    @classmethod
    def from_model_output(cls, raw_text: str):
        text = raw_text.strip()
        fence = chr(96) * 3
        if text.startswith(fence):
            text = text[len(fence):]
            if text.lower().startswith("json"):
                text = text[4:]
            if text.endswith(fence):
                text = text[:-len(fence)]
            text = text.strip()
        try:
            value = json.loads(text)
        except json.JSONDecodeError:
            start, end = text.find("{"), text.rfind("}")
            if start < 0 or end <= start:
                raise ValueError("verifier output did not contain a JSON object")
            value = json.loads(text[start:end + 1])
        result = cls.model_validate(value)
        if any(not item.strip() for item in result.evidence):
            raise ValueError("verifier evidence entries must be non-empty strings")
        result.evidence = [item.strip() for item in result.evidence]
        result.reason = result.reason.strip()
        if not result.reason:
            raise ValueError("verifier reason must be non-empty")
        return result


REFERENCE_SUMMARY_PROMPT = """The video shows one taught target physical object.

Describe only visible, instance-specific appearance useful for comparing this object later.
Focus on exact colors, labels, text, graphics, logos, stickers, shape, material, unusual parts, markings, and wear.
Ignore the room, table, hands, and unrelated objects.
Do not invent details.
Return a concise visual reference summary, not JSON."""


VERIFIER_PROMPT = """Compare the taught reference object with the candidate observation sequence.

The stored teaching videos are the sole reference evidence. Do not use any stored text
description, category string, navigation description, user-provided metadata, or hidden
metadata to make the visual judgment.

Determine whether the candidate is the same intended taught physical object, not merely the same category.

Use positive instance-specific visual agreement when visible:
- exact label, text, or graphics
- unusual shape or geometry
- color combinations
- stickers, markings, logos
- structural details
- wear or scratches

Category similarity alone is not sufficient.

Return "same_object" only when there is positive instance-specific visual agreement.
Return "different_object" when visible evidence conflicts with the taught object.
Return "uncertain" when evidence is insufficient, blurry, occluded, too distant, or only category-level similarity is available.
Do not guess.

The candidate images are ordered:
1. oldest recent non-stop frame
2. middle recent non-stop frame
3. newest recent non-stop frame
4. first all-stop frame

Return ONLY valid JSON in exactly this form:
{
  "result": "same_object" | "different_object" | "uncertain",
  "confidence": 0.0,
  "evidence": ["concise visible evidence"],
  "reason": "concise explanation"
}
"""


def _generate_reference_summary(path: Path) -> str:
    return base.generate_for_videos([path], prompt=REFERENCE_SUMMARY_PROMPT, max_new_tokens=256)


def _generate_candidate_result(candidate_paths, prompt: str, progress_callback=None) -> VerificationResult:
    if progress_callback is not None:
        progress_callback("processing_candidate", "preparing candidate images")
    model, processor = base.load_model()
    messages = [{
        "role": "user",
        "content": [
            *({"type": "image", "image": f"file://{Path(path).resolve()}"} for path in candidate_paths),
            {"type": "text", "text": prompt},
        ],
    }]
    if progress_callback is not None:
        progress_callback("final_comparison", "running final candidate/reference comparison")
    with base._inference_lock, torch.inference_mode():
        text = processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        image_inputs, video_inputs = process_vision_info(messages)
        inputs = processor(
            text=[text], images=image_inputs, videos=video_inputs,
            padding=True, return_tensors="pt"
        ).to(model.device)
        generated = model.generate(**inputs, max_new_tokens=256)
        trimmed = [out[len(inp):] for inp, out in zip(inputs.input_ids, generated)]
        raw = processor.batch_decode(
            trimmed, skip_special_tokens=True, clean_up_tokenization_spaces=False
        )[0].strip()
    return VerificationResult.from_model_output(raw)


def verify_candidate(reference_paths, candidate_paths, progress_callback=None) -> VerificationResult:
    if not reference_paths:
        raise ValueError("no teaching reference videos found")
    summaries = []
    for index, path in enumerate(reference_paths, 1):
        logger.info("[TargetVerifier] summarizing reference clip %d/%d", index, len(reference_paths))
        if progress_callback is not None:
            progress_callback("loading_reference", f"reference clip {index}/{len(reference_paths)}")
            progress_callback(f"reference_{index}_of_{len(reference_paths)}", "start")
        summaries.append(_generate_reference_summary(Path(path)))
        if progress_callback is not None:
            progress_callback(f"reference_{index}_of_{len(reference_paths)}", "complete")

    reference_context = "\n\n".join(
        f"Reference clip {index}: {summary}" for index, summary in enumerate(summaries, 1)
    )
    prompt = (
        VERIFIER_PROMPT
        + "\nVisual summaries from all stored teaching clips (the sole reference evidence):\n"
        + reference_context
    )
    logger.info(
        "[TargetVerifier] comparing %d candidate frames against %d reference clips",
        len(candidate_paths), len(reference_paths)
    )
    return _generate_candidate_result(candidate_paths, prompt, progress_callback)

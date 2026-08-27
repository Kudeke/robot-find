"""Memory-bounded multi-video profile fallback for a single 24 GiB GPU."""

import torch

import qwen_object_service as base


def _profile_from_descriptions(descriptions):
    model, processor = base.load_model()
    joined = "\n\n".join(
        f"Video {index}: {description}" for index, description in enumerate(descriptions, 1)
    )
    prompt = base.PROFILE_PROMPT + "\n\nObserved descriptions from all teaching clips:\n" + joined
    messages = [{"role": "user", "content": [{"type": "text", "text": prompt}]}]
    with base._inference_lock, torch.inference_mode():
        text = processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        inputs = processor(text=[text], padding=True, return_tensors="pt").to(model.device)
        generated = model.generate(**inputs, max_new_tokens=256)
        trimmed = [out[len(inp):] for inp, out in zip(inputs.input_ids, generated)]
        return processor.batch_decode(
            trimmed, skip_special_tokens=True, clean_up_tokenization_spaces=False
        )[0].strip()


def generate_profile(video_paths):
    descriptions = []
    for path in video_paths:
        descriptions.append(base.generate_for_videos([path], prompt=base.VIDEO_PROMPT))
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    raw = _profile_from_descriptions(descriptions)
    return base.parse_profile(raw), raw, descriptions

import os
from pathlib import Path

import torch
from qwen_vl_utils import process_vision_info
from transformers import AutoProcessor, Qwen3VLForConditionalGeneration

MODEL_PATH = "/cvhci/temp/squan/models/Qwen3-VL-8B-Instruct"
IMAGE_PATH = "/cvhci/temp/squan/qwen_object_service/samples/object.jpg"
OUTPUT_PATH = "/cvhci/temp/squan/qwen_object_service/output_image_test.txt"

PROMPT = """Analyze the main physical object in this image.

Describe only visually observable characteristics that would help recognize the exact same physical object later.

Include:
- object category
- primary and secondary colors
- shape
- material or surface appearance
- distinctive parts
- markings, stickers, logos, or visible text
- unusual visual characteristics

Ignore the background unless it is necessary to understand the object.

Return a concise object description."""


def main() -> None:
    if not Path(IMAGE_PATH).is_file():
        raise FileNotFoundError(IMAGE_PATH)

    model = Qwen3VLForConditionalGeneration.from_pretrained(
        MODEL_PATH,
        dtype="auto",
        device_map="auto",
    )
    processor = AutoProcessor.from_pretrained(MODEL_PATH)

    messages = [
        {
            "role": "user",
            "content": [
                {"type": "image", "image": f"file://{IMAGE_PATH}"},
                {"type": "text", "text": PROMPT},
            ],
        }
    ]

    text = processor.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    image_inputs, video_inputs = process_vision_info(messages)
    inputs = processor(
        text=[text],
        images=image_inputs,
        videos=video_inputs,
        padding=True,
        return_tensors="pt",
    )
    inputs = inputs.to(model.device)

    with torch.inference_mode():
        generated_ids = model.generate(**inputs, max_new_tokens=256)
    generated_ids_trimmed = [
        out_ids[len(in_ids) :]
        for in_ids, out_ids in zip(inputs.input_ids, generated_ids)
    ]
    result = processor.batch_decode(
        generated_ids_trimmed,
        skip_special_tokens=True,
        clean_up_tokenization_spaces=False,
    )[0].strip()

    Path(OUTPUT_PATH).write_text(
        "Model:\n"
        f"{MODEL_PATH}\n\n"
        "Image:\n"
        f"{IMAGE_PATH}\n\n"
        "Prompt:\n"
        f"{PROMPT}\n\n"
        "Result:\n"
        f"{result}\n",
        encoding="utf-8",
    )
    print(result)
    print(f"Saved output to: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()

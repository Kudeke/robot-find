# coding: utf-8
"""Realtime wrapper for the verified offline Uni-NaVid inference path.

This file intentionally copies the required UniNaVid_Agent implementation from
offline_eval_uninavid.py so importing the realtime service never triggers the
offline script's main routine.
"""

import re
import threading
import time
from typing import Optional

import cv2  # noqa: F401 - documents and preserves the BGR cv2 image path
import numpy as np
import torch

from uninavid.constants import (
    DEFAULT_IMAGE_TOKEN,
    DEFAULT_IM_END_TOKEN,
    DEFAULT_IM_START_TOKEN,
    IMAGE_TOKEN_INDEX,
)
from uninavid.conversation import SeparatorStyle, conv_templates
from uninavid.mm_utils import (
    KeywordsStoppingCriteria,
    get_model_name_from_path,
    tokenizer_image_token,
)
from uninavid.model.builder import load_pretrained_model


VALID_ACTIONS = {"forward", "left", "right", "stop"}
DEFAULT_MODEL_PATH = "model_zoo/uninavid-7b-full-224-video-fps-1-grid-2"


class UniNaVid_Agent:
    """Agent copied from offline_eval_uninavid.py's verified implementation."""

    def __init__(self, model_path):
        print("Initialize UniNaVid")

        self.conv_mode = "vicuna_v1"
        self.model_name = get_model_name_from_path(model_path)
        self.tokenizer, self.model, self.image_processor, self.context_len = load_pretrained_model(
            model_path, None, get_model_name_from_path(model_path)
        )

        assert self.image_processor is not None

        print("Initialization Complete")

        self.promt_template = (
            "Imagine you are a robot programmed for navigation tasks. You have "
            "been given a video of historical observations and an image of the "
            "current observation <image>. Your assigned task is: '{}'. Analyze "
            "this series of images to determine your next four actions. The "
            "predicted action should be one of the following: forward, left, "
            "right, or stop."
        )
        self.rgb_list = []
        self.count_id = 0
        self.reset()

    def process_images(self, rgb_list):
        batch_image = np.asarray(rgb_list)
        self.model.get_model().new_frames = len(rgb_list)
        video = self.image_processor.preprocess(batch_image, return_tensors="pt")[
            "pixel_values"
        ].half().cuda()

        return [video]

    def predict_inference(self, prompt):
        question = prompt.replace(DEFAULT_IMAGE_TOKEN, "").replace("\n", "")
        qs = prompt

        video_start_special_token_text = "<video_special>"
        video_end_special_token_text = "</video_special>"
        image_start_token_text = "<image_special>"
        image_end_token_text = "</image_special>"
        navigation_token_text = "[Navigation]"
        image_separator_text = "<image_sep>"

        image_start_special_token = self.tokenizer(
            image_start_token_text, return_tensors="pt"
        ).input_ids[0][1:].cuda()
        image_end_special_token = self.tokenizer(
            image_end_token_text, return_tensors="pt"
        ).input_ids[0][1:].cuda()
        video_start_special_token = self.tokenizer(
            video_start_special_token_text, return_tensors="pt"
        ).input_ids[0][1:].cuda()
        video_end_special_token = self.tokenizer(
            video_end_special_token_text, return_tensors="pt"
        ).input_ids[0][1:].cuda()
        navigation_special_token = self.tokenizer(
            navigation_token_text, return_tensors="pt"
        ).input_ids[0][1:].cuda()
        image_separator = self.tokenizer(
            image_separator_text, return_tensors="pt"
        ).input_ids[0][1:].cuda()

        if self.model.config.mm_use_im_start_end:
            qs = (
                DEFAULT_IM_START_TOKEN
                + DEFAULT_IMAGE_TOKEN
                + DEFAULT_IM_END_TOKEN
                + "\n"
                + qs.replace("<image>", "")
            )
        else:
            qs = DEFAULT_IMAGE_TOKEN + "\n" + qs.replace("<image>", "")

        conv = conv_templates[self.conv_mode].copy()
        conv.append_message(conv.roles[0], qs)
        conv.append_message(conv.roles[1], None)
        prompt = conv.get_prompt()

        token_prompt = tokenizer_image_token(
            prompt, self.tokenizer, IMAGE_TOKEN_INDEX, return_tensors="pt"
        ).cuda()
        indices_to_replace = torch.where(token_prompt == -200)[0]
        new_list = []
        while indices_to_replace.numel() > 0:
            idx = indices_to_replace[0]
            new_list.append(token_prompt[:idx])
            new_list.append(video_start_special_token)
            new_list.append(image_separator)
            new_list.append(token_prompt[idx : idx + 1])
            new_list.append(video_end_special_token)
            new_list.append(image_start_special_token)
            new_list.append(image_end_special_token)
            new_list.append(navigation_special_token)
            token_prompt = token_prompt[idx + 1 :]
            indices_to_replace = torch.where(token_prompt == -200)[0]
        if token_prompt.numel() > 0:
            new_list.append(token_prompt)
        input_ids = torch.cat(new_list, dim=0).unsqueeze(0)

        stop_str = conv.sep if conv.sep_style != SeparatorStyle.TWO else conv.sep2
        keywords = [stop_str]
        stopping_criteria = KeywordsStoppingCriteria(keywords, self.tokenizer, input_ids)

        imgs = self.process_images(self.rgb_list)
        self.rgb_list = []

        cur_prompt = question
        with torch.inference_mode():
            self.model.update_prompt([[cur_prompt]])
            output_ids = self.model.generate(
                input_ids,
                images=imgs,
                do_sample=True,
                temperature=0.5,
                max_new_tokens=1024,
                use_cache=True,
                stopping_criteria=[stopping_criteria],
            )

        input_token_len = input_ids.shape[1]
        n_diff_input_output = (input_ids != output_ids[:, :input_token_len]).sum().item()
        if n_diff_input_output > 0:
            print(
                f"[Warning] {n_diff_input_output} output_ids are not the same as "
                "the input_ids"
            )
        outputs = self.tokenizer.batch_decode(
            output_ids[:, input_token_len:], skip_special_tokens=True
        )[0]
        outputs = outputs.strip()
        if outputs.endswith(stop_str):
            outputs = outputs[: -len(stop_str)]
        outputs = outputs.strip()

        return outputs

    def reset(self, task_type="vln"):
        self.transformation_list = []
        self.rgb_list = []
        self.last_action = None
        self.count_id += 1
        self.count_stop = 0
        self.pending_action_list = []
        self.task_type = task_type

        self.first_forward = False
        self.executed_steps = 0
        self.model.config.run_type = "eval"
        self.model.get_model().initialize_online_inference_nav_feat_cache()
        self.model.get_model().new_frames = 0

    def act(self, data):
        # Input image is BGR, matching cv2.imread/cv2.imdecode behavior in the
        # verified offline path. Do not convert to RGB here.
        image_bgr = data["observations"]
        self.rgb_list.append(image_bgr)

        navigation_qs = self.promt_template.format(data["instruction"])
        navigation = self.predict_inference(navigation_qs)
        action_list = parse_actions(navigation)

        traj = [[0.0, 0.0, 0.0]]
        for action in action_list:
            if action == "stop":
                traj = [
                    [0.0, 0.0, 0.0],
                    [0.0, 0.0, 0.0],
                    [0.0, 0.0, 0.0],
                    [0.0, 0.0, 0.0],
                ]
                break
            if action == "forward":
                waypoint = [x + y for x, y in zip(traj[-1], [0.5, 0.0, 0.0])]
                traj.append(waypoint)
            elif action == "left":
                waypoint = [x + y for x, y in zip(traj[-1], [0.0, 0.0, -np.deg2rad(30)])]
                traj.append(waypoint)
            elif action == "right":
                waypoint = [x + y for x, y in zip(traj[-1], [0.0, 0.0, np.deg2rad(30)])]
                traj.append(waypoint)

        self.executed_steps += 1
        self.latest_action = {
            "step": self.executed_steps,
            "path": [traj],
            "actions": action_list,
            "raw_output": navigation,
        }

        return self.latest_action.copy()


def parse_actions(raw_output: str) -> list[str]:
    cleaned = re.sub(r"[,.\n\r\t]+", " ", raw_output.lower())
    actions = [token for token in cleaned.split() if token in VALID_ACTIONS]
    actions = actions[:4]
    return actions or ["stop"]


class UniNaVidEngine:
    def __init__(self, model_path: str = DEFAULT_MODEL_PATH):
        self.model_path = model_path
        self.agent = UniNaVid_Agent(model_path)
        self.lock = threading.Lock()
        self.active_session_id: Optional[str] = None
        self.instruction: Optional[str] = None

    def reset_session(self, session_id: str, instruction: str) -> dict:
        if not session_id:
            raise ValueError("session_id must not be empty")
        if not instruction:
            raise ValueError("instruction must not be empty")

        with self.lock:
            self.agent.reset()
            self.active_session_id = session_id
            self.instruction = instruction
            return {"session_id": session_id}

    def predict(
        self,
        session_id: str,
        image_bgr: np.ndarray,
        instruction: str | None = None,
    ) -> dict:
        if not session_id:
            return self._stop_result(session_id, "session_id must not be empty")
        if image_bgr is None:
            return self._stop_result(session_id, "image_bgr must not be None")

        with self.lock:
            try:
                if self.active_session_id != session_id:
                    active = self.active_session_id or "<none>"
                    raise ValueError(
                        f"session_id {session_id!r} is not active; active session is {active!r}"
                    )

                active_instruction = instruction or self.instruction
                if not active_instruction:
                    raise ValueError("instruction is required before inference")
                if instruction:
                    self.instruction = instruction

                start = time.perf_counter()
                result = self.agent.act(
                    {"instruction": active_instruction, "observations": image_bgr}
                )
                inference_ms = (time.perf_counter() - start) * 1000.0

                raw_output = result.get("raw_output", "")
                actions = parse_actions(raw_output)
                return {
                    "session_id": session_id,
                    "raw_output": raw_output,
                    "actions": actions,
                    "path": result.get("path", []),
                    "step": result.get("step", 0),
                    "inference_ms": inference_ms,
                }
            except Exception as exc:  # noqa: BLE001 - keep service alive on inference errors
                return self._stop_result(session_id, str(exc))

    def close_session(self, session_id: str) -> None:
        with self.lock:
            if self.active_session_id == session_id:
                self.agent.reset()
                self.active_session_id = None
                self.instruction = None

    def _stop_result(self, session_id: str, error: str) -> dict:
        return {
            "session_id": session_id,
            "raw_output": "",
            "actions": ["stop"],
            "path": [],
            "step": 0,
            "inference_ms": 0.0,
            "error": error,
        }

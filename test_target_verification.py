#!/usr/bin/env python3
"""Focused Phase 4 state-machine tests; no Qwen or robot runtime required."""
import os
import tempfile
import unittest

from mission.mission_store import save_mission
from mission.runtime_manager import RuntimeInvalidTransition, RuntimeManager
from mission.schemas import Mission, MissionState


class TargetVerificationStateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="robotfind-phase4-test-")
        os.environ["FINDMYTHINGS_DATA_DIR"] = self.temp.name
        self.manager = RuntimeManager()
        self.counter = 0

    def tearDown(self):
        os.environ.pop("FINDMYTHINGS_DATA_DIR", None)
        self.temp.cleanup()

    def mission(self):
        self.counter += 1
        value = Mission.ready(
            f"mission_test_{self.counter}",
            "obj_test",
            "Test object",
            "Find the test object.",
        )
        save_mission(value)
        return value.mission_id

    def running(self, mission_id):
        self.manager.start(mission_id)
        self.manager.runtime_started(mission_id)

    def test_same_object_then_completion(self):
        mission_id = self.mission()
        self.running(mission_id)
        self.manager.begin_verification(mission_id)
        self.assertEqual(self.manager.apply_verification(mission_id, "same_object").state, MissionState.VERIFYING)
        self.assertEqual(self.manager.runtime_completed(mission_id).state, MissionState.TARGET_FOUND)
        self.assertIsNone(self.manager.get_active())

    def test_rejected_candidates_resume(self):
        for result in ("different_object", "uncertain"):
            mission_id = self.mission()
            self.running(mission_id)
            self.manager.begin_verification(mission_id)
            self.assertEqual(self.manager.apply_verification(mission_id, result).state, MissionState.RESUMING)
            self.assertEqual(self.manager.runtime_resumed(mission_id).state, MissionState.RUNNING)
            self.manager.runtime_failed(mission_id, "test cleanup")

    def test_invalid_state_rejections(self):
        mission_id = self.mission()
        with self.assertRaises(RuntimeInvalidTransition):
            self.manager.runtime_completed(mission_id)
        self.running(mission_id)
        self.manager.begin_verification(mission_id)
        with self.assertRaises(RuntimeInvalidTransition):
            self.manager.begin_verification(mission_id)
        with self.assertRaises(RuntimeInvalidTransition):
            self.manager.runtime_resumed(mission_id)

    def test_manual_stop_from_verifying_and_resuming(self):
        verifying = self.mission()
        self.running(verifying)
        self.manager.begin_verification(verifying)
        self.assertEqual(self.manager.stop(verifying).state, MissionState.STOPPING)
        self.manager.runtime_stopped(verifying)

        resuming = self.mission()
        self.running(resuming)
        self.manager.begin_verification(resuming)
        self.manager.apply_verification(resuming, "uncertain")
        self.assertEqual(self.manager.stop(resuming).state, MissionState.STOPPING)
        self.manager.runtime_stopped(resuming)


if __name__ == "__main__":
    unittest.main()

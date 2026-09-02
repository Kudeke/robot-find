#!/usr/bin/env python3
"""Persistence and worker-failure tests for verification observability; no Qwen required."""
import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from mission.verification_store import (
    VerificationStatus,
    create_candidate_files,
    create_verification,
    load_verification,
    save_verification_record,
    update_completed,
    update_failed,
    update_progress,
)


class VerificationObservabilityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="robotfind-verifier-observability-")
        os.environ["FINDMYTHINGS_DATA_DIR"] = self.temp.name

    def tearDown(self):
        os.environ.pop("FINDMYTHINGS_DATA_DIR", None)
        self.temp.cleanup()

    def record(self, candidate_id="cand_observe"):
        create_candidate_files(
            "mission_observe", candidate_id,
            {name: b"jpeg" for name in ("last_non_stop_1", "last_non_stop_2", "last_non_stop_3", "first_stop")},
        )
        return create_verification("mission_observe", candidate_id, "obj_observe")

    def test_new_record_and_progress_are_persisted(self):
        record = self.record()
        self.assertEqual(record.status, VerificationStatus.PROCESSING)
        self.assertEqual(record.stage, "queued")
        self.assertTrue(record.updated_at)
        update_progress(record, "reference_2_of_4", "complete")
        loaded = load_verification("mission_observe", "cand_observe")
        self.assertEqual(loaded.stage, "reference_2_of_4")
        self.assertEqual(loaded.progress_detail, "complete")
        self.assertTrue(loaded.updated_at)

    def test_completed_record_has_terminal_stage(self):
        record = self.record("cand_complete")
        result = SimpleNamespace(
            result=SimpleNamespace(value="different_object"),
            confidence=0.99,
            evidence=["different visible label"],
            reason="visible details conflict",
        )
        update_completed(record, result)
        loaded = load_verification("mission_observe", "cand_complete")
        self.assertEqual(loaded.status, VerificationStatus.COMPLETED)
        self.assertEqual(loaded.stage, "completed")
        self.assertTrue(loaded.updated_at)
        self.assertTrue(loaded.completed_at)

    def test_worker_exception_persists_failed_record(self):
        record = self.record("cand_failed")

        class RuntimeStub:
            def fail_verification(self, mission_id, error):
                return None

        from mission import verification_manager
        with patch.object(verification_manager, "verify_candidate", side_effect=RuntimeError("inference boom")):
            manager = verification_manager.VerificationJobManager(RuntimeStub())
            manager._run(record, [Path("reference.mp4")])
            manager.executor.shutdown(wait=True)

        loaded = load_verification("mission_observe", "cand_failed")
        self.assertEqual(loaded.status, VerificationStatus.FAILED)
        self.assertEqual(loaded.stage, "failed")
        self.assertTrue(loaded.error)
        self.assertTrue(loaded.updated_at)
        self.assertTrue(loaded.completed_at)

    def test_old_record_without_observability_fields_loads(self):
        directory = Path(self.temp.name) / "missions" / "mission_observe" / "verifications" / "cand_old"
        directory.mkdir(parents=True)
        legacy = {
            "candidate_id": "cand_old", "mission_id": "mission_observe", "object_id": "obj_observe",
            "status": "completed", "result": "same_object", "confidence": 0.8,
            "evidence": ["mark"], "reason": "match", "error": None,
            "created_at": "2026-01-01T00:00:00Z", "completed_at": "2026-01-01T00:01:00Z",
            "candidate_files": {},
        }
        (directory / "verification.json").write_text(json.dumps(legacy))
        loaded = load_verification("mission_observe", "cand_old")
        self.assertEqual(loaded.status, VerificationStatus.COMPLETED)
        self.assertIsNone(loaded.stage)
        self.assertIsNone(loaded.updated_at)


if __name__ == "__main__":
    unittest.main()

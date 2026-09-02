#!/usr/bin/env python3
"""Mocked Phase 4 candidate-idempotency API tests; no Qwen or robot runtime required."""
import json
import os
import tempfile
import threading
import time
import unittest
from io import BytesIO
from pathlib import Path
from unittest.mock import patch

from PIL import Image


class CandidateIdempotencyTest(unittest.TestCase):
    def test_duplicate_candidate_runs_verifier_once(self):
        with tempfile.TemporaryDirectory(prefix="robotfind-phase4-idempotency-") as root:
            os.environ["FINDMYTHINGS_DATA_DIR"] = root
            object_dir = Path(root) / "objects" / "obj_test"
            object_dir.mkdir(parents=True)
            (object_dir / "profile.json").write_text(json.dumps({
                "object_id": "obj_test",
                "name": "Test object",
                "category": "object",
                "visual_description": "unused",
                "distinctive_features": ["blue"],
                "navigation_description": "blue object",
                "created_at": "2026-01-01T00:00:00Z",
            }))
            for index in range(1, 5):
                (object_dir / ("clip_%02d.mp4" % index)).write_bytes(b"fake-mp4")

            from mission.mission_store import save_mission
            from mission.schemas import Mission
            mission_id = "mission_idempotency_test"
            save_mission(Mission.ready(mission_id, "obj_test", "Test object", "Find the blue object."))

            import object_store
            object_store.OBJECTS_ROOT = Path(root) / "objects"
            import api_server_phase3_fixed
            from fastapi.testclient import TestClient
            from target_verifier import VerificationResult

            client = TestClient(api_server_phase3_fixed.app)
            self.assertEqual(client.post("/api/v1/missions/%s/start" % mission_id).status_code, 200)
            self.assertEqual(client.post("/api/v1/missions/%s/runtime-started" % mission_id).status_code, 200)

            image = BytesIO()
            Image.new("RGB", (8, 8), (1, 2, 3)).save(image, format="JPEG")
            jpeg = image.getvalue()

            def files():
                return {
                    name: (name + ".jpg", jpeg, "image/jpeg")
                    for name in ("last_non_stop_1", "last_non_stop_2", "last_non_stop_3", "first_stop")
                }

            entered = threading.Event()
            release = threading.Event()
            calls = []

            def fake_verify(reference_paths, candidate_paths, progress_callback=None):
                calls.append((list(reference_paths), list(candidate_paths)))
                entered.set()
                release.wait(10)
                return VerificationResult(
                    result="same_object",
                    confidence=0.9,
                    evidence=["same visible mark"],
                    reason="mock match",
                )

            with patch("mission.verification_manager.verify_candidate", side_effect=fake_verify):
                first = client.post(
                    "/api/v1/missions/%s/verify-candidate" % mission_id,
                    data={"candidate_id": "cand_test"},
                    files=files(),
                )
                self.assertEqual(first.status_code, 202, first.text)
                self.assertTrue(entered.wait(5))

                processing = client.get(
                    "/api/v1/missions/%s/verifications/cand_test" % mission_id
                )
                self.assertEqual(processing.json()["status"], "processing")
                self.assertTrue(processing.json()["stage"])
                self.assertTrue(processing.json()["updated_at"])

                duplicate = client.post(
                    "/api/v1/missions/%s/verify-candidate" % mission_id,
                    data={"candidate_id": "cand_test"},
                    files=files(),
                )
                self.assertEqual(duplicate.status_code, 202)

                other = client.post(
                    "/api/v1/missions/%s/verify-candidate" % mission_id,
                    data={"candidate_id": "cand_other"},
                    files=files(),
                )
                self.assertEqual(other.status_code, 409)

                release.set()
                deadline = time.time() + 10
                record = None
                while time.time() < deadline:
                    record = client.get(
                        "/api/v1/missions/%s/verifications/cand_test" % mission_id
                    ).json()
                    if record["status"] == "completed":
                        break
                    time.sleep(0.1)
                self.assertEqual(record["status"], "completed")
                self.assertEqual(record["stage"], "completed")
                self.assertTrue(record["updated_at"])

                duplicate_completed = client.post(
                    "/api/v1/missions/%s/verify-candidate" % mission_id,
                    data={"candidate_id": "cand_test"},
                    files=files(),
                )
                self.assertEqual(duplicate_completed.status_code, 200)
                self.assertEqual(duplicate_completed.json(), record)
                self.assertEqual(len(calls), 1)

                candidate_root = Path(root) / "missions" / mission_id / "verifications" / "cand_test"
                for name in ("last_non_stop_1", "last_non_stop_2", "last_non_stop_3", "first_stop"):
                    self.assertEqual((candidate_root / (name + ".jpg")).stat().st_size, len(jpeg))
                self.assertTrue((candidate_root / "verification.json").is_file())
                self.assertEqual(
                    client.post("/api/v1/missions/%s/runtime-completed" % mission_id).json()["state"],
                    "target_found",
                )

            os.environ.pop("FINDMYTHINGS_DATA_DIR", None)


if __name__ == "__main__":
    unittest.main()

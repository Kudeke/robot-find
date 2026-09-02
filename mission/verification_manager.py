import logging
import time
from concurrent.futures import ThreadPoolExecutor
from threading import RLock

from target_verifier import verify_candidate
from .runtime_manager import RuntimeInvalidTransition, RuntimeManager
from .verification_store import (
    VerificationRecord,
    VerificationStatus,
    candidate_path_map,
    list_processing_records,
    now_iso,
    save_verification_record,
    update_completed,
    update_failed,
    update_progress,
)

logger = logging.getLogger("mission.verification")


class VerificationJobManager:
    def __init__(self, runtime_manager: RuntimeManager):
        self.runtime_manager = runtime_manager
        self.lock = RLock()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="target-verifier")
        self.recover_processing_records()

    def recover_processing_records(self):
        for record in list_processing_records():
            record.status = VerificationStatus.FAILED
            record.stage = "failed"
            record.updated_at = now_iso()
            record.progress_detail = "verification service restarted before completion"
            record.error = "verification service restarted before candidate verification completed"
            record.completed_at = record.updated_at
            save_verification_record(record)
            logger.warning("[TargetVerifier] recovered candidate_id=%s as failed", record.candidate_id)

    def submit(self, record: VerificationRecord, reference_paths):
        with self.lock:
            self.executor.submit(self._run, record, list(reference_paths))

    def _progress_callback(self, record: VerificationRecord, started_at: float, reference_started: dict):
        def progress(stage: str, detail: str | None = None):
            update_progress(record, stage, detail)
            elapsed = time.monotonic() - started_at
            if stage.startswith("reference_") and detail == "start":
                reference_started[stage] = time.monotonic()
                logger.info("[VerifierJob] %s start", stage)
            elif stage.startswith("reference_") and detail == "complete":
                duration = elapsed
                begin = reference_started.get(stage)
                if begin is not None:
                    duration = time.monotonic() - begin
                logger.info("[VerifierJob] %s complete elapsed=%.1fs", stage, duration)
            else:
                logger.info("[VerifierJob] candidate stage=%s detail=%s elapsed=%.1fs", stage, detail or "", elapsed)
        return progress

    def _run(self, record: VerificationRecord, reference_paths):
        started_at = time.monotonic()
        logger.info("[VerifierJob] candidate=%s started", record.candidate_id)
        paths = candidate_path_map(record.mission_id, record.candidate_id)
        candidate_paths = [paths[name] for name in paths]
        try:
            update_progress(record, "waiting_for_inference_lock", "waiting for Qwen inference lock")
            logger.info("[VerifierJob] waiting for Qwen inference lock")
            reference_started = {}
            result = verify_candidate(
                reference_paths,
                candidate_paths,
                progress_callback=self._progress_callback(record, started_at, reference_started),
            )
            update_completed(record, result)
            total = time.monotonic() - started_at
            logger.info(
                "[VerifierJob] completed result=%s confidence=%.2f total_elapsed=%.1fs",
                result.result.value, result.confidence, total,
            )
            try:
                self.runtime_manager.apply_verification(record.mission_id, result.result.value)
            except RuntimeInvalidTransition:
                logger.info(
                    "[VerifierJob] mission state changed before result application mission_id=%s candidate_id=%s",
                    record.mission_id, record.candidate_id,
                )
        except Exception:
            logger.exception("[VerifierJob] failed candidate=%s", record.candidate_id)
            try:
                update_failed(record, "target verification failed")
                self.runtime_manager.fail_verification(record.mission_id, "target verification failed")
            except RuntimeInvalidTransition:
                pass

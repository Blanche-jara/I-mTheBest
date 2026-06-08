"""
분석 작업(Job) 관리 — 백그라운드 스레드에서 engine.analyze 를 돌리고
진행률을 갱신한다. 서버는 이 상태를 REST/WebSocket 으로 노출한다.
"""
from __future__ import annotations

import os
import threading
import traceback
import uuid
from dataclasses import dataclass, field
from typing import Optional

from engine import analyze, AnalysisParams, AnalysisResult


@dataclass
class Job:
    id: str
    video_path: str
    params: AnalysisParams
    out_dir: str
    status: str = "queued"            # queued | running | done | error
    progress: float = 0.0
    stage: str = ""
    message: str = ""
    error: Optional[str] = None
    result: Optional[AnalysisResult] = None
    _thread: Optional[threading.Thread] = field(default=None, repr=False)


class JobManager:
    def __init__(self, output_base: str, files_route: str = "/files"):
        self.output_base = os.path.abspath(output_base)
        self.files_route = files_route
        os.makedirs(self.output_base, exist_ok=True)
        self._jobs: dict[str, Job] = {}
        self._lock = threading.Lock()

    def create(self, video_path: str, params: dict | None) -> Job:
        job_id = uuid.uuid4().hex[:12]
        out_dir = os.path.join(self.output_base, job_id)
        os.makedirs(out_dir, exist_ok=True)
        job = Job(id=job_id, video_path=video_path,
                  params=AnalysisParams.from_dict(params), out_dir=out_dir)
        with self._lock:
            self._jobs[job_id] = job
        t = threading.Thread(target=self._run, args=(job,), daemon=True)
        job._thread = t
        t.start()
        return job

    def get(self, job_id: str) -> Optional[Job]:
        return self._jobs.get(job_id)

    def _run(self, job: Job):
        job.status = "running"

        def progress(frac: float, stage: str):
            job.progress = float(frac)
            job.stage = stage
            job.message = stage

        try:
            result = analyze(job.video_path, job.params, out_dir=job.out_dir,
                             progress=progress)
            self._attach_urls(job, result)
            job.result = result
            job.progress = 1.0
            job.status = "done"
            job.stage = "완료"
            # 결과 JSON 도 디스크에 저장(인수인계/재현용)
            with open(os.path.join(job.out_dir, "result.json"), "w", encoding="utf-8") as f:
                f.write(result.model_dump_json(indent=2))
        except Exception as e:
            job.status = "error"
            job.error = f"{e}"
            job.message = f"오류: {e}"
            traceback.print_exc()

    def _attach_urls(self, job: Job, result: AnalysisResult):
        """절대 클립 경로를 서버 정적 URL 로도 노출(원격/웹 재생 대비)."""
        for h in result.highlights:
            if h.clip_path:
                rel = os.path.relpath(h.clip_path, self.output_base).replace("\\", "/")
                h.clip_url = f"{self.files_route}/{rel}"
            if h.thumbnail_path:
                rel = os.path.relpath(h.thumbnail_path, self.output_base).replace("\\", "/")
                h.thumbnail_url = f"{self.files_route}/{rel}"

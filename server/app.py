"""
FastAPI 로컬 서버.

엔드포인트
  GET  /health              서버/엔진/GPU 상태
  POST /analyze             분석 시작 → {job_id}
  GET  /jobs/{id}           작업 상태(+완료 시 결과)
  GET  /jobs/{id}/result    완료된 결과(AnalysisResult)
  WS   /ws/{id}             진행률 실시간 스트림
  GET  /files/...           생성된 클립/썸네일 정적 서빙

실행:  python -m server.app   또는   uvicorn server.app:app --port 8000
GUI(Flutter)는 기본적으로 http://127.0.0.1:8000 으로 접속한다.
"""
from __future__ import annotations

import asyncio
import os

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from engine.models import AnalyzeRequest, JobStatus
from .jobs import JobManager

OUTPUT_BASE = os.environ.get("HL_OUTPUT_DIR", os.path.abspath("output"))
FILES_ROUTE = "/files"

app = FastAPI(title="게임 하이라이트 추출 엔진", version="0.1.0")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)

manager = JobManager(OUTPUT_BASE, files_route=FILES_ROUTE)
os.makedirs(OUTPUT_BASE, exist_ok=True)
app.mount(FILES_ROUTE, StaticFiles(directory=OUTPUT_BASE), name="files")


def _gpu_info() -> dict:
    try:
        import torch
        return {"torch": torch.__version__,
                "cuda": bool(torch.cuda.is_available()),
                "device": (torch.cuda.get_device_name(0)
                           if torch.cuda.is_available() else "cpu")}
    except Exception:
        return {"torch": None, "cuda": False, "device": "cpu"}


@app.get("/health")
def health():
    import sys
    info = {"status": "ok", "python": sys.version.split()[0],
            "output_dir": OUTPUT_BASE}
    info.update(_gpu_info())
    try:
        import cv2; info["opencv"] = cv2.__version__
    except Exception:
        info["opencv"] = None
    try:
        import librosa; info["librosa"] = librosa.__version__
    except Exception:
        info["librosa"] = None
    return info


@app.post("/analyze")
def analyze_endpoint(req: AnalyzeRequest):
    if not os.path.exists(req.video_path):
        raise HTTPException(status_code=400, detail=f"영상 파일을 찾을 수 없습니다: {req.video_path}")
    job = manager.create(req.video_path, req.params)
    return {"job_id": job.id}


def _status(job) -> JobStatus:
    return JobStatus(
        job_id=job.id, status=job.status, progress=job.progress,
        stage=job.stage, message=job.message, error=job.error,
        result=job.result if job.status == "done" else None,
    )


@app.get("/jobs/{job_id}", response_model=JobStatus)
def job_status(job_id: str):
    job = manager.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="작업을 찾을 수 없습니다")
    return _status(job)


@app.get("/jobs/{job_id}/result")
def job_result(job_id: str):
    job = manager.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="작업을 찾을 수 없습니다")
    if job.status != "done" or job.result is None:
        raise HTTPException(status_code=409, detail=f"아직 완료되지 않음(status={job.status})")
    return job.result


@app.websocket("/ws/{job_id}")
async def ws_progress(websocket: WebSocket, job_id: str):
    await websocket.accept()
    job = manager.get(job_id)
    if not job:
        await websocket.send_json({"error": "작업을 찾을 수 없습니다"})
        await websocket.close()
        return
    try:
        last = -1.0
        while True:
            payload = {"job_id": job.id, "status": job.status,
                       "progress": round(job.progress, 4), "stage": job.stage,
                       "message": job.message}
            if job.progress != last or job.status in ("done", "error"):
                await websocket.send_json(payload)
                last = job.progress
            if job.status in ("done", "error"):
                break
            await asyncio.sleep(0.25)
    except WebSocketDisconnect:
        return
    finally:
        try:
            await websocket.close()
        except Exception:
            pass


def main():
    import uvicorn
    port = int(os.environ.get("HL_PORT", "8000"))
    uvicorn.run(app, host="127.0.0.1", port=port)


if __name__ == "__main__":
    main()

"""
API / 결과 데이터 모델 (pydantic v2).

이 파일이 Python 엔진과 Flutter GUI 사이의 "계약(contract)"이다.
여기 정의된 JSON 구조 그대로 서버가 내보내고 Flutter 가 파싱한다.
필드를 바꾸면 app/lib/models 의 Dart 모델도 함께 바꿔야 한다.
"""
from __future__ import annotations

from typing import Optional
from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
#  시계열 — 시간축 t 와 각 채널의 surprise(bits) 배열. 모두 길이가 같다.
# ---------------------------------------------------------------------------
class Timeline(BaseModel):
    t: list[float] = Field(default_factory=list, description="윈도 중심 시각(초)")
    frame_entropy: list[float] = Field(default_factory=list)
    motion: list[float] = Field(default_factory=list)
    spectral: list[float] = Field(default_factory=list)
    cheer: list[float] = Field(default_factory=list)
    loudness: list[float] = Field(default_factory=list)
    fused: list[float] = Field(default_factory=list, description="융합된 최종 surprise(bits)")


class ChannelStat(BaseModel):
    name: str
    label_ko: str
    group: str                       # "video" | "audio"
    weight: float                    # 융합 가중치
    mean_bits: float
    peak_bits: float
    mi_with_fused: float             # 융합 결과와의 상호정보량(bits)


class HighlightExplanation(BaseModel):
    total_bits: float                          # 구간 적분 정보량 = 점수
    contributions: dict[str, float]            # 채널별 기여 bits
    dominant_channel: str
    dominant_label_ko: str
    summary_ko: str                            # 사람이 읽을 한 줄 설명


class Highlight(BaseModel):
    id: str
    rank: int
    start_sec: float
    end_sec: float
    peak_sec: float
    score: float                               # = explanation.total_bits
    explanation: HighlightExplanation
    clip_path: Optional[str] = None            # 절대 경로(로컬 재생용)
    clip_url: Optional[str] = None             # 서버 정적 URL
    thumbnail_path: Optional[str] = None
    thumbnail_url: Optional[str] = None


class AnalysisResult(BaseModel):
    video_path: str
    duration_sec: float
    analysis_fps: float
    frame_size: list[int]                      # [w, h]
    timeline: Timeline
    channels: list[ChannelStat]
    highlights: list[Highlight]
    params: dict
    mi_matrix: dict[str, dict[str, float]] = Field(
        default_factory=dict, description="채널 간 상호정보량 행렬(bits)"
    )


# ---------------------------------------------------------------------------
#  서버 요청/응답
# ---------------------------------------------------------------------------
class AnalyzeRequest(BaseModel):
    video_path: str
    params: Optional[dict] = None


class JobStatus(BaseModel):
    job_id: str
    status: str                                # queued | running | done | error
    progress: float = 0.0                      # 0.0 ~ 1.0
    stage: str = ""                            # 현재 단계 이름
    message: str = ""
    error: Optional[str] = None
    result: Optional[AnalysisResult] = None


class ProgressEvent(BaseModel):
    job_id: str
    progress: float
    stage: str
    message: str

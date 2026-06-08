"""
중앙 설정값 (AnalysisParams) 및 기본값.

긴 영상(1시간+)을 빠르게 처리하기 위한 핵심 손잡이는 두 가지다:
  - analysis_fps : 원본을 그대로 보지 않고 초당 몇 프레임만 샘플링할지
  - downscale_width : 옵티컬 플로우/엔트로피 계산용 다운스케일 가로 폭

이 둘이 처리량을 지배한다. 1시간 30fps 영상 = 108,000 프레임이지만
analysis_fps=3, width=256 이면 실제로 다루는 건 10,800 개의 작은 프레임뿐이다.
"""
from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Optional


@dataclass
class AnalysisParams:
    # ---- 영상 채널 ----
    analysis_fps: float = 3.0          # 초당 분석 프레임 수 (샘플링 레이트)
    downscale_width: int = 256         # 분석용 프레임 가로 폭(px); 세로는 비율 유지
    flow_downscale: int = 0            # 0 이면 downscale_width 와 동일하게 사용

    # ---- 오디오 채널 ----
    audio_sr: int = 22050              # 분석용 리샘플링 주파수
    audio_hop: int = 512               # STFT hop length

    # ---- surprise(자기정보) 모델 ----
    surprise_window_sec: float = 6.0   # 자기정보를 추정할 "최근 과거" 윈도(초)
    surprise_bins: int = 32            # 특징값 히스토그램 빈 수

    # ---- 융합 / 하이라이트 검출 ----
    top_k: int = 12                    # 최대 하이라이트 개수
    min_gap_sec: float = 8.0           # 하이라이트 간 최소 간격(초)
    min_clip_sec: float = 12.0         # 클립 최소 길이
    max_clip_sec: float = 30.0         # 클립 최대 길이
    clip_pad_sec: float = 4.0          # 피크 앞뒤 여유(초)
    peak_z: float = 1.2                # 임계값 = mean + peak_z * std (적응형)

    # 채널 가중치. None 이면 mutual-information 기반 자동(최대엔트로피) 가중.
    weight_frame_entropy: Optional[float] = None
    weight_motion: Optional[float] = None
    weight_spectral: Optional[float] = None
    weight_cheer: Optional[float] = None
    weight_loudness: Optional[float] = None

    # ---- 기타 ----
    enable_cheer_model: bool = False   # True 면 torch 학습형 분류기 사용(가능할 때)
    reencode_clips: bool = True        # True: 프레임 정확 컷(재인코딩), False: 빠른 copy
    thumbnail: bool = True

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Optional[dict]) -> "AnalysisParams":
        if not d:
            return cls()
        known = {k: v for k, v in d.items() if k in cls.__dataclass_fields__ and v is not None}
        return cls(**known)


# 채널 식별자 — 코드 전반과 Flutter 대시보드가 공유하는 정식 이름
CHANNELS = [
    "frame_entropy",   # 영상: 프레임 내부 복잡도(공간 엔트로피)의 급변
    "motion",          # 영상: 옵티컬 플로우 motion entropy 의 급변
    "spectral",        # 오디오: 스펙트럼 변화(novelty)
    "cheer",           # 오디오: 환호성/함성
    "loudness",        # 오디오: 음량(RMS) 급변
]

CHANNEL_LABELS_KO = {
    "frame_entropy": "프레임 엔트로피",
    "motion": "모션 엔트로피",
    "spectral": "스펙트럼 변화",
    "cheer": "환호성",
    "loudness": "음량 변화",
}

CHANNEL_GROUP = {
    "frame_entropy": "video",
    "motion": "video",
    "spectral": "audio",
    "cheer": "audio",
    "loudness": "audio",
}

"""
게임 영상 자동 하이라이트 추출 엔진.

정보이론(Shannon self-information, entropy, mutual information) 관점에서
영상·오디오 채널의 surprise 를 계산하고 융합하여 하이라이트를 검출한다.

대표 진입점:
  from engine import analyze, AnalysisParams
  result = analyze("game.mp4", AnalysisParams(), out_dir="output/job1")
"""
from .config import AnalysisParams, CHANNELS, CHANNEL_LABELS_KO, CHANNEL_GROUP
from .pipeline import analyze
from .models import (AnalysisResult, Timeline, ChannelStat, Highlight,
                     HighlightExplanation, AnalyzeRequest, JobStatus, ProgressEvent)

__all__ = [
    "AnalysisParams", "CHANNELS", "CHANNEL_LABELS_KO", "CHANNEL_GROUP",
    "analyze",
    "AnalysisResult", "Timeline", "ChannelStat", "Highlight",
    "HighlightExplanation", "AnalyzeRequest", "JobStatus", "ProgressEvent",
]

__version__ = "0.1.0"

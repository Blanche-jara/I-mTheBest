"""
전체 파이프라인 오케스트레이션.

  probe → 영상 채널 → 오디오 채널 → 공통 시간축 정렬
        → running_surprise(채널별 자기정보) → 융합/검출 → 클립·썸네일
        → AnalysisResult(모델) 반환

진행률 콜백 progress(fraction:0~1, stage:str) 으로 GUI 에 실시간 보고한다.
"""
from __future__ import annotations

import os
from typing import Callable, Optional
import numpy as np

from .config import AnalysisParams, CHANNELS, CHANNEL_LABELS_KO
from .infotheory import running_surprise
from . import video_channel, audio_channel, fusion, clipper
from .models import (AnalysisResult, Timeline, ChannelStat, Highlight,
                     HighlightExplanation)

ProgressCB = Optional[Callable[[float, str], None]]


def _round(arr, nd=4) -> list[float]:
    return [round(float(x), nd) for x in np.asarray(arr).ravel()]


def _summary_ko(contribs: dict, total_bits: float) -> tuple[str, str, str]:
    """주도 채널과 한 줄 설명 생성."""
    items = sorted(contribs.items(), key=lambda kv: kv[1], reverse=True)
    dom, _ = items[0]
    dom_label = CHANNEL_LABELS_KO[dom]
    top2 = "·".join(CHANNEL_LABELS_KO[k] for k, v in items[:2] if v > 0)
    summary = (f"{dom_label} 채널이 주도하여 약 {total_bits:.1f} bits 의 정보량(놀라움)이 "
               f"관측된 구간 (기여 상위: {top2}).")
    return dom, dom_label, summary


def analyze(video_path: str, params: AnalysisParams, out_dir: str,
            progress: ProgressCB = None) -> AnalysisResult:
    def report(frac, stage):
        if progress:
            progress(float(np.clip(frac, 0.0, 1.0)), stage)

    report(0.01, "영상 정보 확인")
    probe_dur = clipper.ffprobe_duration(video_path)

    # ---- 1) 영상 채널 ----
    vid = video_channel.analyze_video(video_path, params, progress=report,
                                      progress_range=(0.03, 0.55))
    t = vid["t"]
    if t.size < 3:
        raise RuntimeError("분석할 프레임이 충분하지 않습니다(영상이 너무 짧거나 손상).")
    duration = probe_dur or vid["duration_sec"]

    # ---- 2) 오디오 채널 ----
    aud = audio_channel.analyze_audio(video_path, params, progress=report,
                                      progress_range=(0.55, 0.78),
                                      total_duration=duration)

    # ---- 3) 공통 시간축(영상 t)으로 오디오 정렬 ----
    report(0.80, "채널 정렬")
    def _interp(src_t, src_v):
        if src_t.size == 0:
            return np.zeros_like(t)
        return np.interp(t, src_t, src_v, left=src_v[0], right=src_v[-1])

    raw = {
        "frame_entropy": vid["frame_entropy"],
        "motion": vid["motion"],
        "spectral": _interp(aud["t"], aud["spectral"]),
        "loudness": _interp(aud["t"], aud["loudness"]),
        "cheer": _interp(aud["t"], aud["cheer"]),
    }

    # ---- 4) 채널별 surprise(자기정보, bits) ----
    report(0.83, "surprise(자기정보) 계산")
    win = max(4, int(params.surprise_window_sec * params.analysis_fps))
    surprise = {k: running_surprise(v, win=win, bins=params.surprise_bins)
                for k, v in raw.items()}

    # ---- 5) 융합 + 하이라이트 검출 ----
    report(0.87, "멀티모달 융합 · 하이라이트 검출")
    fr = fusion.fuse_and_detect(t, surprise, params)

    # ---- 6) 클립 / 썸네일 ----
    clips_dir = os.path.join(out_dir, "clips")
    thumbs_dir = os.path.join(out_dir, "thumbs")
    os.makedirs(clips_dir, exist_ok=True)
    os.makedirs(thumbs_dir, exist_ok=True)

    highlights = []
    hl_list = fr["highlights"]
    for i, h in enumerate(hl_list):
        report(0.90 + 0.09 * (i / max(1, len(hl_list))),
               f"하이라이트 클립 생성 {i + 1}/{len(hl_list)}")
        hid = f"hl_{i + 1:03d}"
        clip_path = os.path.join(clips_dir, f"{hid}.mp4")
        thumb_path = os.path.join(thumbs_dir, f"{hid}.jpg")
        ok = clipper.cut_clip(video_path, h["start_sec"], h["end_sec"], clip_path,
                              reencode=params.reencode_clips)
        thumb_ok = (params.thumbnail and
                    clipper.make_thumbnail(video_path, h["peak_sec"], thumb_path))
        dom, dom_label, summary = _summary_ko(h["contributions"], h["total_bits"])
        highlights.append(Highlight(
            id=hid, rank=int(h["rank"]),
            start_sec=h["start_sec"], end_sec=h["end_sec"], peak_sec=h["peak_sec"],
            score=h["total_bits"],
            explanation=HighlightExplanation(
                total_bits=h["total_bits"],
                contributions={k: round(float(v), 3) for k, v in h["contributions"].items()},
                dominant_channel=dom, dominant_label_ko=dom_label, summary_ko=summary,
            ),
            clip_path=clip_path if ok else None,
            thumbnail_path=thumb_path if thumb_ok else None,
        ))

    # ---- 7) 결과 모델 ----
    timeline = Timeline(
        t=_round(t, 3),
        frame_entropy=_round(surprise["frame_entropy"]),
        motion=_round(surprise["motion"]),
        spectral=_round(surprise["spectral"]),
        cheer=_round(surprise["cheer"]),
        loudness=_round(surprise["loudness"]),
        fused=_round(fr["fused"]),
    )
    channels = [ChannelStat(**c) for c in fr["channels"]]

    report(1.0, "완료")
    return AnalysisResult(
        video_path=video_path,
        duration_sec=float(duration),
        analysis_fps=float(params.analysis_fps),
        frame_size=vid["frame_size"],
        timeline=timeline,
        channels=channels,
        highlights=highlights,
        params=params.to_dict(),
        mi_matrix=fr["mi_matrix"],
    )

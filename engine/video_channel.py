"""
영상 채널 — 프레임에서 두 가지 raw 특징 시계열을 뽑는다.

  1) frame_entropy : 프레임 픽셀 강도 분포의 Shannon 엔트로피 (공간 복잡도, bits)
  2) motion        : 연속 프레임 간 dense optical flow(Farneback) 의
                     magnitude 분포 엔트로피 = "motion entropy"

두 raw 신호는 pipeline 단계에서 running_surprise() 로 bits 단위 surprise 로 변환된다.
여기서는 "원재료"만 만든다.

긴 영상 대응: 원본을 모두 보지 않고 analysis_fps 로 샘플링하고
downscale_width 로 줄여서 계산량을 고정한다(메모리 상수, 처리량 일정).
"""
from __future__ import annotations

from typing import Callable, Optional
import numpy as np

try:
    import cv2
except Exception as e:  # pragma: no cover
    cv2 = None
    _IMPORT_ERR = e

from .config import AnalysisParams
from .infotheory import image_entropy, distribution_entropy

ProgressCB = Optional[Callable[[float, str], None]]


def _resize_keep_ratio(frame, width: int):
    h, w = frame.shape[:2]
    if w <= width:
        return frame
    nh = max(1, int(round(h * width / w)))
    return cv2.resize(frame, (width, nh), interpolation=cv2.INTER_AREA)


def analyze_video(path: str, params: AnalysisParams,
                  progress: ProgressCB = None,
                  progress_range: tuple[float, float] = (0.0, 1.0)) -> dict:
    """
    반환:
      {
        't': np.ndarray (샘플 시각, 초),
        'frame_entropy': np.ndarray (raw bits),
        'motion': np.ndarray (raw motion entropy),
        'duration_sec': float,
        'src_fps': float,
        'frame_size': [w, h],
      }
    """
    if cv2 is None:
        raise RuntimeError(f"opencv-python(cv2) 가 필요합니다: {_IMPORT_ERR}")

    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        raise RuntimeError(f"영상을 열 수 없습니다: {path}")

    src_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    if src_fps <= 0 or not np.isfinite(src_fps):
        src_fps = 30.0
    n_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    duration = (n_frames / src_fps) if n_frames > 0 else 0.0

    step = max(1, int(round(src_fps / max(0.1, params.analysis_fps))))
    flow_w = params.flow_downscale or params.downscale_width

    times: list[float] = []
    fe: list[float] = []        # frame entropy (raw)
    mo: list[float] = []        # motion entropy (raw)

    prev_small = None
    out_w = out_h = 0
    p0, p1 = progress_range
    idx = 0
    processed = 0

    while True:
        grabbed = cap.grab()                      # 디코드만, 변환 생략 → 빠른 스킵
        if not grabbed:
            break
        if idx % step == 0:
            ok, frame = cap.retrieve()
            if not ok or frame is None:
                idx += 1
                continue
            t = idx / src_fps
            small = _resize_keep_ratio(frame, flow_w)
            gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
            out_h, out_w = gray.shape[:2]

            times.append(t)
            fe.append(image_entropy(gray))

            if prev_small is None:
                mo.append(0.0)
            else:
                flow = cv2.calcOpticalFlowFarneback(
                    prev_small, gray, None,
                    pyr_scale=0.5, levels=3, winsize=15,
                    iterations=3, poly_n=5, poly_sigma=1.2, flags=0,
                )
                mag, _ = cv2.cartToPolar(flow[..., 0], flow[..., 1])
                # 움직임 크기 분포의 엔트로피 = motion entropy.
                # 정지/단조로운 팬 → 낮음, 혼란스러운 교전 → 높음.
                m_ent = distribution_entropy(mag.ravel(), bins=params.surprise_bins,
                                             value_range=(0.0, float(max(1.0, mag.max()))))
                # 평균 크기로 스케일을 살짝 결합(완전 정지 구간을 0 근처로).
                mo.append(float(m_ent * np.tanh(mag.mean())))
            prev_small = gray
            processed += 1

            if progress and (processed % 25 == 0) and n_frames > 0:
                frac = idx / max(1, n_frames)
                progress(p0 + (p1 - p0) * frac, f"영상 분석 {idx}/{n_frames} 프레임")
        idx += 1

    cap.release()

    if duration <= 0.0 and times:
        duration = times[-1] + step / src_fps

    if progress:
        progress(p1, "영상 분석 완료")

    return {
        "t": np.asarray(times, dtype=np.float64),
        "frame_entropy": np.asarray(fe, dtype=np.float64),
        "motion": np.asarray(mo, dtype=np.float64),
        "duration_sec": float(duration),
        "src_fps": float(src_fps),
        "frame_size": [int(out_w), int(out_h)],
    }

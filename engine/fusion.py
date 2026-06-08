"""
멀티모달 융합 + 하이라이트 검출.

입력: 공통 시간축 t 위에 정렬된 5개 채널의 surprise 시계열(모두 bits = -log2 p).
      (frame_entropy, motion, spectral, cheer, loudness)

핵심 아이디어 (maximum entropy principle):
  - 라벨이 없을 때 가장 편향 없는 채널 결합은 균등 가중(uniform prior).
  - 단, 채널들이 서로 상호정보량(MI)이 크면 "중복(redundancy)"이므로 증거를
    이중계산하게 된다. 이를 최대엔트로피/파시모니 관점에서 보정해
    중복이 큰 채널의 가중치를 낮춘다:   w_i ∝ (1 - 평균 NMI_i) · liveness_i.
  - 결과 fused(t) = Σ w_i · s_i(t) 는 채널 선택 prior w 하의 기대 자기정보로,
    여전히 bits 단위이며 "이 순간의 총 놀라움"으로 해석된다.

설명가능성: 각 하이라이트 구간에서 fused 를 적분한 값이 점수(정보량)이고,
            채널별 적분 기여가 "왜 뽑혔는가"를 bits 로 분해해준다.
"""
from __future__ import annotations

import numpy as np
from scipy.signal import find_peaks

from .config import AnalysisParams, CHANNELS, CHANNEL_LABELS_KO, CHANNEL_GROUP
from .infotheory import normalized_mutual_information, mutual_information


def _percentile_scale(series: dict[str, np.ndarray]) -> dict[str, np.ndarray]:
    """
    채널별 신뢰도 정규화: 각 채널의 95퍼센타일을 공통 기준에 맞춰
    스케일만 완만히 보정한다(bits 해석은 유지, 단일 채널의 스케일 독점 방지).
    """
    p95 = {}
    for k, v in series.items():
        nz = v[v > 0]
        p95[k] = float(np.percentile(nz, 95)) if nz.size else 0.0
    live = [v for v in p95.values() if v > 1e-9]
    ref = float(np.median(live)) if live else 1.0
    out = {}
    for k, v in series.items():
        if p95[k] < 1e-9:
            out[k] = v.copy()
        else:
            scale = float(np.clip(ref / p95[k], 0.25, 4.0))
            out[k] = v * scale
    return out


def _auto_weights(series: dict[str, np.ndarray]) -> dict[str, float]:
    """MI 기반 최대엔트로피 가중치. 중복 큰 채널 down-weight, 죽은 채널 ~0."""
    keys = list(series.keys())
    n = len(keys)
    # 평균 정규화 상호정보량(자기 제외)
    avg_nmi = {}
    for i, ki in enumerate(keys):
        vals = []
        for j, kj in enumerate(keys):
            if i == j:
                continue
            vals.append(normalized_mutual_information(series[ki], series[kj]))
        avg_nmi[ki] = float(np.mean(vals)) if vals else 0.0
    # liveness = 채널이 살아있는 정도(표준편차 기반 0~1)
    raw = {}
    for k in keys:
        v = series[k]
        live = 1.0 if (v.size and v.std() > 1e-6) else 0.0
        raw[k] = max(0.0, (1.0 - avg_nmi[k])) * live
    total = sum(raw.values())
    if total < 1e-9:
        return {k: 1.0 / n for k in keys}
    return {k: raw[k] / total for k in keys}


def _resolve_weights(series: dict[str, np.ndarray], params: AnalysisParams) -> dict[str, float]:
    manual = {
        "frame_entropy": params.weight_frame_entropy,
        "motion": params.weight_motion,
        "spectral": params.weight_spectral,
        "cheer": params.weight_cheer,
        "loudness": params.weight_loudness,
    }
    if all(v is not None for v in manual.values()):
        total = sum(manual.values()) or 1.0
        return {k: float(v) / total for k, v in manual.items()}
    auto = _auto_weights(series)
    # 일부만 수동 지정 시: 지정된 값은 존중하고 나머지를 auto 비율로 채움
    for k, v in manual.items():
        if v is not None:
            auto[k] = float(v)
    total = sum(auto.values()) or 1.0
    return {k: v / total for k, v in auto.items()}


def fuse_and_detect(t: np.ndarray, surprise: dict[str, np.ndarray],
                    params: AnalysisParams) -> dict:
    """
    surprise: {channel_name: np.ndarray(bits)} — 모두 t 와 길이 동일.
    반환 dict: fused, weights, channels(stat), highlights, mi_matrix
    """
    t = np.asarray(t, dtype=np.float64)
    n = t.size
    channels = {k: np.asarray(surprise.get(k, np.zeros(n)), dtype=np.float64)[:n] for k in CHANNELS}
    for k in channels:  # 길이 보정
        if channels[k].size < n:
            channels[k] = np.pad(channels[k], (0, n - channels[k].size))

    scaled = _percentile_scale(channels)
    weights = _resolve_weights(channels, params)

    fused = np.zeros(n, dtype=np.float64)
    weighted = {}
    for k in CHANNELS:
        weighted[k] = weights[k] * scaled[k]
        fused += weighted[k]

    # ---- 하이라이트 검출 ----
    dt = float(np.median(np.diff(t))) if n > 1 else (1.0 / max(0.1, params.analysis_fps))
    fps = 1.0 / max(1e-6, dt)
    highlights = []
    if n >= 3 and fused.std() > 1e-9:
        thr = float(fused.mean() + params.peak_z * fused.std())
        distance = max(1, int(params.min_gap_sec * fps))
        peaks, props = find_peaks(fused, height=thr, distance=distance,
                                  prominence=float(fused.std() * 0.5))
        # 점수(구간 적분) 기준 정렬 후 top_k
        cand = []
        for pk in peaks:
            s_idx, e_idx = _expand_segment(fused, pk, thr, params, fps, n)
            seg = slice(s_idx, e_idx + 1)
            seg_t = t[seg]
            total_bits = float(np.trapezoid(fused[seg], seg_t)) if seg_t.size > 1 else float(fused[pk])
            contribs = {}
            for k in CHANNELS:
                contribs[k] = (float(np.trapezoid(weighted[k][seg], seg_t))
                               if seg_t.size > 1 else float(weighted[k][pk]))
            cand.append({
                "peak_idx": int(pk),
                "start_sec": float(t[s_idx]),
                "end_sec": float(t[e_idx]),
                "peak_sec": float(t[pk]),
                "total_bits": total_bits,
                "contributions": contribs,
            })
        cand.sort(key=lambda c: c["total_bits"], reverse=True)
        cand = cand[: params.top_k]
        cand.sort(key=lambda c: c["start_sec"])
        for rank0, c in enumerate(sorted(cand, key=lambda x: x["total_bits"], reverse=True)):
            c["rank"] = rank0 + 1
        cand.sort(key=lambda c: c["start_sec"])
        highlights = cand

    # ---- 채널 통계 & MI 행렬 ----
    ch_stats = []
    for k in CHANNELS:
        v = channels[k]
        ch_stats.append({
            "name": k,
            "label_ko": CHANNEL_LABELS_KO[k],
            "group": CHANNEL_GROUP[k],
            "weight": float(weights[k]),
            "mean_bits": float(v.mean()) if v.size else 0.0,
            "peak_bits": float(v.max()) if v.size else 0.0,
            "mi_with_fused": float(mutual_information(v, fused)),
        })

    mi_matrix = {}
    for ki in CHANNELS:
        mi_matrix[ki] = {kj: float(normalized_mutual_information(channels[ki], channels[kj]))
                         for kj in CHANNELS}

    return {
        "fused": fused,
        "weights": weights,
        "channels": ch_stats,
        "highlights": highlights,
        "mi_matrix": mi_matrix,
    }


def _expand_segment(fused: np.ndarray, pk: int, thr: float,
                    params: AnalysisParams, fps: float, n: int) -> tuple[int, int]:
    """피크에서 좌우로 임계값 위 구간을 확장하고 길이/패딩을 제약."""
    floor = max(thr * 0.6, fused.mean())
    s, e = pk, pk
    while s > 0 and fused[s - 1] > floor:
        s -= 1
    while e < n - 1 and fused[e + 1] > floor:
        e += 1
    pad = int(params.clip_pad_sec * fps)
    s = max(0, s - pad)
    e = min(n - 1, e + pad)
    # 최소/최대 길이 제약
    min_len = int(params.min_clip_sec * fps)
    max_len = int(params.max_clip_sec * fps)
    if e - s < min_len:
        grow = (min_len - (e - s)) // 2 + 1
        s = max(0, s - grow)
        e = min(n - 1, e + grow)
    if e - s > max_len:
        half = max_len // 2
        s = max(0, pk - half)
        e = min(n - 1, pk + half)
    return s, e

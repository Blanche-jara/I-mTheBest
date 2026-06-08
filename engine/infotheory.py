"""
정보이론 핵심 연산 (순수 numpy/scipy — 무거운 의존성 없음).

이 모듈이 프로젝트의 이론적 심장이다. 모든 "놀라움(surprise)"은
Shannon 의 자기정보(self-information)  I(x) = -log2 p(x)  [bits] 로 정의되며,
채널 융합과 설명가능성은 엔트로피·상호정보량(mutual information)으로 정량화된다.

핵심 함수
  shannon_entropy   : H(X) = -Σ p log2 p
  self_information   : I(x) = -log2 p(x)
  image_entropy      : 한 프레임의 픽셀 강도 분포 엔트로피(공간 복잡도, 0~8 bits)
  running_surprise   : 시계열에서 "최근 과거 분포 대비 현재 값의 자기정보"
  mutual_information : I(X;Y) = Σ p(x,y) log2 [ p(x,y) / (p(x)p(y)) ]
"""
from __future__ import annotations

import numpy as np

_EPS = 1e-12


def shannon_entropy(probs: np.ndarray, base: float = 2.0) -> float:
    """확률분포 probs 의 Shannon 엔트로피 H(X) = -Σ p log p."""
    p = np.asarray(probs, dtype=np.float64)
    p = p[p > 0]
    if p.size == 0:
        return 0.0
    p = p / p.sum()
    return float(-np.sum(p * (np.log(p) / np.log(base))))


def self_information(p: float | np.ndarray, base: float = 2.0) -> float | np.ndarray:
    """자기정보 I(x) = -log_base p(x). p 가 작을수록(드물수록) 값이 크다 = 놀라움."""
    p = np.clip(np.asarray(p, dtype=np.float64), _EPS, 1.0)
    out = -np.log(p) / np.log(base)
    return float(out) if np.ndim(out) == 0 else out


def histogram_probs(x: np.ndarray, bins: int, value_range: tuple[float, float] | None = None,
                    smooth: float = 1.0) -> np.ndarray:
    """x 를 히스토그램으로 만들어 라플라스 평활(smooth) 후 확률분포로 반환."""
    x = np.asarray(x, dtype=np.float64).ravel()
    if x.size == 0:
        return np.full(bins, 1.0 / bins)
    counts, _ = np.histogram(x, bins=bins, range=value_range)
    counts = counts.astype(np.float64) + smooth
    return counts / counts.sum()


def image_entropy(gray: np.ndarray) -> float:
    """
    8-bit 그레이스케일 프레임의 강도 히스토그램 엔트로피(bits, 0~8).
    화면이 단조로우면 낮고(예: 로딩 화면), 복잡/혼란스러우면 높다(교전·폭발).
    """
    g = np.asarray(gray).ravel()
    counts = np.bincount(g.astype(np.uint8), minlength=256).astype(np.float64)
    total = counts.sum()
    if total <= 0:
        return 0.0
    p = counts / total
    return shannon_entropy(p)


def distribution_entropy(values: np.ndarray, bins: int = 32,
                         value_range: tuple[float, float] | None = None) -> float:
    """연속값 배열을 히스토그램으로 본 분포 엔트로피(bits). 옵티컬 플로우 magnitude 등에 사용."""
    p = histogram_probs(values, bins=bins, value_range=value_range, smooth=0.0)
    return shannon_entropy(p)


def running_surprise(series: np.ndarray, win: int, bins: int = 32) -> np.ndarray:
    """
    시계열의 각 시점 surprise(자기정보, bits) 를 계산한다.

    아이디어: 시점 i 의 값이 "직전 win 개 샘플이 그리는 분포"에서 얼마나
    드문가? p_hat(현재 빈) 을 라플라스 평활로 추정하고  -log2 p_hat  을 반환.
    급변(드문 값)일수록 큰 bits → 그 순간이 놀랍다.

    이것이 −log p 로 정의되는 surprise 의 직접 구현이며, 모든 채널에 공통 적용된다.
    """
    s = np.asarray(series, dtype=np.float64).ravel()
    n = s.size
    out = np.zeros(n, dtype=np.float64)
    if n == 0:
        return out
    lo, hi = float(np.nanmin(s)), float(np.nanmax(s))
    if not np.isfinite(lo) or not np.isfinite(hi) or hi - lo < _EPS:
        return out  # 변화가 없으면 surprise 0
    edges = np.linspace(lo, hi, bins + 1)
    win = max(4, int(win))
    for i in range(n):
        a = max(0, i - win)
        hist = s[a:i]
        if hist.size < 4:
            continue
        counts, _ = np.histogram(hist, bins=edges)
        counts = counts.astype(np.float64) + 1.0          # 라플라스 평활
        probs = counts / counts.sum()
        b = int(np.clip(np.searchsorted(edges, s[i], side="right") - 1, 0, bins - 1))
        out[i] = self_information(probs[b])
    return out


def mutual_information(x: np.ndarray, y: np.ndarray, bins: int = 24) -> float:
    """
    두 연속 시계열의 상호정보량 I(X;Y) [bits].
    2D 히스토그램으로 결합분포를 추정한 뒤
        I = Σ p(x,y) log2 [ p(x,y) / (p(x) p(y)) ]  = H(X)+H(Y)-H(X,Y).
    채널 간 중복(redundancy)·시너지를 측정해 융합 가중치와 설명에 쓴다.
    """
    x = np.asarray(x, dtype=np.float64).ravel()
    y = np.asarray(y, dtype=np.float64).ravel()
    n = min(x.size, y.size)
    if n < 8:
        return 0.0
    x, y = x[:n], y[:n]
    if x.std() < _EPS or y.std() < _EPS:
        return 0.0
    c_xy, _, _ = np.histogram2d(x, y, bins=bins)
    p_xy = c_xy / c_xy.sum()
    p_x = p_xy.sum(axis=1, keepdims=True)
    p_y = p_xy.sum(axis=0, keepdims=True)
    denom = p_x * p_y
    mask = (p_xy > 0) & (denom > 0)
    mi = np.sum(p_xy[mask] * np.log2(p_xy[mask] / denom[mask]))
    return float(max(0.0, mi))


def normalized_mutual_information(x: np.ndarray, y: np.ndarray, bins: int = 24) -> float:
    """0~1 정규화 상호정보량 (시각화/행렬 표시용)."""
    mi = mutual_information(x, y, bins=bins)
    hx = distribution_entropy(x, bins=bins)
    hy = distribution_entropy(y, bins=bins)
    denom = max(hx, hy, _EPS)
    return float(np.clip(mi / denom, 0.0, 1.0))


def robust_minmax(x: np.ndarray, lo_pct: float = 1.0, hi_pct: float = 99.0) -> np.ndarray:
    """이상치에 강한 0~1 정규화(시각화·가중합 안정화용)."""
    x = np.asarray(x, dtype=np.float64)
    if x.size == 0:
        return x
    lo = np.percentile(x, lo_pct)
    hi = np.percentile(x, hi_pct)
    if hi - lo < _EPS:
        return np.zeros_like(x)
    return np.clip((x - lo) / (hi - lo), 0.0, 1.0)

"""fusion(융합·검출) 단위테스트 — 합성 신호로 하이라이트가 잡히는지 확인."""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from engine.config import AnalysisParams, CHANNELS  # noqa: E402
from engine.fusion import fuse_and_detect  # noqa: E402


def _synthetic():
    """600 샘플(=3fps 200초), motion 채널 한 곳에 큰 surprise 스파이크."""
    n = 600
    fps = 3.0
    t = np.arange(n) / fps
    rng = np.random.default_rng(7)
    surprise = {k: np.abs(rng.normal(0.2, 0.05, size=n)) for k in CHANNELS}
    # 100초(=index 300) 부근에 motion 큰 봉우리
    peak = 300
    bump = np.exp(-((np.arange(n) - peak) ** 2) / (2 * 6 ** 2)) * 4.0
    surprise["motion"] = surprise["motion"] + bump
    surprise["loudness"] = surprise["loudness"] + bump * 0.5
    return t, surprise, peak / fps


def test_detects_highlight_at_spike():
    t, surprise, peak_sec = _synthetic()
    params = AnalysisParams(analysis_fps=3.0, top_k=5, min_gap_sec=5.0)
    out = fuse_and_detect(t, surprise, params)
    assert len(out["highlights"]) >= 1
    # 가장 큰 점수 하이라이트가 스파이크 근처(±5초)에 있어야 한다
    best = max(out["highlights"], key=lambda h: h["total_bits"])
    assert abs(best["peak_sec"] - peak_sec) < 5.0
    # 주도 채널이 motion 이어야 한다
    dom = max(best["contributions"].items(), key=lambda kv: kv[1])[0]
    assert dom == "motion"


def test_weights_sum_to_one():
    t, surprise, _ = _synthetic()
    out = fuse_and_detect(t, surprise, AnalysisParams())
    assert abs(sum(out["weights"].values()) - 1.0) < 1e-6


def test_mi_matrix_shape():
    t, surprise, _ = _synthetic()
    out = fuse_and_detect(t, surprise, AnalysisParams())
    assert set(out["mi_matrix"].keys()) == set(CHANNELS)
    for k in CHANNELS:
        assert abs(out["mi_matrix"][k][k] - 1.0) < 0.2  # 자기 자신과 NMI≈1


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"PASS {name}")
    print("모든 fusion 테스트 통과")

"""infotheory 핵심 함수 단위테스트 (순수 numpy — 무거운 의존성 불필요)."""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from engine.infotheory import (  # noqa: E402
    shannon_entropy, self_information, image_entropy,
    running_surprise, mutual_information, normalized_mutual_information,
)


def test_self_information_bits():
    assert abs(self_information(0.5) - 1.0) < 1e-9      # 동전 1개 = 1 bit
    assert abs(self_information(0.25) - 2.0) < 1e-9     # 1/4 = 2 bits
    assert self_information(1.0) == 0.0                 # 확실한 사건 = 0 bit


def test_shannon_entropy_bounds():
    assert abs(shannon_entropy([0.5, 0.5]) - 1.0) < 1e-9
    assert abs(shannon_entropy([1.0, 0.0]) - 0.0) < 1e-9
    # 균등분포 N개 → log2 N
    assert abs(shannon_entropy(np.ones(8) / 8) - 3.0) < 1e-9


def test_image_entropy_extremes():
    flat = np.zeros((64, 64), dtype=np.uint8)
    assert image_entropy(flat) == 0.0                  # 단색 → 0 bit
    # 0~255 균등 → 8 bit 근처
    ramp = np.tile(np.arange(256, dtype=np.uint8), (64, 1))
    assert image_entropy(ramp) > 7.5


def test_running_surprise_spike():
    rng = np.random.default_rng(0)
    s = rng.normal(0, 0.01, size=400)
    s[200] = 5.0                                       # 급격한 이상치
    sur = running_surprise(s, win=40, bins=16)
    assert sur[200] > sur[:150].mean() + 1.0           # 스파이크에서 surprise 큼


def test_mutual_information():
    rng = np.random.default_rng(1)
    x = rng.normal(size=2000)
    y_same = x.copy()
    y_indep = rng.normal(size=2000)
    assert mutual_information(x, y_same) > mutual_information(x, y_indep)
    assert 0.0 <= normalized_mutual_information(x, y_indep) < 0.3


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"PASS {name}")
    print("모든 infotheory 테스트 통과")

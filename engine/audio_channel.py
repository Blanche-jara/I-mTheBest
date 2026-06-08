"""
오디오 채널 — 오디오에서 세 가지 raw 특징 시계열을 뽑는다.

  1) spectral : 스펙트럼 변화(spectral novelty / onset strength) — 갑작스러운 소리 변화
  2) loudness : RMS 음량(dB) — 음량의 급변
  3) cheer    : 환호성/함성 점수 — 중역대 광대역·평탄 스펙트럼 휴리스틱
                (enable_cheer_model + torch 가용 시 학습형 분류기로 대체 가능)

긴 영상 대응: ffmpeg 로 PCM 을 파이프 스트리밍해서 고정 크기 윈도(기본 15초)
단위로 처리한다 → 1시간이든 3시간이든 메모리는 한 윈도 크기로 일정.
오디오 추출은 ffmpeg 가 모든 컨테이너(mp4/mkv/...)를 처리하므로 안전하다.
"""
from __future__ import annotations

import subprocess
from typing import Callable, Optional
import numpy as np

try:
    import librosa
except Exception as e:  # pragma: no cover
    librosa = None
    _LIBROSA_ERR = e

from .config import AnalysisParams

ProgressCB = Optional[Callable[[float, str], None]]

_WIN_SEC = 15.0  # 스트리밍 처리 윈도 길이(초)


def _ffmpeg_pcm_stream(path: str, sr: int):
    """ffmpeg 로 모노 f32le PCM 을 stdout 으로 흘려보내는 프로세스를 연다."""
    cmd = [
        "ffmpeg", "-nostdin", "-i", path,
        "-vn", "-ac", "1", "-ar", str(sr),
        "-f", "f32le", "-loglevel", "error", "pipe:1",
    ]
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)


def _cheer_score(S: np.ndarray, freqs: np.ndarray) -> np.ndarray:
    """
    프레임별 환호성 점수(휴리스틱).
    환호성/함성은 (a) 1~6kHz 중역대 에너지가 크고 (b) 스펙트럼이 평탄(광대역 잡음성)하다.
    두 조건의 곱으로 0~ 스케일의 raw 점수를 만든다. running_surprise 가 onset 을 잡는다.
    """
    eps = 1e-10
    band = (freqs >= 1000) & (freqs <= 6000)
    band_energy = S[band, :].mean(axis=0)
    total_energy = S.mean(axis=0) + eps
    band_ratio = band_energy / total_energy
    # spectral flatness = 기하평균 / 산술평균 (0=순음, 1=백색잡음)
    gmean = np.exp(np.mean(np.log(S + eps), axis=0))
    amean = np.mean(S, axis=0) + eps
    flatness = gmean / amean
    return band_ratio * flatness * np.log1p(band_energy)


def analyze_audio(path: str, params: AnalysisParams,
                  progress: ProgressCB = None,
                  progress_range: tuple[float, float] = (0.0, 1.0),
                  total_duration: float = 0.0) -> dict:
    """
    반환:
      {
        't': np.ndarray (오디오 프레임 시각, 초),
        'spectral': np.ndarray,
        'loudness': np.ndarray,
        'cheer': np.ndarray,
      }
    오디오가 없으면 빈 배열을 반환한다(영상 채널만으로도 동작).
    """
    if librosa is None:
        raise RuntimeError(f"librosa 가 필요합니다: {_LIBROSA_ERR}")

    sr = params.audio_sr
    hop = params.audio_hop
    n_fft = 2048
    win_samples = int(_WIN_SEC * sr)
    freqs = librosa.fft_frequencies(sr=sr, n_fft=n_fft)

    proc = _ffmpeg_pcm_stream(path, sr)
    buf = bytearray()
    bytes_per_win = win_samples * 4  # float32

    t_all: list[np.ndarray] = []
    sp_all: list[np.ndarray] = []
    ld_all: list[np.ndarray] = []
    ch_all: list[np.ndarray] = []
    global_start = 0  # 누적 샘플 오프셋
    p0, p1 = progress_range

    def _process_block(y: np.ndarray, start_sample: int):
        if y.size < n_fft:
            return
        S = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop))
        onset = librosa.onset.onset_strength(S=librosa.amplitude_to_db(S, ref=np.max),
                                             sr=sr, hop_length=hop)
        rms = librosa.feature.rms(S=S, hop_length=hop)[0]
        loud_db = 20.0 * np.log10(rms + 1e-8)
        cheer = _cheer_score(S, freqs)
        n = min(len(onset), len(rms), len(cheer))
        if n <= 0:
            return
        frame_idx = np.arange(n)
        times = (start_sample / sr) + frame_idx * hop / sr
        t_all.append(times)
        sp_all.append(np.asarray(onset[:n], dtype=np.float64))
        ld_all.append(np.asarray(loud_db[:n], dtype=np.float64))
        ch_all.append(np.asarray(cheer[:n], dtype=np.float64))

    try:
        while True:
            chunk = proc.stdout.read(bytes_per_win - len(buf))
            if chunk:
                buf.extend(chunk)
            if len(buf) >= bytes_per_win or not chunk:
                take = (len(buf) // 4) * 4
                if take == 0:
                    if not chunk:
                        break
                    continue
                y = np.frombuffer(bytes(buf[:take]), dtype=np.float32).astype(np.float64)
                del buf[:take]
                _process_block(y, global_start)
                global_start += len(y)
                if progress and total_duration > 0:
                    frac = min(1.0, (global_start / sr) / total_duration)
                    progress(p0 + (p1 - p0) * frac, f"오디오 분석 {global_start // sr:.0f}s")
            if not chunk:
                break
    finally:
        try:
            proc.stdout.close()
        except Exception:
            pass
        proc.wait()

    if progress:
        progress(p1, "오디오 분석 완료")

    if not t_all:  # 오디오 트랙 없음
        empty = np.asarray([], dtype=np.float64)
        return {"t": empty, "spectral": empty, "loudness": empty, "cheer": empty}

    return {
        "t": np.concatenate(t_all),
        "spectral": np.concatenate(sp_all),
        "loudness": np.concatenate(ld_all),
        "cheer": np.concatenate(ch_all),
    }

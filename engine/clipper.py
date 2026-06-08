"""
ffmpeg 기반 클립 추출 및 썸네일 생성, 영상 길이 probe.

원본을 다시 디코딩하지 않고 ffmpeg 에 위임하므로 빠르고 컨테이너 독립적이다.
"""
from __future__ import annotations

import json
import os
import subprocess


def ffprobe_duration(path: str) -> float:
    """ffprobe 로 영상 길이(초)를 얻는다. 실패 시 0.0."""
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "json", path],
            capture_output=True, text=True, check=True,
        )
        return float(json.loads(out.stdout)["format"]["duration"])
    except Exception:
        return 0.0


def cut_clip(src: str, start: float, end: float, out_path: str,
             reencode: bool = True) -> bool:
    """[start, end] 구간을 잘라 out_path 로 저장. 성공 여부 반환."""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    dur = max(0.1, end - start)
    if reencode:
        # 프레임 정확 컷(재인코딩). -ss 를 -i 앞에 두어 빠른 정확 seek.
        cmd = ["ffmpeg", "-y", "-ss", f"{start:.3f}", "-i", src, "-t", f"{dur:.3f}",
               "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
               "-c:a", "aac", "-movflags", "+faststart",
               "-loglevel", "error", out_path]
    else:
        # 빠른 무손실 copy (키프레임 경계로 약간 어긋날 수 있음).
        cmd = ["ffmpeg", "-y", "-ss", f"{start:.3f}", "-i", src, "-t", f"{dur:.3f}",
               "-c", "copy", "-movflags", "+faststart",
               "-loglevel", "error", out_path]
    try:
        subprocess.run(cmd, check=True, capture_output=True)
        return os.path.exists(out_path) and os.path.getsize(out_path) > 0
    except Exception:
        return False


def make_thumbnail(src: str, time_sec: float, out_path: str, width: int = 480) -> bool:
    """time_sec 시점의 프레임 1장을 jpg 썸네일로 저장."""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    cmd = ["ffmpeg", "-y", "-ss", f"{time_sec:.3f}", "-i", src,
           "-frames:v", "1", "-vf", f"scale={width}:-1", "-q:v", "3",
           "-loglevel", "error", out_path]
    try:
        subprocess.run(cmd, check=True, capture_output=True)
        return os.path.exists(out_path)
    except Exception:
        return False

"""
CLI 실행기 — 서버/GUI 없이 단독으로 영상 하이라이트를 추출한다.

사용 예:
  python -m engine.cli game.mp4 -o output/game1 --fps 3 --top-k 10
  python -m engine.cli game.mp4 --no-reencode          # 빠른 copy 컷
결과:
  <out>/result.json , <out>/clips/*.mp4 , <out>/thumbs/*.jpg
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

from .config import AnalysisParams
from .pipeline import analyze


def _progress_printer():
    last = [0.0]
    def cb(frac, stage):
        # 한 줄 진행바
        bar = "█" * int(frac * 30)
        bar = bar.ljust(30, "·")
        sys.stdout.write(f"\r[{bar}] {frac * 100:5.1f}%  {stage[:42]:42}")
        sys.stdout.flush()
        last[0] = frac
    return cb


def main(argv=None):
    ap = argparse.ArgumentParser(description="게임 영상 자동 하이라이트 추출 (정보이론 기반)")
    ap.add_argument("video", help="입력 영상 경로")
    ap.add_argument("-o", "--out", default=None, help="출력 폴더 (기본: output/<영상이름>)")
    ap.add_argument("--fps", type=float, default=None, help="분석 프레임/초 (기본 3)")
    ap.add_argument("--width", type=int, default=None, help="분석 다운스케일 가로폭 (기본 256)")
    ap.add_argument("--top-k", type=int, default=None, help="최대 하이라이트 수 (기본 12)")
    ap.add_argument("--min-gap", type=float, default=None, help="하이라이트 간 최소 간격(초)")
    ap.add_argument("--peak-z", type=float, default=None, help="피크 임계 z (기본 1.2)")
    ap.add_argument("--no-reencode", action="store_true", help="재인코딩 없이 빠른 copy 컷")
    ap.add_argument("--no-thumb", action="store_true", help="썸네일 생략")
    args = ap.parse_args(argv)

    if not os.path.exists(args.video):
        print(f"입력 영상을 찾을 수 없습니다: {args.video}", file=sys.stderr)
        return 2

    out = args.out or os.path.join("output", os.path.splitext(os.path.basename(args.video))[0])
    os.makedirs(out, exist_ok=True)

    p = AnalysisParams()
    if args.fps is not None: p.analysis_fps = args.fps
    if args.width is not None: p.downscale_width = args.width
    if args.top_k is not None: p.top_k = args.top_k
    if args.min_gap is not None: p.min_gap_sec = args.min_gap
    if args.peak_z is not None: p.peak_z = args.peak_z
    if args.no_reencode: p.reencode_clips = False
    if args.no_thumb: p.thumbnail = False

    print(f"▶ 분석 시작: {args.video}\n  출력: {out}\n  파라미터: fps={p.analysis_fps}, "
          f"width={p.downscale_width}, top_k={p.top_k}")
    t0 = time.time()
    result = analyze(args.video, p, out_dir=out, progress=_progress_printer())
    dt = time.time() - t0
    print()  # 진행바 줄바꿈

    result_path = os.path.join(out, "result.json")
    with open(result_path, "w", encoding="utf-8") as f:
        f.write(result.model_dump_json(indent=2))

    print(f"\n✓ 완료 ({dt:.1f}s) · 영상 길이 {result.duration_sec:.0f}s · "
          f"하이라이트 {len(result.highlights)}개")
    print(f"  결과 JSON: {result_path}")
    print("\n  순위  시각        길이   정보량(bits)  주도채널        설명")
    print("  " + "-" * 78)
    for h in sorted(result.highlights, key=lambda x: x.rank):
        mm, ss = divmod(int(h.peak_sec), 60)
        length = h.end_sec - h.start_sec
        print(f"  {h.rank:>3}  {mm:02d}:{ss:02d}      {length:4.1f}s   "
              f"{h.score:8.1f}     {h.explanation.dominant_label_ko:8}  "
              f"{os.path.basename(h.clip_path) if h.clip_path else '(클립 실패)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

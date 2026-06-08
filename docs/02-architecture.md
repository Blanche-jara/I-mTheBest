# 시스템 아키텍처 및 데이터 흐름

> 게임 영상 자동 하이라이트 추출 — 정보이론 기반(Shannon self-information / mutual information)
> 본 문서는 실제 소스 코드(`engine/`, `server/`, `app/`)의 함수·파일명에 정확히 대응한다.

---

## 0. 한눈에 보는 핵심

긴 게임 영상에서 "놀라운 순간(surprise)"을 자동으로 골라낸다. 핵심은 머신러닝 분류기가 아니라 **정보이론**이다. 각 채널(영상·오디오)에서 신호의 자기정보

```
I(x) = -log2 p(x)   [bits]
```

를 계산하고, 채널 간 상호정보량(mutual information)으로 중복을 보정해 융합한다. 따라서 각 하이라이트에는 "왜 뽑혔는가"를 **bits 단위 정보량**으로 정량 설명할 수 있다(설명가능성).

---

## 1. 전체 개요 (ASCII 다이어그램)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          Flutter GUI  (app/)                               │
│   영상 선택 · 진행률 표시 · surprise 그래프/대시보드 · 하이라이트 클립 재생   │
└───────────────┬──────────────────────────────────────────▲────────────────┘
                │  REST (분석요청/상태/결과)                  │  WebSocket
                │  HTTP  POST /analyze, GET /jobs/{id} ...   │  WS /ws/{id} (진행률)
                ▼                                            │  + /files (정적 클립)
┌──────────────────────────────────────────────────────────┴────────────────┐
│                      FastAPI 로컬 서버  (server/)                            │
│   app.py : 엔드포인트   |   jobs.py : 백그라운드 스레드로 engine.analyze 구동   │
│   진행률 progress(frac, stage) 콜백을 Job 상태로 누적 → REST/WS 로 노출        │
└───────────────┬────────────────────────────────────────────────────────────┘
                │  analyze(video_path, params, out_dir, progress)
                ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                       Python 엔진  (engine/)                                  │
│                                                                              │
│   pipeline.analyze()  ── 오케스트레이션 ──────────────────────────────────┐   │
│                                                                          │   │
│   ┌─ video_channel.analyze_video ─┐   ┌─ audio_channel.analyze_audio ─┐  │   │
│   │  frame_entropy, motion        │   │  spectral, loudness, cheer    │  │   │
│   │  (OpenCV, 샘플링+다운스케일)    │   │  (ffmpeg PCM 스트림 + librosa)  │  │   │
│   └───────────────┬───────────────┘   └───────────────┬───────────────┘  │   │
│                   └──────── 공통 시간축 t 로 정렬(보간) ─┘                   │   │
│                                    │                                      │   │
│              infotheory.running_surprise()  채널별 -log2 p (bits)          │   │
│                                    │                                      │   │
│              fusion.fuse_and_detect()  MI 가중 융합 + 피크/구간 검출         │   │
│                                    │                                      │   │
│              clipper.cut_clip / make_thumbnail  (ffmpeg 클립·썸네일)        │   │
│                                    │                                      │   │
│              models.AnalysisResult  (pydantic JSON 계약) ─────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
                                     │
                          ffmpeg / ffprobe (외부 바이너리)
```

---

## 2. 3계층 역할

| 계층 | 위치 | 핵심 책임 | 핵심 기술 |
|---|---|---|---|
| **Python 엔진** | `engine/` | 영상·오디오에서 특징 추출 → surprise(자기정보) 계산 → 융합·검출 → 클립/썸네일 생성 → `AnalysisResult` 반환. 서버·GUI 없이 CLI(`engine.cli`)로도 단독 동작. | NumPy, SciPy, OpenCV, librosa, ffmpeg/ffprobe |
| **FastAPI 서버** | `server/` | 엔진을 백그라운드 스레드로 구동하는 작업(Job) 관리자. 분석 요청 접수, 진행률·상태·결과를 REST/WebSocket 으로 노출, 생성된 클립을 정적 파일로 서빙. | FastAPI, uvicorn, pydantic |
| **Flutter GUI** | `app/` | 사용자 진입점. 영상 선택, 진행률 실시간 표시, surprise 시계열 그래프/대시보드, 하이라이트 목록·클립 재생. 서버가 내보내는 JSON 계약을 그대로 소비. | Flutter / Dart |

> 비고: 세 계층 모두 구현 완료. Flutter GUI(`app/lib/`)는 홈/분석/대시보드 화면과 타임라인 차트·MI 행렬·하이라이트 카드·클립 플레이어 위젯으로 구성되며 `flutter analyze` 이슈 0건이다. 엔진·서버 계층은 CLI 및 REST/WS 로 end-to-end 동작이 검증되었다(60초 합성영상 → 하이라이트 클립·썸네일 생성 확인).

설계 원칙: **엔진은 서버/GUI를 모른다.** 엔진의 유일한 외부 접점은 `progress(fraction, stage)` 콜백과 반환되는 `AnalysisResult` 모델이다. 서버는 이 콜백을 Job 상태로 옮겨 적고, GUI는 모델 JSON만 파싱한다. 세 계층은 `engine/models.py` 의 pydantic 모델을 공유 계약으로 삼는다.

---

## 3. 데이터 흐름: 영상 → 채널특징 → surprise → 융합 → 하이라이트 → 클립 → GUI

```
[원본 영상 mp4/mkv]
       │
       ├─(영상)→ analyze_video() ─→ raw 시계열:  frame_entropy, motion        ┐
       │            OpenCV grab/retrieve, 다운스케일, Farneback optical flow   │
       │                                                                       │
       └─(오디오)→ analyze_audio() ─→ raw 시계열: spectral, loudness, cheer    │
                    ffmpeg → f32le PCM 스트림 → librosa STFT/RMS/onset         │
                                                                               │
   (정렬) np.interp 로 오디오 raw 를 영상 시간축 t 에 보간 ──────────────────────┘
       │
       ▼
[5채널 raw 시계열, 공통 길이]
       │  running_surprise(v, win, bins) :  각 시점 = -log2 p_hat(현재값 | 최근 윈도 분포)
       ▼
[5채널 surprise 시계열 (bits)]   frame_entropy · motion · spectral · cheer · loudness
       │  fuse_and_detect()
       │    1) _percentile_scale  : 채널별 95퍼센타일 스케일 보정
       │    2) _resolve_weights   : MI 기반 최대엔트로피 가중 w_i ∝ (1 - 평균 NMI_i)·liveness_i
       │    3) fused(t) = Σ w_i · s_i(t)        (가중 합, 여전히 bits)
       │    4) find_peaks(height=mean+z·std, distance=min_gap) → _expand_segment 로 구간 확장
       │    5) 구간 적분(trapezoid) = total_bits = 점수,  채널별 적분 = contributions
       ▼
[하이라이트 후보 → total_bits 정렬 → top_k]
       │  clipper.cut_clip()  : ffmpeg 로 [start,end] 컷  (재인코딩 or copy)
       │  clipper.make_thumbnail() : peak_sec 프레임 1장 jpg
       ▼
[AnalysisResult]  timeline(surprise 그래프용) + channels(통계/MI) + highlights(클립·설명) + mi_matrix
       │  서버: model_dump_json() → REST 응답 + result.json 저장, clip_url/thumbnail_url 부여
       ▼
[Flutter GUI]  진행률 → surprise 그래프 → 하이라이트 카드 → 클립 재생 + bits 기여 설명
```

핵심 단계의 수식·근거:

- **자기정보(surprise)**: `infotheory.running_surprise()` 는 시점 i 의 값이 직전 `win`개 샘플 분포에서 얼마나 드문지를 라플라스 평활 히스토그램으로 추정해 `I = -log2 p_hat` 을 돌려준다. 드문 값일수록 큰 bits.
- **융합(maximum entropy 관점)**: 라벨이 없을 때 가장 편향 없는 결합은 균등 가중이지만, 채널 간 상호정보량(중복)이 크면 증거를 이중계산하므로 `w_i ∝ (1 - 평균 NMI_i)·liveness_i` 로 중복 채널을 down-weight 한다. 죽은(분산 0) 채널은 가중치 ~0.
- **점수/설명**: 하이라이트 구간에서 `fused` 를 시간 적분한 값이 점수(`total_bits`)이고, `weighted[k]` 의 구간 적분이 채널별 기여(`contributions`)다 → "왜 뽑혔는가"를 bits로 분해.

---

## 4. 파이프라인 단계별 표 (진행률 구간 포함)

진행률은 `pipeline.analyze()` 의 `report(frac, stage)` 가 보고하는 실제 `fraction` 값이다. 영상/오디오 채널은 내부 `progress_range` 로 세분 보고한다.

| # | 단계(stage) | 호출 함수 / 모듈 | 진행률 구간 | 산출물 |
|---|---|---|---|---|
| 0 | 영상 정보 확인 | `clipper.ffprobe_duration` | 0.01 | 영상 길이(초) |
| 1 | 영상 분석 (프레임 엔트로피 · 모션) | `video_channel.analyze_video` | 0.03 → 0.55 | raw `frame_entropy`, `motion`, 시간축 `t` |
| 2 | 오디오 분석 (스펙트럼 · 음량 · 환호성) | `audio_channel.analyze_audio` | 0.55 → 0.78 | raw `spectral`, `loudness`, `cheer` |
| 3 | 채널 정렬 | `np.interp` (pipeline 내부) | 0.80 | 오디오 raw 를 영상 `t` 축으로 보간 |
| 4 | surprise(자기정보) 계산 | `infotheory.running_surprise` | 0.83 | 5채널 surprise 시계열(bits) |
| 5 | 멀티모달 융합 · 하이라이트 검출 | `fusion.fuse_and_detect` | 0.87 | `fused`, 후보 구간, 가중치, MI 행렬 |
| 6 | 하이라이트 클립 생성 `i/N` | `clipper.cut_clip` / `make_thumbnail` | 0.90 → 0.99 | `clips/hl_*.mp4`, `thumbs/hl_*.jpg` |
| 7 | 완료 | `pipeline` (모델 조립) | 1.0 | `AnalysisResult` |

> 진행률 세부: 단계 1·2 는 처리 프레임/초 비율에 따라 구간 안에서 선형 보고(`progress(p0 + (p1-p0)*frac, ...)`). 단계 6 은 하이라이트 개수 N 에 대해 `0.90 + 0.09*(i/N)` 으로 분배된다.

---

## 5. 1시간+ 긴 영상 처리 전략

목표: 입력 길이에 관계없이 **메모리는 상수, 처리량은 일정**. 1시간·30fps 영상은 108,000 프레임이지만 실제로 다루는 양을 손잡이 두 개로 고정한다.

### 5.1 `analysis_fps` 샘플링 (영상)
`video_channel.analyze_video` 는 원본을 모두 디코딩하지 않는다. `step = round(src_fps / analysis_fps)` 간격으로만 프레임을 본다. 나머지는 `cap.grab()`(디코드만, 색변환 생략)으로 **빠르게 스킵**하고, 샘플 시점에서만 `cap.retrieve()` 로 실제 프레임을 가져온다.

```
analysis_fps = 3, src 30fps  →  step = 10  →  108,000 프레임 → 분석 대상 10,800개
```

### 5.2 다운스케일 (영상)
각 분석 프레임을 `_resize_keep_ratio(frame, flow_w)` 로 가로 폭 `downscale_width`(기본 256px, 비율 유지)까지 줄인다. 엔트로피·옵티컬 플로우(Farneback) 계산량이 픽셀 수에 비례하므로, 작은 회색조 프레임으로 고정해 프레임당 비용을 상수화한다. `flow_downscale` 로 플로우 전용 폭을 따로 지정할 수도 있다(0이면 `downscale_width` 사용).

### 5.3 ffmpeg PCM 스트리밍 (오디오)
`audio_channel._ffmpeg_pcm_stream` 이 ffmpeg를 띄워 모노 `f32le` PCM 을 stdout 파이프로 흘려보낸다. 엔진은 이를 **고정 길이 윈도(`_WIN_SEC = 15.0`초)** 단위로 읽어 `librosa.stft / rms / onset_strength / _cheer_score` 를 돌리고 결과만 누적한다. 전체 오디오를 메모리에 적재하지 않으므로 1시간이든 3시간이든 한 윈도 크기(`win_samples = 15 × 22050` 샘플)로 일정하다. ffmpeg가 컨테이너(mp4/mkv/...)와 코덱을 모두 처리하므로 입력 형식에 안전하다.

### 5.4 메모리 상수화 (요약)
| 자원 | 상한을 고정하는 메커니즘 |
|---|---|
| 영상 디코드 | `grab()` 스킵 + `step` 샘플링 → 디코드 부담 ∝ analysis_fps |
| 프레임 메모리 | `downscale_width` 회색조 → 프레임당 픽셀 수 상수 (이전 1프레임만 유지: `prev_small`) |
| 오디오 메모리 | 15초 윈도 스트리밍 → 버퍼는 한 윈도 크기 (`bytes_per_win`) |
| 시계열 길이 | ∝ duration × analysis_fps (가벼운 1D float 배열) |
| 클립 추출 | ffmpeg가 원본을 직접 seek/컷 → 엔진이 영상을 재디코딩하지 않음 |

결과적으로 처리 비용은 대략 `O(duration × analysis_fps)` 의 작은 프레임 연산 + `O(duration)` 의 오디오 윈도 연산으로, 입력 길이에 선형이며 피크 메모리는 상수다.

---

## 6. 모듈 / 파일 지도

```
I'mTheBest/
├─ engine/                      # ── Python 엔진 (서버/GUI 비의존) ──
│  ├─ __init__.py               # 공개 진입점: analyze, AnalysisParams, 모델 re-export
│  ├─ config.py                 # AnalysisParams(데이터클래스) + CHANNELS / 라벨 / 그룹
│  ├─ infotheory.py             # 이론 핵심: shannon_entropy, self_information,
│  │                            #   image_entropy, running_surprise, mutual_information,
│  │                            #   normalized_mutual_information, robust_minmax
│  ├─ video_channel.py          # analyze_video: frame_entropy + motion(Farneback)
│  ├─ audio_channel.py          # analyze_audio: spectral/loudness/cheer (ffmpeg PCM 스트림)
│  ├─ fusion.py                 # fuse_and_detect: MI 가중 융합 + find_peaks/_expand_segment
│  ├─ clipper.py                # ffprobe_duration, cut_clip, make_thumbnail (ffmpeg)
│  ├─ pipeline.py               # analyze(): 전체 오케스트레이션 + 진행률 보고
│  ├─ models.py                 # pydantic 계약: Timeline/ChannelStat/Highlight/AnalysisResult ...
│  └─ cli.py                    # python -m engine.cli : 서버 없이 단독 실행
│
├─ server/                      # ── FastAPI 로컬 서버 ──
│  ├─ __init__.py
│  ├─ app.py                    # 엔드포인트(/health /analyze /jobs /ws /files)
│  └─ jobs.py                   # JobManager: 스레드 구동 + 진행률 누적 + URL 부여 + result.json
│
├─ app/                         # ── Flutter GUI (구현 완료, flutter analyze 0건) ──
│  └─ lib/
│     ├─ main.dart              # MediaKit 초기화 + 앱 진입점
│     ├─ theme.dart             # 다크 테마 + 채널 색상/한국어 라벨
│     ├─ models/models.dart     # AnalysisResult 등 계약 1:1 fromJson
│     ├─ api/api_client.dart    # REST + WebSocket 클라이언트
│     ├─ state/app_state.dart   # ChangeNotifier 상태
│     ├─ screens/               # home / analysis / dashboard
│     └─ widgets/               # timeline_chart, mi_matrix, highlight_card, contribution_bar, player_view
│
├─ tests/                       # test_infotheory.py, test_fusion.py
├─ requirements.txt             # numpy/scipy/opencv/librosa/fastapi/uvicorn/pydantic (torch 선택)
└─ docs/02-architecture.md      # (본 문서)
```

데이터 의존 방향: `cli`/`server.jobs` → `engine.pipeline` → (`video_channel`, `audio_channel`, `infotheory`, `fusion`, `clipper`) → `models`. `config`·`models` 는 거의 모든 모듈이 참조하는 공유 기반이다.

---

## 7. API 계약

### 7.1 엔드포인트 표 (`server/app.py`)

| 메서드 | 경로 | 요청 본문 | 응답 | 설명 |
|---|---|---|---|---|
| `GET` | `/health` | — | `{status, python, torch, cuda, device, opencv, librosa, output_dir}` | 서버/엔진/GPU·라이브러리 상태 |
| `POST` | `/analyze` | `AnalyzeRequest` `{video_path, params?}` | `{job_id}` | 분석 시작(백그라운드 스레드). 파일 없으면 400 |
| `GET` | `/jobs/{job_id}` | — | `JobStatus` | 작업 상태(+`status=="done"` 이면 `result` 포함). 없으면 404 |
| `GET` | `/jobs/{job_id}/result` | — | `AnalysisResult` | 완료 결과. 미완료 시 409 |
| `WS` | `/ws/{job_id}` | — | `{job_id, status, progress, stage, message}` 스트림 | 진행률 실시간 push(약 0.25s 간격, 변화 시) |
| `GET` | `/files/{...}` | — | 정적 파일 | 생성된 클립·썸네일 서빙(`OUTPUT_BASE` 마운트) |

상태 코드: 입력 영상 미존재 → `400`, 작업 ID 없음 → `404`, 결과 미완료 → `409`. CORS 는 전체 허용(로컬 GUI 대상).

### 7.2 데이터 모델 JSON 스키마 요약 (`engine/models.py`)

세 계층이 공유하는 계약. 필드를 바꾸면 Flutter(Dart) 모델도 함께 바꿔야 한다.

**AnalysisResult** (최상위 결과)
```jsonc
{
  "video_path": "string",
  "duration_sec": 0.0,
  "analysis_fps": 3.0,
  "frame_size": [256, 144],            // [w, h] (다운스케일 후)
  "timeline":  { /* Timeline */ },
  "channels":  [ /* ChannelStat */ ],
  "highlights":[ /* Highlight */ ],
  "params":    { /* AnalysisParams.to_dict() */ },
  "mi_matrix": { "frame_entropy": { "motion": 0.0, ... }, ... }  // 채널×채널 NMI(0~1)
}
```

**Timeline** — 그래프용 시계열. 모든 배열 길이는 `t` 와 동일하며 값은 surprise(bits).
```jsonc
{
  "t":             [/* 윈도 중심 시각(초) */],
  "frame_entropy": [/* bits */], "motion":   [/* bits */],
  "spectral":      [/* bits */], "cheer":    [/* bits */], "loudness": [/* bits */],
  "fused":         [/* 융합 최종 surprise(bits) */]
}
```

**ChannelStat** — 채널별 통계(대시보드 범례용)
```jsonc
{
  "name": "frame_entropy", "label_ko": "프레임 엔트로피",
  "group": "video",          // "video" | "audio"
  "weight": 0.0,             // 융합 가중치
  "mean_bits": 0.0, "peak_bits": 0.0,
  "mi_with_fused": 0.0       // 융합 결과와의 상호정보량(bits)
}
```

**Highlight** + **HighlightExplanation** — 하이라이트 카드/재생/설명
```jsonc
{
  "id": "hl_001", "rank": 1,
  "start_sec": 0.0, "end_sec": 0.0, "peak_sec": 0.0,
  "score": 0.0,                       // = explanation.total_bits
  "explanation": {
    "total_bits": 0.0,                // 구간 적분 정보량 = 점수
    "contributions": { "motion": 0.0, "loudness": 0.0, ... },  // 채널별 기여 bits
    "dominant_channel": "motion", "dominant_label_ko": "모션 엔트로피",
    "summary_ko": "모션 엔트로피 채널이 주도하여 약 X bits ..."
  },
  "clip_path": "…/clips/hl_001.mp4",  "clip_url": "/files/<job>/clips/hl_001.mp4",
  "thumbnail_path": "…/thumbs/hl_001.jpg", "thumbnail_url": "/files/<job>/thumbs/hl_001.jpg"
}
```

**JobStatus** (작업 상태) / **AnalyzeRequest** (요청)
```jsonc
// AnalyzeRequest
{ "video_path": "string", "params": { /* 선택: AnalysisParams 부분 지정 */ } }

// JobStatus
{
  "job_id": "string",
  "status": "queued|running|done|error",
  "progress": 0.0,          // 0.0 ~ 1.0
  "stage": "string", "message": "string",
  "error": null,
  "result": null            // status=="done" 일 때만 AnalysisResult
}
```

> `clip_url` / `thumbnail_url` 은 서버(`jobs._attach_urls`)가 `/files` 정적 라우트 기준 상대경로로 부여한다(원격/웹 재생 대비). 로컬 재생은 `clip_path`(절대 경로)를 사용할 수 있다.

---

## 부록 A. 채널 정의(요약)

| 채널 | 그룹 | raw 특징 | 직관 |
|---|---|---|---|
| `frame_entropy` | video | 프레임 픽셀 강도 히스토그램의 Shannon 엔트로피(0~8 bits) | 화면 복잡도 급변(교전·폭발 ↑, 로딩 ↓) |
| `motion` | video | Farneback optical flow magnitude 분포 엔트로피 × tanh(평균크기) | 혼란스러운 움직임 ↑, 정지/단조 팬 ↓ |
| `spectral` | audio | `librosa.onset.onset_strength`(스펙트럼 novelty) | 갑작스러운 소리 변화 |
| `loudness` | audio | RMS 음량(dB) | 음량 급변 |
| `cheer` | audio | 1~6kHz 대역비 × spectral flatness × log1p(대역에너지) 휴리스틱 | 환호성/함성(광대역·평탄 스펙트럼) |

모든 raw 채널은 `running_surprise` 를 통해 동일하게 `-log2 p` (bits) surprise 로 변환된 뒤 융합된다.

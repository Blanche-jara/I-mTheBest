# 05 — 하이라이트 길이 · 분석 파라미터 튜닝 가이드

이 문서는 **하이라이트(클립) 길이를 비롯한 모든 분석 파라미터를 어디서·어떻게 바꾸는지**,
그리고 그 설정이 **다른 컴퓨터에서도 동일하게 적용되는 원리**를 한곳에 정리한 공용 레퍼런스입니다.
아무 PC에서 이 파일만 열어도 자급자족되도록 작성했습니다.

- 길이 로직 정본: [`engine/fusion.py`](../engine/fusion.py) `_expand_segment`
- 파라미터 기본값 정본: [`engine/config.py`](../engine/config.py) `AnalysisParams`
- GUI 입력: [`app/lib/screens/home_screen.dart`](../app/lib/screens/home_screen.dart) "분석 파라미터" 패널
- GUI → 서버 전송: [`app/lib/models/models.dart`](../app/lib/models/models.dart) `AnalysisParams.toJson()`

---

## 0. 한눈에 (TL;DR) — 하이라이트를 더 길게

클립 길이를 만드는 손잡이는 **딱 3개**입니다.

| 손잡이 | 의미 | 기본값(현재) | 더 길게 하려면 |
|---|---|---|---|
| `clip_pad_sec` | 피크 앞뒤에 균일하게 붙는 여유(초) | **4.0** | ↑ (가장 직관적 — 모든 클립이 양옆 +N초) |
| `min_clip_sec` | 클립 최소 길이(초) | **12.0** | ↑ ("절대 N초보다 짧지 않게") |
| `max_clip_sec` | 클립 최대 길이(초) | **30.0** | ↑ (긴 장면이 잘리는 걸 방지) |

- **GUI에서 코드 수정 없이**: 홈 화면 "분석 파라미터" → `피크 앞뒤 여유(초)` / `클립 최소 길이(초)` / `클립 최대 길이(초)` 입력 → 분석.
- **기본값 자체를 바꿔 모든 PC·CLI에 적용**: [`engine/config.py`](../engine/config.py) 35–37행과
  [`app/lib/models/models.dart`](../app/lib/models/models.dart) `AnalysisParams` 기본값을 같이 수정.

> 현재 기본값(12/30/4)이면 보통 클립이 **~14–22초**, 임팩트 큰 장면은 최대 30초까지 나옵니다.
> (이전 기본값 4/20/2 에서는 ~10초였습니다.)

---

## 1. 분석 파라미터 전체 표

정본은 [`engine/config.py`](../engine/config.py) `AnalysisParams` 데이터클래스입니다.
"GUI 노출" 열은 홈 화면에서 코드 수정 없이 조절 가능한지 여부입니다.

| 파라미터 | 의미 | 기본값 | GUI 노출 | CLI 플래그 |
|---|---|---|---|---|
| `analysis_fps` | 초당 분석 프레임 수(샘플링 레이트). 처리량의 핵심 손잡이 | 3.0 | ✅ 분석 FPS | `--fps` |
| `downscale_width` | 분석용 프레임 가로폭(px). 처리량의 핵심 손잡이 | 256 | ❌ | `--width` |
| `surprise_window_sec` | 자기정보 추정용 "최근 과거" 윈도(초) | 6.0 | ❌ | — |
| `surprise_bins` | 특징값 히스토그램 빈 수 | 32 | ❌ | — |
| `top_k` | 최대 하이라이트 개수 | 12 | ✅ 하이라이트 수 | `--top-k` |
| `min_gap_sec` | 하이라이트 **사이** 최소 간격(초) — 길이 아님 | 8.0 | ✅ 최소 간격 | `--min-gap` |
| **`min_clip_sec`** | **클립 최소 길이(초)** | **12.0** | ✅ 클립 최소 길이 | ❌ (config 기본값) |
| **`max_clip_sec`** | **클립 최대 길이(초)** | **30.0** | ✅ 클립 최대 길이 | ❌ (config 기본값) |
| **`clip_pad_sec`** | **피크 앞뒤 여유(초)** | **4.0** | ✅ 피크 앞뒤 여유 | ❌ (config 기본값) |
| `peak_z` | 피크 임계 z (`임계 = 평균 + z·표준편차`). 높이면 더 엄격(=하이라이트 수↓) | 1.2 | ✅ 피크 임계 z | `--peak-z` |
| `reencode_clips` | 켜면 프레임 정확 컷(재인코딩), 끄면 빠른 copy 컷 | true | ✅ 스위치 | `--no-reencode` |
| `thumbnail` | 썸네일 생성 | true | ❌ | `--no-thumb` |
| `weight_*` (5종) | 채널 가중치. `None`이면 MI 기반 자동(최대엔트로피) 가중 | None | ❌ | — |

> ⚠️ **`min_gap_sec` ≠ 길이.** `min_gap_sec`는 서로 다른 하이라이트가 너무 붙지 않게 하는 **간격**이고,
> 클립 한 개의 **길이**는 아래 3개(`min/max_clip_sec`, `clip_pad_sec`)와 검출 구간이 결정합니다.

---

## 2. 클립 한 개의 길이는 어떻게 정해지나

길이 계산은 [`engine/fusion.py`](../engine/fusion.py) `_expand_segment()` 한 곳에서 끝납니다.
융합 신호 `fused` 에서 피크(`pk`)를 찾은 뒤, 다음 순서로 시작·끝 인덱스를 만듭니다.

```
1) 바닥값 floor = max(임계 × 0.6, fused 평균)
2) 피크에서 좌·우로, fused 가 floor 위인 동안 구간을 확장
3) 양쪽에 clip_pad_sec(초) 만큼 패딩 추가
4) 길이 < min_clip_sec  → 부족분을 양쪽으로 늘려 최소 길이 보장
5) 길이 > max_clip_sec  → 피크 중심으로 max_clip_sec 로 잘라냄
```

즉 **"임계 위 구간 + 좌우 패딩"** 이 자연 길이이고, 거기에 **최소·최대 클램프**가 걸립니다.

- 예전에 ~10초가 나온 이유: 자연 구간 ≈ 6초 + 패딩 2초×2 = ~10초, 최소 4초·최대 20초 안에 들어 그대로 통과.
- 더 길게 하는 직관: **패딩을 키우면** 모든 클립이 균일하게 길어지고, **최소 길이를 키우면** 짧은 클립이 강제로 늘어납니다.
  최대 길이는 "자연 길이 + 패딩"이 그 값을 넘을 때만 작동(잘림 방지용)합니다.

권장 조합 예시:

| 목표 | clip_pad_sec | min_clip_sec | max_clip_sec |
|---|---|---|---|
| 짧고 타이트하게 (구버전) | 2 | 4 | 20 |
| 균형 (현재 기본값) | 4 | 12 | 30 |
| 길고 여유 있게 | 6 | 18 | 45 |

---

## 3. 어디서 바꾸나 — 3가지 경로

### (A) GUI 홈 화면 — 코드 수정 없이, 런타임에
홈 화면 "분석 파라미터" 패널에 입력칸이 있습니다(아래 3개가 이번에 추가됨):
`클립 최소 길이(초)` · `클립 최대 길이(초)` · `피크 앞뒤 여유(초)`.
값을 바꾸고 분석을 시작하면 그 값으로 클립이 잘립니다.

> 단, 이 입력값은 **영속 저장되지 않습니다.** 앱을 재시작하면 다시 **코드 기본값**으로 돌아갑니다
> ([`app/lib/state/app_state.dart`](../app/lib/state/app_state.dart) `_params = const AnalysisParams()`).
> "매번 길게"가 기본이 되길 원하면 (B)에서 기본값을 바꾸세요.

### (B) 기본값 변경 — 모든 PC·모든 실행 경로에 적용 (권장: 영구 설정)
**두 곳을 같은 값으로** 바꿉니다. (둘이 어긋나면 GUI가 보내는 값이 이기므로 헷갈립니다.)

1. 엔진 기본값(CLI·서버 폴백) — [`engine/config.py`](../engine/config.py):
   ```python
   min_clip_sec: float = 12.0   # 클립 최소 길이
   max_clip_sec: float = 30.0   # 클립 최대 길이
   clip_pad_sec: float = 4.0    # 피크 앞뒤 여유(초)
   ```
2. GUI 기본값(앱 시작 시 입력칸 초기값) — [`app/lib/models/models.dart`](../app/lib/models/models.dart) `AnalysisParams`:
   ```dart
   this.minClipSec = 12.0,
   this.maxClipSec = 30.0,
   this.clipPadSec = 4.0,
   ```

이렇게 소스에 박아두면 **저장소를 그대로 다른 컴퓨터로 옮겨도 동일한 길이**가 기본이 됩니다(4절 참고).

### (C) 코드/스크립트에서 직접
파이썬에서 엔진을 직접 호출할 때:
```python
from engine import analyze, AnalysisParams
p = AnalysisParams(min_clip_sec=18, max_clip_sec=45, clip_pad_sec=6)
result = analyze("game.mp4", p, out_dir="output/game")
```

> 참고: 현재 **CLI([`engine/cli.py`](../engine/cli.py))에는 클립 길이 플래그가 없습니다.**
> CLI는 `config.py` 기본값을 그대로 쓰므로, CLI로 길이를 바꾸려면 (B)의 1번을 수정하거나 위 (C) 방식을 쓰세요.
> (원하면 `--min-clip` / `--max-clip` / `--clip-pad` 플래그를 추가하는 것도 간단합니다.)

---

## 4. 파라미터가 흐르는 경로 (GUI → 엔진)

```
[홈 화면 입력칸]                       app/lib/screens/home_screen.dart  _collectParams()
      │  AnalysisParams (Dart)
      ▼
toJson() → { analysis_fps, top_k, min_gap_sec, peak_z,
             min_clip_sec, max_clip_sec, clip_pad_sec, reencode_clips }
      │  POST /analyze  { video_path, params }   app/lib/api/api_client.dart
      ▼
[FastAPI]  server/app.py  /analyze → JobManager.create(...)   server/jobs.py
      │  AnalysisParams.from_dict(params)   ← 보낸 키만 덮어쓰고, 빠진 키는 config.py 기본값
      ▼
[엔진]  engine/pipeline.py analyze() → fusion.fuse_and_detect() → _expand_segment()
      │  clipper.cut_clip(start, end)   ← ffmpeg 로 실제 컷
      ▼
output/<job>/clips/*.mp4
```

핵심 규칙 두 가지:
1. **GUI가 보낸 값이 우선.** `from_dict`는 요청에 들어온 키만 덮어쓰므로, GUI가 `clip_pad_sec`를 보내면
   `config.py`의 같은 항목은 그 작업에서 무시됩니다(= 폴백 역할만).
2. **GUI가 안 보내는 항목은 `config.py` 기본값.** 예: `downscale_width`, `surprise_window_sec` 등은
   GUI에 칸이 없으므로 항상 `config.py` 값이 쓰입니다.

그래서 (B)에서 **두 곳을 같은 값**으로 맞추라고 한 것입니다 — 어느 경로로 실행하든 동일한 결과를 보장.

---

## 5. 다른 컴퓨터에서 — 이식성(Portability)

> 새 PC에서 0부터 빌드/실행하는 절차 전반은 [HANDOVER.md](HANDOVER.md)를 따르세요. 여기서는 **설정 이식**만 다룹니다.

**이 시스템에는 사용자별 설정 파일이 없습니다.** 분석 파라미터의 "진짜 출처"는 두 개의 **소스 코드 기본값**입니다:
- 엔진: [`engine/config.py`](../engine/config.py) `AnalysisParams`
- GUI: [`app/lib/models/models.dart`](../app/lib/models/models.dart) `AnalysisParams`

따라서 **이식 가능한 설정 = 소스의 기본값**입니다. 저장소를 그대로 복사/clone하면 두 기본값이 함께 따라오므로,
**별도 설정 마이그레이션 없이** 모든 PC에서 같은 길이로 동작합니다. (GUI에서 즉석으로 바꾼 값만 휘발성.)

새 컴퓨터 체크리스트(설정 관점):
1. 저장소 전체를 복사(단, `.venv`, `app/.dart_tool`, `app/build` 는 제외 — [HANDOVER.md](HANDOVER.md) 2-1 참고).
2. `scripts\setup.ps1` 로 `.venv` 재생성 → 엔진 기본값은 이미 소스에 포함되어 즉시 적용.
3. GUI를 쓰면 `app`에서 `flutter pub get` 후 `flutter run -d windows` → Dart 기본값이 입력칸 초기값으로 표시됨.
4. 길이를 영구히 바꾸고 싶으면 (B)의 두 파일을 커밋 → 다음에 어느 PC에서 받아도 그 값이 기본.

### 이번 변경으로 수정된 파일 (기록)
| 파일 | 변경 |
|---|---|
| [`engine/config.py`](../engine/config.py) | `min_clip_sec 4→12`, `max_clip_sec 20→30`, `clip_pad_sec 2→4` |
| [`app/lib/models/models.dart`](../app/lib/models/models.dart) | `AnalysisParams`에 `minClipSec/maxClipSec/clipPadSec` 필드 + `toJson()` 전송 추가 (기본값 12/30/4) |
| [`app/lib/screens/home_screen.dart`](../app/lib/screens/home_screen.dart) | 컨트롤러 3개 + dispose + `_collectParams` + "분석 파라미터" 패널 입력칸 3개 추가 |

> 서버·엔진의 수신부([`server/jobs.py`](../server/jobs.py) `AnalysisParams.from_dict`, [`engine/fusion.py`](../engine/fusion.py))는
> 이미 이 키들을 처리하므로 추가 수정이 없었습니다.

---

## 6. 알려진 경고 — media_kit CMake (CMP0175) · 무해

`flutter run -d windows` 시 다음과 같은 경고가 뜰 수 있습니다:

```
CMake Warning (dev) at flutter/ephemeral/.plugin_symlinks/media_kit_libs_windows_video/windows/CMakeLists.txt:90 (add_custom_command):
  Exactly one of PRE_BUILD, PRE_LINK, or POST_BUILD must be given. ...
  Policy CMP0175 is not set: ...
This warning is for project developers. Use -Wno-dev to suppress it.
```

- **무해합니다.** 경고를 내는 파일이 **`media_kit_libs_windows_video` 플러그인의 `CMakeLists.txt`** 라
  우리 코드가 아니며, 마지막 줄 "for project developers"의 대상은 **플러그인 개발자**입니다.
- 원인: CMake 3.31에서 도입된 정책 **CMP0175** 가 `add_custom_command()`에
  `PRE_BUILD/PRE_LINK/POST_BUILD` 중 하나를 요구하는데, media_kit의 옛 스크립트가 이를 명시하지 않음.
  CMake가 `POST_BUILD`로 가정하고 진행하므로 **빌드 결과물은 정상**입니다.
- 대응(택1): ① 그냥 둔다(권장) · ② `media_kit` / `media_kit_libs_windows_video`를 CMP0175 대응된
  상위 버전으로 올린다 · ③ 우리 쪽 `app/windows/CMakeLists.txt` 상단에 `cmake_policy(SET CMP0175 OLD)` 추가
  (단, 플러그인 내부 경고까지 전부 잡지는 못할 수 있음).

> 관련: 매우 최신 CMake에서 `flutter build windows` 의 **INSTALL 패키징 단계**가 MSB3073으로 실패할 수 있는
> 별개 이슈가 있습니다(exe 생성 *이후* 단계). 개발/실행은 `flutter run -d windows` 를 쓰면 우회됩니다.
> 자세한 내용은 [HANDOVER.md](HANDOVER.md) 3-B의 "참고 2" 참조.

---

## 7. 변경 이력

| 날짜 | 내용 |
|---|---|
| 2026-06-08 | 하이라이트 기본 길이 상향(4/20/2 → 12/30/4). GUI 홈 화면에 클립 길이 입력칸 3개 추가. 본 문서 신설. |

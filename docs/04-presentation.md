# 발표 슬라이드 아웃라인 · 데모 시나리오 · Q&A

> 주제: **게임 영상 자동 하이라이트 추출 — 정보이론(Shannon self-information) 기반 멀티모달 융합**
> 발표 형식: 1인 발표, 5~7분 기준
> 이 문서는 발표 슬라이드 구성안, 라이브 데모 시나리오, 예상 Q&A, 이론 요약을 담는다.
> 모든 함수명·파일명·파라미터는 실제 구현(`engine/`)과 일치한다.

---

## 0. 한 줄 요약과 핵심 주장

긴 게임 플레이 영상에서 "의미 있는 순간"을 자동으로 골라내되, **ML 분류기처럼 블랙박스로 점수만 내는 것이 아니라 "왜 이 순간인가"를 정보량(bits)으로 분해해 설명**하는 시스템이다.

핵심은 단 하나의 정의에서 출발한다:

```
놀라움(surprise) = 자기정보(self-information) = I(x) = -log2 p(x)   [bits]
```

영상 2채널 + 오디오 3채널 = 총 5채널 각각에서 이 surprise를 계산하고, 상호정보량(mutual information) 기반 최대엔트로피 가중으로 융합한다.

---

## 1. 슬라이드 아웃라인 (총 12장)

> 표기: **[제목 / 말할 핵심 / 시각자료 제안]**
> 5~7분 기준이므로 한 장당 평균 25~35초. ★ 표시는 시간이 부족하면 빠르게 넘길 슬라이드.

---

### 슬라이드 1 — 표지

- **제목**: 게임 영상 자동 하이라이트 추출 — 정보이론으로 "왜 하이라이트인가"를 설명하다
- **말할 핵심**: 한 문장 후킹. "1시간짜리 게임 영상에서 중요한 10초를 자동으로, 그리고 그 이유까지 설명하면서 뽑습니다."
- **시각자료**: 게임 교전 스틸컷 1장 + 그 위에 surprise 곡선이 솟구치는 오버레이. 발표자 이름/소속.

---

### 슬라이드 2 — 문제 정의

- **제목**: 왜 어려운가 / 기존 방식의 한계
- **말할 핵심**:
  - 영상은 길고(1시간 = 30fps 기준 108,000 프레임), 사람이 다 보기 힘들다.
  - 기존 ML 하이라이트 분류기는 "점수 0.87" 같은 숫자만 주고 **근거를 설명하지 못한다(블랙박스)**.
  - 게임마다 라벨링 데이터를 새로 모으기 어렵다(라벨 없는 상황).
- **시각자료**: 긴 타임라인 바 + "어디가 중요?" 물음표. 블랙박스 아이콘 대비.

---

### 슬라이드 3 — 핵심 아이디어 (정보이론 한 컷)

- **제목**: 하이라이트 = 놀라운 순간 = 정보량이 큰 순간
- **말할 핵심**:
  - 드문 일일수록 정보가 많다. 이것이 Shannon의 자기정보다.
  - 수식 하나로 끝: `I(x) = -log2 p(x)`. p가 작을수록(드물수록) bits가 크다.
  - "교전·폭발·환호성은 평소 분포에서 벗어난 드문 사건 → 큰 surprise."
- **시각자료**: `-log2 p` 그래프(p→0 일 때 발산). 옆에 "p=0.5 → 1 bit, p=0.01 → 6.6 bits" 예시 표.

```
 I(x)=-log2 p(x)
 bits
  7 |*
  6 | *
  4 |   *
  2 |      *
  1 |         *____
  0 +-------------------- p(x)
    0   0.25  0.5   1.0
```

---

### 슬라이드 4 — 전체 파이프라인 개요

- **제목**: 시스템 한눈에 보기 (`engine/pipeline.py`)
- **말할 핵심**: 입력 영상 → 영상/오디오 채널에서 raw 특징 추출 → 공통 시간축 정렬 → `running_surprise`로 bits 변환 → `fuse_and_detect`로 융합·검출 → 클립/설명 생성.
- **시각자료**: 아래 ASCII 다이어그램을 그대로 슬라이드 도식으로.

```
영상 파일
   │
   ├─[video_channel.analyze_video]──► frame_entropy(raw), motion(raw)
   │
   └─[audio_channel.analyze_audio]──► spectral, loudness, cheer (raw)
                                          │
        공통 시간축 t 로 정렬 (np.interp)  │  ← pipeline._interp
                                          ▼
   [infotheory.running_surprise]  raw → surprise(bits, -log2 p)  ×5채널
                                          │
   [fusion.fuse_and_detect]  최대엔트로피 가중 융합 → fused(bits)
                                          │
                  find_peaks → 구간 확장 → 점수=∫fused dt
                                          ▼
        하이라이트 클립(.mp4) + 채널별 기여 bits 설명
```

---

### 슬라이드 5 — 5개 채널 소개

- **제목**: 무엇을 "본다/듣는다" — 5개 채널 (`engine/config.py: CHANNELS`)
- **말할 핵심**: 영상에서 2개, 오디오에서 3개. 각 채널은 서로 다른 종류의 사건에 민감.
- **시각자료**: 아래 표.

| 채널 ID (코드) | 한국어 라벨 | 그룹 | 무엇을 포착하나 | 출처 파일 |
|---|---|---|---|---|
| `frame_entropy` | 프레임 엔트로피 | video | 화면 내부 공간 복잡도(폭발·이펙트로 화면이 복잡해짐) | `video_channel.py` |
| `motion` | 모션 엔트로피 | video | optical flow 움직임 분포의 혼란도(난전·빠른 교전) | `video_channel.py` |
| `spectral` | 스펙트럼 변화 | audio | 갑작스러운 소리 변화(onset, 총성·타격음) | `audio_channel.py` |
| `cheer` | 환호성 | audio | 광대역·평탄 스펙트럼(함성·환호) | `audio_channel.py` |
| `loudness` | 음량 변화 | audio | RMS 음량(dB)의 급변 | `audio_channel.py` |

---

### 슬라이드 6 — 영상 채널 자세히

- **제목**: 영상 채널 — 프레임 엔트로피 & 모션 엔트로피 (`video_channel.analyze_video`)
- **말할 핵심**:
  - **프레임 엔트로피**: 8-bit 그레이스케일 픽셀 강도 히스토그램의 Shannon 엔트로피(0~8 bits). `image_entropy()`. 단조로운 화면(로딩)은 낮고, 복잡한 화면(교전·폭발)은 높다.
  - **모션 엔트로피**: Farneback dense optical flow의 magnitude 분포 엔트로피. `distribution_entropy()`. 정지·단조로운 팬은 낮고, 혼란스러운 난전은 높다. 평균 크기 `tanh(mag.mean())`로 살짝 스케일.
  - 긴 영상 대응: 원본을 다 보지 않고 `analysis_fps`(기본 3fps)로 샘플링, `downscale_width`(기본 256px)로 축소 → 처리량 고정.
- **시각자료**: 같은 장면의 단조 프레임 vs 교전 프레임 + 각각의 픽셀 히스토그램 + 엔트로피 수치 비교.

---

### 슬라이드 7 — 오디오 채널 자세히 ★

- **제목**: 오디오 채널 — spectral / loudness / cheer (`audio_channel.analyze_audio`)
- **말할 핵심**:
  - **spectral**: librosa `onset_strength` 기반 스펙트럼 변화량.
  - **loudness**: `librosa.feature.rms` → dB(`20·log10(rms)`).
  - **cheer**: 휴리스틱. 1~6kHz 중역대 에너지 비율 × **spectral flatness**(기하평균/산술평균) × `log1p(band_energy)`. 환호성은 광대역·평탄하다는 성질을 이용. (`enable_cheer_model`로 torch 학습형 분류기 대체 가능하나 기본은 휴리스틱.)
  - 긴 영상 대응: ffmpeg로 PCM을 15초 윈도 스트리밍 → 메모리 상수.
- **시각자료**: 스펙트로그램 + cheer 점수 곡선이 함성 구간에서 솟는 그림.

---

### 슬라이드 8 — surprise 계산 (이론의 심장)

- **제목**: raw 특징 → 놀라움(bits) 변환 (`infotheory.running_surprise`)
- **말할 핵심**:
  - 채널마다 단위·스케일이 다르다(엔트로피 bits, dB, 휴리스틱 점수...). 그대로 더할 수 없다.
  - 해법: **"최근 과거 분포 대비 현재 값이 얼마나 드문가"**를 모든 채널에 동일하게 적용.
  - 직전 `win`개 샘플(기본 `surprise_window_sec=6초`)로 히스토그램을 만들고 라플라스 평활 후, 현재 값이 떨어진 빈의 확률 `p_hat`에 대해 `-log2 p_hat`을 반환.
  - 결과: **모든 채널이 동일한 bits 단위의 surprise 시계열**이 된다. 비로소 비교·합산 가능.
- **시각자료**: raw 신호(아래) → 변환 → surprise 신호(위) 화살표 도식. 급변 지점에서 bits 스파이크.

```
raw motion:   ─╱╲____╱╲╱╲___    (단위 제각각)
                     │  running_surprise: 최근 6초 분포 대비 -log2 p̂
                     ▼
surprise(bits): __▁__██___▁__    (드문 급변 = 큰 bits)
```

---

### 슬라이드 9 — 멀티모달 융합 (최대엔트로피)

- **제목**: 어떻게 합치나 — MI 기반 최대엔트로피 가중 (`fusion._auto_weights`)
- **말할 핵심**:
  - 라벨이 없으니 가장 편향 없는 출발점은 **균등 가중(maximum entropy prior)**.
  - 단, 두 채널이 상호정보량(MI)이 크면 **중복(redundancy)** → 같은 증거를 이중계산. 이를 보정.
  - 가중치: `w_i ∝ (1 − 평균 NMI_i) · liveness_i`. 즉 다른 채널과 겹치는(중복) 채널은 down-weight, 죽은(변화 없는) 채널은 ~0.
  - 융합 결과 `fused(t) = Σ wᵢ·sᵢ(t)`도 여전히 bits 단위 = "이 순간의 총 놀라움".
  - 가중치는 자동(MI 기반)이 기본, `weight_*` 파라미터로 수동 지정도 가능(`_resolve_weights`).
- **시각자료**: 5×5 MI 행렬 히트맵 + 가중치 막대그래프(`mi_matrix`, `weights`).

---

### 슬라이드 10 — 검출과 설명가능성

- **제목**: 하이라이트 검출 & "왜 뽑혔는가" (`fusion.fuse_and_detect`)
- **말할 핵심**:
  - 적응형 임계값: `thr = mean + peak_z·std` (기본 `peak_z=1.2`). `scipy.signal.find_peaks`로 피크 검출, `min_gap_sec`(8초)으로 간격 제약.
  - 피크에서 좌우로 임계값 위 구간 확장(`_expand_segment`), 길이는 `min_clip_sec`~`max_clip_sec`(4~20초)로 제약.
  - **점수 = 구간 적분 `total_bits = ∫ fused dt`** (`np.trapezoid`). top_k(기본 12개) 선정.
  - **설명**: 각 구간에서 채널별로도 적분(`contributions`) → 어느 채널이 몇 bits 기여했는지 분해. `_summary_ko`가 "○○ 채널이 주도하여 약 N bits..." 한국어 설명 생성.
- **시각자료**: fused 곡선 + 임계선 + 검출 구간 음영 + 그 구간의 채널별 기여 스택 막대.

```
fused(bits)
  │        ╱▒▒╲              ← 검출된 하이라이트(임계 초과)
  │   ____╱▒▒▒▒╲___    ┄┄┄ thr = mean + 1.2·std
  │__╱            ╲____
  └──────────────────── t
   기여 분해: motion 3.1b · spectral 2.0b · cheer 1.4b ...
```

---

### 슬라이드 11 — 결과 대시보드 / 데모

- **제목**: 결과물 — 자동 클립 + 정보량 대시보드
- **말할 핵심**: 출력은 `AnalysisResult`(`engine/models.py`) — 타임라인 5채널 + fused, 채널 통계(가중치·평균/최대 bits·fused와의 MI), 하이라이트 리스트(클립 경로·썸네일·설명). Flutter 대시보드가 이를 그린다.
- **시각자료**: 실제 대시보드 스크린샷(타임라인 곡선 + 하이라이트 카드 + 기여 분해). → 슬라이드 12에서 라이브.

---

### 슬라이드 12 — 기여 / 한계 / 마무리

- **제목**: 정리 · 한계 · 향후
- **말할 핵심**:
  - **기여**: 라벨 없이 동작, 단일 정보이론 정의(`-log2 p`)로 5채널 통합, 설명가능(bits 분해).
  - **한계**: cheer는 휴리스틱(실제 환호 vs 군중 잡음 혼동 가능), surprise는 "드묾"만 보므로 "재미있게 드문 것"과 "단순히 이상한 것"을 구분 못 함, 게임별 튜닝 필요.
  - **향후**: cheer 학습형 모델(`enable_cheer_model`), 채널 추가, 사용자 피드백 반영.
- **시각자료**: 3열(기여/한계/향후) 요약 + "감사합니다 / 질문".

---

## 2. 데모 시나리오 (라이브 또는 녹화)

> 목표: **각 채널이 서로 다른 사건에 반응하는 것**과 **설명가능성(기여 분해)**을 눈으로 보여준다.
> 입력은 1~3분 정도로 편집한 게임 클립 묶음을 권장(전체 분석이 빠르게 끝나도록). `analysis_fps=3` 기준 충분.

### 데모 준비 (사전, 발표 전에 미리 실행해 둘 것)

```bash
# engine/cli.py 로 분석 (경로는 환경에 맞게)
python -m engine.cli  <게임영상.mp4>  --out  <출력폴더>
# 산출물: clips/hl_001.mp4 ... , thumbs/ , AnalysisResult(JSON)
```

분석이 끝나면 대시보드(app/)로 결과 JSON을 열어둔다. 라이브에서 처음부터 돌리면 시간이 걸리므로 **결과를 미리 만들어 두고**, 발표에서는 "이미 분석된 결과"를 보여주는 것을 권장.

### 시나리오 단계 (스토리보드)

아래는 "한 클립 안에 서로 다른 사건이 순서대로 등장"하도록 편집한 데모 영상 기준이다.

| 단계 | 보여줄 장면 | 어느 채널이 솟는가 | 말할 포인트 |
|---|---|---|---|
| ① 로딩/대기 화면 | 정적인 메뉴·로딩 | (모두 낮음, baseline) | "평소엔 surprise가 낮다 = 놀랍지 않다" |
| ② FPS 교전 시작 | 빠른 이동·난전 | **`motion`** (모션 엔트로피) 급등 | "optical flow magnitude 분포가 혼란해지며 bits↑" |
| ③ 폭발/스킬 이펙트 | 화면 가득 파티클 | **`frame_entropy`** 급등 | "픽셀 강도 분포가 복잡 → 공간 엔트로피↑" |
| ④ 결정적 한 방 + 함성 | 킬 장면 + 해설/관중 환호 | **`cheer`** + **`spectral`** 급등 | "광대역·평탄 스펙트럼 = 환호성 휴리스틱이 포착" |
| ⑤ 큰 타격음/총성 | 임팩트 사운드 | **`loudness`** + **`spectral`** | "RMS dB 급변 + onset" |
| ⑥ 융합 결과 | fused 곡선 + 검출 구간 | **`fused`** 가 ②~⑤를 종합 | "여러 채널이 동시에 솟은 ④가 가장 높은 total_bits" |

### 데모에서 강조할 "설명가능성" 장면

검출된 하이라이트 카드에서 **기여 분해**를 클릭해 보여준다:

```
하이라이트 #1  (12.3초 ~ 19.8초)   점수: 14.2 bits
─────────────────────────────────────────────
설명: "환호성 채널이 주도하여 약 14.2 bits 의 정보량(놀라움)이
       관측된 구간 (기여 상위: 환호성·스펙트럼 변화)."
기여 분해:
  환호성        ████████░░  5.8 bits
  스펙트럼 변화  ██████░░░░  4.1 bits
  모션 엔트로피  ████░░░░░░  2.6 bits
  음량 변화      ██░░░░░░░░  1.2 bits
  프레임 엔트로피 █░░░░░░░░░  0.5 bits
```

→ "ML 분류기는 '점수 0.9'만 주지만, 우리는 **이 점수가 어느 채널에서 몇 bits 왔는지** 분해해 보여줍니다." 이것이 데모의 클라이맥스.

### 데모 백업 플랜

- 인터넷/실행 불안정 대비: **위 스크린샷·녹화 영상**을 슬라이드에 미리 박아 둔다.
- 라이브 실행이 가능하면 ②(모션)와 ④(환호) 두 장면만 빠르게 보여주고 나머지는 정지 화면으로 설명.

---

## 3. 예상 질문 Q&A (8문항)

### Q1. (이론) 왜 하필 `-log2 p`인가요? 그냥 변화량(차분)을 쓰면 안 되나요?

`-log2 p`는 Shannon이 유도한 **유일한** 정보 측도다(가법성·연속성·단조성 공리를 만족하는 함수는 로그뿐). 단순 차분은 단위가 채널마다 제각각이고 "드묾"을 정량화하지 못한다. 우리는 **확률**(최근 분포 대비 빈도)로 바꾼 뒤 `-log2 p`를 씌우므로 5개 채널이 전부 **동일한 bits 단위**가 되어 비교·합산이 가능해진다. 구현은 `infotheory.self_information` / `running_surprise`.

### Q2. (구현) surprise를 "최근 과거 분포 대비"로 계산하는데, 윈도 크기가 결과를 좌우하지 않나요?

맞습니다. `surprise_window_sec`(기본 6초)와 `surprise_bins`(기본 32)가 민감도를 정한다. 윈도가 짧으면 미세 변화에 민감, 길면 더 큰 맥락에서의 드묾을 본다. `running_surprise`는 직전 `win`개 샘플로만 분포를 추정하고 **라플라스 평활(+1)** 로 0 확률을 막아 `-log2 0` 발산을 방지한다. 즉 윈도는 "무엇을 평소(baseline)로 볼 것인가"를 정하는 하이퍼파라미터다.

### Q3. (이론) 채널을 그냥 평균내지 않고 MI 가중을 쓰는 이유는?

두 채널이 같은 사건에 함께 반응하면(예: 폭발 시 frame_entropy와 loudness가 동시에 솟음) 단순 합산은 **같은 증거를 이중계산**한다. 상호정보량 `I(X;Y)`가 그 중복(redundancy)을 정량화한다. 그래서 `w_i ∝ (1 − 평균 NMI_i)·liveness_i`로 **중복이 큰 채널을 깎는다**(`fusion._auto_weights`). 라벨이 없을 때 균등 가중(maximum entropy prior)에서 출발해 중복만 보정하는, 가장 편향 없는 결합이다.

### Q4. (구현) cheer(환호성)는 학습 모델인가요? 정확한가요?

기본은 **휴리스틱**입니다(`audio_channel._cheer_score`). 환호성이 (a) 1~6kHz 중역대 에너지가 크고 (b) **스펙트럼이 평탄**(spectral flatness, 백색잡음에 가까움)하다는 성질을 곱으로 점수화한다. `enable_cheer_model=True`이고 torch가 있으면 학습형 분류기로 대체 가능하나, 데모는 휴리스틱 기준이다. 한계로, 빗소리·군중 웅성거림 등 광대역 잡음을 환호로 오인할 수 있다(Q7 참고).

### Q5. (구현) 1시간짜리 영상도 처리되나요? 메모리·속도는?

처리량을 고정하도록 설계했다. 영상은 `analysis_fps`(3fps)로 샘플링 + `downscale_width`(256px)로 축소 → 1시간 30fps 영상도 실제로는 약 10,800개의 작은 프레임만 다룬다. 오디오는 ffmpeg로 PCM을 15초 윈도 스트리밍 처리 → **메모리는 영상 길이와 무관하게 한 윈도 크기로 일정**. (`video_channel.py`, `audio_channel.py` 도크스트링 참조.)

### Q6. (이론·구현) "점수"는 정확히 무엇이며 어떻게 정렬하나요?

점수 = 하이라이트 구간에서 fused surprise를 시간 적분한 값, `total_bits = ∫ fused dt`(`np.trapezoid`). 즉 "그 구간에서 누적된 총 놀라움(bits)"이다. 피크는 `find_peaks(height=mean+peak_z·std, distance=min_gap_sec)`로 찾고, 구간을 확장한 뒤 적분값 기준으로 정렬해 `top_k`(12개)를 고른다. 채널별 적분 기여(`contributions`)가 설명을 만든다(`fusion.fuse_and_detect`).

### Q7. (한계) "놀라운 순간 = 재미있는 순간"이 아닌 경우는?

핵심 한계입니다. surprise는 **드묾**만 측정하므로, "재미있게 드문 것"과 "단순히 이상한 것"(글리치, 갑작스러운 정적, 화면 깨짐)을 구분하지 못한다. 또 라벨이 없어 게임 장르별 "하이라이트의 정의" 차이를 자동 학습하지 못한다. 완화책으로 채널 가중 수동 지정(`weight_*`), `peak_z`/`min_gap_sec` 튜닝, 향후 사용자 피드백 반영을 둔다.

### Q8. (비교) 그냥 사전학습된 하이라이트 ML 모델을 쓰면 더 낫지 않나요?

성능만 보면 도메인 학습 모델이 특정 게임에서 더 정확할 수 있다. 그러나 이 프로젝트의 차별점은 두 가지: (1) **라벨이 필요 없다** — 새 게임에 데이터 수집 없이 바로 적용. (2) **설명가능하다** — 점수를 채널별 bits로 분해해 "왜 이 순간인가"를 제시한다(블랙박스가 아님). 즉 정확도 경쟁이 아니라 **라벨-프리 + 설명가능성**이 목표다. 실제로는 본 시스템을 1차 후보 추출에, ML을 재정렬에 결합하는 하이브리드도 가능하다.

---

## 4. 학습한 이론 요약 슬라이드

> 이 한 장으로 "무엇을 공부했는가"를 압축. 발표 끝부분 또는 부록에 배치.

### 4.1 핵심 정의 (모두 `engine/infotheory.py`에 구현)

| 개념 | 수식 (마크다운) | 코드 함수 | 본 시스템에서의 역할 |
|---|---|---|---|
| 자기정보 (놀라움) | `I(x) = -log2 p(x)` | `self_information` | surprise의 기본 정의 |
| Shannon 엔트로피 | `H(X) = -Σ p(x) log2 p(x)` | `shannon_entropy` | 분포의 복잡도(불확실성) |
| 프레임 엔트로피 | `H` of 픽셀 강도 분포 (0~8 bits) | `image_entropy` | 영상 공간 복잡도 |
| 분포 엔트로피 | `H` of 연속값 히스토그램 | `distribution_entropy` | optical flow 모션 엔트로피 |
| 시계열 surprise | 최근 분포 대비 `-log2 p̂(현재)` | `running_surprise` | 모든 채널 공통 bits 변환 |
| 상호정보량 | `I(X;Y) = Σ p(x,y) log2 [p(x,y)/(p(x)p(y))]` | `mutual_information` | 채널 간 중복 측정 |
| (등가식) | `I(X;Y) = H(X) + H(Y) − H(X,Y)` | — | MI의 엔트로피 해석 |
| 정규화 MI | `NMI = I(X;Y) / max(H(X), H(Y))` ∈ [0,1] | `normalized_mutual_information` | 가중치·히트맵 |

### 4.2 최대엔트로피 원리 (융합)

- 라벨이 없을 때 가장 편향 없는 prior = **균등 가중**(maximum entropy).
- 중복(MI가 큰 채널)만 보정: `w_i ∝ (1 − 평균 NMI_i) · liveness_i` (`fusion._auto_weights`).
- 융합 결과 `fused(t) = Σ wᵢ·sᵢ(t)`는 "채널 선택 prior w 하의 기대 자기정보" → 여전히 bits.

### 4.3 적용 도메인 (이론 → 신호)

```
공간(영상)  : frame_entropy  ← 픽셀 강도 분포의 H        (image_entropy)
            : motion         ← optical flow magnitude의 H (distribution_entropy)
시간(오디오): spectral       ← onset strength (스펙트럼 변화)
            : loudness       ← RMS dB
            : cheer          ← band ratio × spectral flatness
                    ↓ (모두) running_surprise: -log2 p̂
           동일 단위 bits → MI 가중 융합 → ∫dt = 점수(bits)
```

### 4.4 한 문장 정리

> **"드문 사건은 정보가 많다(`-log2 p`). 영상·오디오 5채널에서 이 놀라움을 bits로 통일하고, 중복은 상호정보량으로 깎아 융합하면, 라벨 없이도 하이라이트를 뽑고 그 이유를 bits로 설명할 수 있다."**

---

## 부록 A. 발표 시간 배분 (6분 기준)

| 구간 | 슬라이드 | 시간 |
|---|---|---|
| 도입(문제·아이디어) | 1~3 | ~1분 20초 |
| 시스템·채널 | 4~7 | ~1분 40초 |
| 이론 핵심(surprise·융합·검출) | 8~10 | ~1분 40초 |
| 데모·결과 | 11 + 라이브 | ~1분 |
| 정리·한계 | 12 | ~20초 |
| (이론 요약 4장은 부록/질문 대비용) | — | Q&A 중 활용 |

## 부록 B. 슬라이드 ↔ 코드 매핑 (신뢰도 체크용)

| 슬라이드 주장 | 근거 파일·함수 |
|---|---|
| 5채널 정의 | `engine/config.py: CHANNELS, CHANNEL_LABELS_KO` |
| frame_entropy / motion | `engine/video_channel.py`, `infotheory.image_entropy/distribution_entropy` |
| spectral / loudness / cheer | `engine/audio_channel.py: analyze_audio, _cheer_score` |
| surprise = `-log2 p̂` | `engine/infotheory.py: running_surprise, self_information` |
| MI 가중 융합 | `engine/fusion.py: _auto_weights, _resolve_weights` |
| 검출·점수=∫fused dt·기여 분해 | `engine/fusion.py: fuse_and_detect, _expand_segment` |
| 한국어 설명 생성 | `engine/pipeline.py: _summary_ko` |
| 결과 데이터 구조 | `engine/models.py: AnalysisResult, Timeline, Highlight` |

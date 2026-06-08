# 설명가능성: 왜 이 순간이 하이라이트인가

> 본 문서는 `engine/` 구현(특히 `engine/infotheory.py`, `engine/fusion.py`, `engine/pipeline.py`, `engine/models.py`)에 정확히 대응한다. 모든 수치 단위는 **bits**이며, 코드에 실제로 존재하는 함수명·필드명만 사용한다.

---

## 1. 문제의식: 블랙박스 ML 분류기의 한계

하이라이트 검출을 "지도학습 이진 분류"로 푸는 흔한 접근(프레임/구간 → `하이라이트=1`)은 동작하지만, 발표·심사·실사용 관점에서 다음 한계를 가진다.

- **근거가 불투명하다.** 분류기는 점수(예: 0.92)를 내지만 "왜 이 점수인가"가 가중치 수억 개에 흩어져 있어, 사람이 검증할 수 있는 형태가 아니다.
- **라벨 의존성이 크다.** 게임·종목·방송 스타일마다 "하이라이트"의 정의가 다른데, 분류기는 학습 데이터의 라벨 분포를 그대로 따라간다. 라벨이 없거나 편향되면 곧장 성능·신뢰가 무너진다.
- **단위가 없다.** 출력 0.92는 "0.91보다 조금 큰 무언가"일 뿐, 물리적·정보적 의미가 없다. 두 하이라이트를 "정보량 기준 1.7배"처럼 정량 비교할 수 없다.
- **채널 기여 분해가 어렵다.** "이 장면은 화면 변화보다 환호성 때문에 뽑혔다"를 사후설명(saliency, SHAP 등)으로 근사할 수는 있으나, 그것은 모델과 별개의 또 다른 추정이다.

본 시스템은 이 문제를 **모델 구조 자체를 설명가능하게** 설계해 해결한다. 즉 사후설명을 덧붙이는 것이 아니라, 점수의 정의 자체가 분해 가능한 정보량이다.

---

## 2. 본 접근의 차별점: 정보량(bits)으로 정량 설명

핵심 정의는 Shannon의 **자기정보(self-information)** 다.

```
I(x) = -log2 p(x)   [bits]
```

`p(x)`가 작을수록(=드물수록) `I(x)`가 크다. 즉 "드문 일 = 놀라움(surprise) = 정보량이 큰 순간"이다. 이 정의는 `engine/infotheory.py`의 `self_information()`에 그대로 구현되어 있다.

각 채널은 자신의 raw 특징 시계열에서, **"최근 과거 분포 대비 현재 값이 얼마나 드문가"** 를 `running_surprise()`로 계산한다.

```
시점 i 의 surprise:
  최근 win 개 샘플로 분포 p_hat 추정(라플라스 평활)
  현재 값이 속한 빈의 확률 p_hat(bin) 에 대해  s_i = -log2 p_hat(bin)
```

이 과정을 거치면 5개 채널이 모두 **동일한 단위(bits)** 의 시계열이 된다.

| 채널 식별자 (`CHANNELS`) | 한글 라벨 (`CHANNEL_LABELS_KO`) | 그룹 | raw 특징 출처 |
|---|---|---|---|
| `frame_entropy` | 프레임 엔트로피 | video | 프레임 픽셀 강도 분포 엔트로피 (`image_entropy`) |
| `motion` | 모션 엔트로피 | video | dense optical flow magnitude 분포 엔트로피 |
| `spectral` | 스펙트럼 변화 | audio | spectral novelty / onset strength |
| `cheer` | 환호성 | audio | 중역대 광대역·평탄 스펙트럼 휴리스틱 (`_cheer_score`) |
| `loudness` | 음량 변화 | audio | RMS 음량(dB) |

> 차별점 한 줄 요약: **분류기의 출력 0.92 대신, "이 구간은 12.4 bits, 그중 환호성 7.1 bits"처럼 단위를 가진 분해 가능한 근거를 낸다.**

---

## 3. 점수 = 구간 적분 정보량 계산식과 의미

### 3.1 채널 융합 (fused surprise)

라벨이 없으므로 가장 편향 없는 결합은 균등 가중이다. 다만 채널들이 서로 상호정보량(MI)이 크면 같은 증거를 **이중계산(redundancy)** 하게 되므로, 중복이 큰 채널의 가중치를 낮춘다. 이것이 `engine/fusion.py`의 최대엔트로피 가중(`_auto_weights`)이다.

```
w_i ∝ (1 - 평균 NMI_i) · liveness_i        (정규화하여 Σ w_i = 1)

fused(t) = Σ_i  w_i · s_i(t)               [bits]
```

- `평균 NMI_i` : 채널 i와 나머지 채널들 간 정규화 상호정보량의 평균 (`normalized_mutual_information`)
- `liveness_i` : 채널이 살아있는지(표준편차 > 1e-6) 여부. 죽은 채널은 가중치 ≈ 0
- 모든 채널 가중치를 수동 지정하면(`weight_*` 파라미터) 자동 가중 대신 그 값을 정규화해 사용 (`_resolve_weights`)

`fused(t)`는 "채널 선택 prior `w` 하의 기대 자기정보"로, 여전히 bits 단위이며 **"이 순간의 총 놀라움"** 으로 해석된다.

### 3.2 점수 = 구간 적분

하이라이트 구간 `[t_start, t_end]`의 점수는 `fused(t)`를 그 구간에서 **시간 적분(사다리꼴, `numpy.trapezoid`)** 한 값이다.

```
total_bits = ∫_{t_start}^{t_end}  fused(t) dt        [bits·sec 차원, 코드상 'bits' 점수로 사용]
```

코드(`fuse_and_detect`)에서:

```python
total_bits = float(_trapz(fused[seg], seg_t))   # seg = [s_idx .. e_idx]
```

**의미**: 단일 피크 높이가 아니라 "정보량 곡선 아래 면적"을 점수로 쓴다. 따라서

- 짧고 날카로운 한 순간보다,
- 비슷한 강도라도 **충분히 오래 지속된** 순간이 더 높은 점수를 받는다.

이는 "강렬함 × 지속성"을 동시에 반영하는 자연스러운 정의이며, 하이라이트는 이 `total_bits` 기준으로 정렬되어 상위 `top_k`개가 선택된다(`cand.sort(key=... total_bits, reverse=True)`).

### 3.3 검출 흐름 (ASCII)

```
raw 특징(영상/오디오)
   │  running_surprise (-log2 p_hat)
   ▼
채널별 surprise s_i(t)  [bits]  ──┐
                                  │  w_i = (1-평균NMI)·liveness  (최대엔트로피 가중)
                                  ▼
                 fused(t) = Σ w_i·s_i(t)
                                  │  적응형 임계값  thr = mean + peak_z·std
                                  │  find_peaks(height=thr, distance, prominence)
                                  ▼
                 피크별 구간 확장 (_expand_segment)
                                  │  total_bits = ∫ fused dt   (점수)
                                  ▼
                 total_bits 내림차순 정렬 → 상위 top_k
```

---

## 4. 채널별 기여(contributions) 분해와 주도채널 판정

점수가 적분으로 정의되므로, **선형성(적분은 합에 대해 분배)** 덕분에 점수를 채널별로 정확히 분해할 수 있다. 이것이 본 접근의 핵심 설명 메커니즘이다.

```
fused(t) = Σ_i  weighted_i(t),   weighted_i(t) = w_i · scaled_i(t)

⇒ total_bits = ∫ fused dt = Σ_i ∫ weighted_i dt = Σ_i contributions[i]
```

코드(`fuse_and_detect`)에서 각 구간마다:

```python
for k in CHANNELS:
    contribs[k] = float(_trapz(weighted[k][seg], seg_t))
```

즉 `total_bits = Σ_k contributions[k]`가 **근사가 아니라 정의상 정확히** 성립한다. 사후설명이 아니라, 점수의 구성요소를 그대로 보여주는 것이다.

### 주도채널 판정

`engine/pipeline.py`의 `_summary_ko()`가 기여를 내림차순 정렬해 1위 채널을 주도채널로 본다.

```python
items = sorted(contribs.items(), key=lambda kv: kv[1], reverse=True)
dom, _ = items[0]                 # 주도 채널
dom_label = CHANNEL_LABELS_KO[dom]
top2 = "·".join(...상위 2개...)
```

이 결과는 `HighlightExplanation` 모델(`engine/models.py`)에 다음 필드로 담겨 GUI/JSON으로 전달된다.

| 필드 | 의미 |
|---|---|
| `total_bits` | 구간 적분 정보량 = 점수 |
| `contributions` | 채널별 기여 bits (`dict[str, float]`) |
| `dominant_channel` | 주도 채널 식별자 (예: `cheer`) |
| `dominant_label_ko` | 주도 채널 한글 라벨 (예: 환호성) |
| `summary_ko` | 사람이 읽는 한 줄 설명 |

---

## 5. MI 행렬로 보는 채널 중복/상보성 해석

`fuse_and_detect`는 채널 쌍마다 정규화 상호정보량을 계산해 `mi_matrix`(`AnalysisResult.mi_matrix`, `dict[str, dict[str, float]]`)로 반환한다.

```python
mi_matrix[ki][kj] = normalized_mutual_information(channels[ki], channels[kj])  # 0~1
```

기반이 되는 상호정보량은 `engine/infotheory.py`의 `mutual_information`이며 표준 정의를 따른다.

```
I(X;Y) = Σ p(x,y) · log2 [ p(x,y) / (p(x) p(y)) ]  =  H(X) + H(Y) - H(X,Y)   [bits]

NMI(X;Y) = I(X;Y) / max(H(X), H(Y))   ∈ [0, 1]
```

**해석 규칙**

- `NMI`가 높다(→1) = 두 채널이 **같은 증거를 본다(중복, redundancy)**. 예: `loudness`와 `cheer`는 시끄러운 순간에 함께 오르는 경향. 중복이 크면 융합에서 가중치가 낮아진다(§3.1).
- `NMI`가 낮다(→0) = 두 채널이 **서로 다른 측면을 본다(상보, complementarity)**. 예: 조용하지만 화면이 급변하는 순간은 `frame_entropy`/`motion`만 반응. 상보 채널이 많을수록 융합의 가치가 크다.

또한 채널별 통계(`ChannelStat`)에는 융합 결과와의 상호정보량 `mi_with_fused`가 들어가, "어떤 채널이 최종 판정에 가장 많은 정보를 주었는가"를 보여준다.

### MI 행렬 읽기 (ASCII, 예시 수치)

```
NMI 행렬 (0=독립, 1=완전중복)        (대각선=자기 자신=1.00)

              frame  motion  spect  cheer  loud
   frame_entropy 1.00  0.41  0.08  0.05  0.07
   motion        0.41  1.00  0.12  0.09  0.11
   spectral      0.08  0.12  1.00  0.33  0.48
   cheer         0.05  0.09  0.33  1.00  0.55   ←┐ cheer·loudness 중복 큼
   loudness      0.07  0.11  0.48  0.55  1.00   ←┘  → 둘 다 down-weight

해석: (frame_entropy, motion)은 영상 내부에서 중간 중복(0.41),
      (cheer, loudness)는 오디오에서 높은 중복(0.55) → 가중치 자동 하향.
      영상↔오디오 교차 NMI는 낮음(상보) → 멀티모달 융합의 이득이 큼.
```

> 주의: 위 수치는 설명용 예시이며 실제 영상마다 달라진다.

---

## 6. 한계와 향후 개선

정확성을 위해 현재 구현의 한계를 명시한다.

1. **환호성 채널은 현재 휴리스틱이다.** `_cheer_score`는 "1~6kHz 중역대 에너지 × 스펙트럼 평탄도"라는 규칙 기반 점수다. 군중 함성과 광대역 잡음(바람·관중석 소음·일부 효과음)을 혼동할 수 있다.
   - 향후: `enable_cheer_model` 파라미터가 이미 자리잡혀 있으며(`config.py`), torch 가용 시 **학습형 환호성 분류기**로 대체하도록 설계되어 있다. 단, 분류기 출력도 그대로 쓰지 않고 `running_surprise`를 거쳐 bits로 환산하면 설명가능성 체계를 그대로 유지할 수 있다.
2. **`total_bits`의 차원.** 적분값은 엄밀히는 `bits·sec` 차원이며, 본 시스템은 이를 구간 점수로 사용한다. 길이가 매우 다른 구간을 비교할 때는 이 정의를 인지해야 한다(필요 시 정규화 점수 별도 제공 가능).
3. **분포 추정의 근사.** surprise·MI 모두 히스토그램(빈 수 `surprise_bins`/MI는 24)과 라플라스 평활에 기반한 추정이다. 빈 수·윈도(`surprise_window_sec`)에 따라 절대 bits 값이 달라진다. 즉 채널 간/구간 간 **상대 비교**는 견고하지만, 절대값은 파라미터 의존적이다.
4. **가중치의 시간 불변성.** `_auto_weights`는 영상 전체에 대한 단일 가중치를 산출한다. 장면 성격이 크게 바뀌는 긴 영상에서는 구간별 적응 가중이 더 정확할 수 있다(향후 과제).
5. **인과가 아닌 통계적 놀라움.** "드물다 ≠ 재미있다"인 경우(예: 로딩 화면 깜빡임)도 있다. 다채널 융합과 임계·prominence 조건이 이를 상당 부분 걸러내지만 완전하지 않다.

---

## 7. 데모에서 보여줄 설명 예시 (가상 하이라이트 1개를 bits로 분해)

아래는 발표 시연용 **가상 하이라이트 1개**의 설명 출력 예시다(수치는 구조 설명용 예시).

### 입력 구간

```
하이라이트 hl_003   rank 1
start_sec = 742.0   peak_sec = 749.3   end_sec = 758.0   (지속 16.0s)
```

### bits 분해 (contributions → total_bits)

```
채널            기여(bits)   비중     막대
─────────────────────────────────────────────────
환호성 cheer       7.1      57.3%   ██████████████████
음량 변화 loudness 2.6      21.0%   ███████
스펙트럼 spectral  1.4      11.3%   ████
모션 motion        0.9       7.3%   ███
프레임 frame_ent   0.4       3.2%   █
─────────────────────────────────────────────────
total_bits        12.4     100%   = Σ contributions  (정의상 정확)
```

### 주도채널 판정과 한 줄 설명

`_summary_ko(contribs, total_bits)`가 생성하는 출력 형태:

- `dominant_channel = "cheer"`, `dominant_label_ko = "환호성"`
- `summary_ko`:
  > **환호성 채널이 주도하여 약 12.4 bits 의 정보량(놀라움)이 관측된 구간 (기여 상위: 환호성·음량 변화).**

### 발표용 해석 멘트(예시)

> "이 장면은 화면 자체의 변화(프레임·모션 합쳐 1.3 bits)는 작지만, 군중 환호와 음량 급등이 9.7 bits를 만들어 전체 12.4 bits로 1위가 되었습니다. MI 행렬에서 cheer와 loudness가 함께 반응(중복)하므로 둘의 가중치는 이미 하향 조정된 상태이며, 그럼에도 점수가 높다는 것은 **실제로 강한 오디오 이벤트**였음을 뜻합니다. 즉 우리는 '왜 뽑혔는가'를 0.92 같은 불투명한 숫자가 아니라, **bits 단위로 분해된 근거**로 제시합니다."

---

## 부록: 관련 코드 위치 (신뢰도 확인용)

| 개념 | 함수 / 필드 | 파일 |
|---|---|---|
| 자기정보 `I(x)=-log2 p(x)` | `self_information` | `engine/infotheory.py` |
| 시계열 surprise | `running_surprise` | `engine/infotheory.py` |
| 상호정보량 / 정규화 MI | `mutual_information`, `normalized_mutual_information` | `engine/infotheory.py` |
| 최대엔트로피 가중 | `_auto_weights`, `_resolve_weights` | `engine/fusion.py` |
| 융합·검출·점수·기여 | `fuse_and_detect` (`_trapz` 적분) | `engine/fusion.py` |
| 구간 확장 | `_expand_segment` | `engine/fusion.py` |
| 주도채널·한 줄 설명 | `_summary_ko` | `engine/pipeline.py` |
| 채널 정의/라벨 | `CHANNELS`, `CHANNEL_LABELS_KO`, `CHANNEL_GROUP` | `engine/config.py` |
| 설명 데이터 모델 | `HighlightExplanation` (`total_bits`, `contributions`, `dominant_channel`, `summary_ko`), `mi_matrix` | `engine/models.py` |

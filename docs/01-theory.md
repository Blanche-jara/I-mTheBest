# 정보이론 배경: self-information · entropy · mutual information · maximum entropy

> **한 줄 요약** — 본 프로젝트는 "하이라이트 = 놀라운(surprising) 순간"이라는 가정을 Shannon의 자기정보 `I(x) = -log2 p(x)` [bits]로 수치화하고, 영상·오디오 5개 채널의 surprise 시계열을 **상호정보량 기반 최대엔트로피 가중치**로 융합해 "왜 뽑혔는가"를 bits 단위로 설명한다.

---

## 0. 들어가며 — 왜 정보이론인가

긴 게임 플레이 영상에서 의미 있는 순간을 자동으로 골라내는 문제를, 라벨 학습형 분류기 대신 **정보이론 관점**으로 푼다. 핵심 직관은 단순하다.

- 평범한 순간 = 자주 일어나는 일 = 확률 `p(x)`가 크다 → 정보량이 작다.
- 하이라이트 = 드물게 일어나는 일 = 확률 `p(x)`가 작다 → 정보량이 크다 = **놀랍다(surprise)**.

이 "놀라움"을 Shannon의 자기정보 `-log2 p(x)`로 정의하면, 모든 채널(프레임 엔트로피·모션·스펙트럼·환호성·음량)을 **같은 단위(bits)**로 환산해 비교·합산할 수 있고, 각 하이라이트의 선택 근거를 정보량으로 분해해 설명할 수 있다. 단순 ML 분류기와의 차별점이 바로 이 **설명가능성(explainability)**이다.

이 문서의 모든 개념은 실제 구현 함수(`engine/infotheory.py`, `engine/fusion.py`)와 1:1로 대응하며, 6절의 매핑 표에 정리했다.

---

## 1. 자기정보 `I(x) = -log2 p(x)` — 놀라움의 단위

### 정의와 의미

사건 `x`가 확률 `p(x)`로 일어날 때, 그 사건이 실제로 관측되었을 때의 **자기정보(self-information)** 또는 **surprise**는

```
I(x) = -log2 p(x)   [bits]
```

로 정의된다. 성질은 다음과 같다.

| `p(x)` | `I(x)` | 해석 |
|--------|--------|------|
| 1.0 (확실) | 0 bits | 전혀 놀랍지 않음 |
| 0.5 | 1 bit | 동전 한 번 던진 만큼의 정보 |
| 0.25 | 2 bits | 두 배 더 드묾 |
| 0.01 | ≈ 6.64 bits | 매우 드묾 = 매우 놀라움 |
| → 0 | → ∞ | 거의 불가능한 일이 일어남 |

- **단위는 bit.** 밑(base)이 2인 로그를 쓰기 때문이다. "이 사건을 부호화하는 데 필요한 평균 비트 수"라는 부호화 해석과도 일치한다.
- `p`가 작을수록 `I`가 단조 증가한다 → **드물수록 놀랍다.**
- 곱셈적 독립 사건의 정보량은 더해진다: `I(x,y) = I(x)+I(y)` (독립일 때). 덕분에 여러 채널의 놀라움을 합산하는 것이 자연스럽다.

### 게임 영상 예시

3초마다 한 프레임씩 샘플링하는 평범한 전투 대기 구간을 생각하자. 화면 밝기 변화, 음량, 모션이 모두 "늘 보던 분포" 안에 있으면 각 관측의 `p`가 커서 `I ≈ 0`이다. 그러다 폭발이 터지는 순간:

- 화면이 갑자기 복잡해지고(프레임 엔트로피 급증),
- 카메라/오브젝트가 격하게 움직이며(모션 엔트로피 급증),
- 관중 환호성과 음량이 치솟는다.

이 값들은 직전까지의 분포에서 **매우 드문 값**이므로 `p`가 작고 `I = -log2 p`가 커진다. 즉 그 순간의 surprise가 bits 단위로 크게 튄다.

### 코드

```python
def self_information(p, base=2.0):
    # I(x) = -log_base p(x). p 가 작을수록(드물수록) 값이 크다 = 놀라움.
    p = np.clip(np.asarray(p, dtype=np.float64), _EPS, 1.0)
    return -np.log(p) / np.log(base)
```

`_EPS = 1e-12`로 클리핑하여 `p → 0`에서 `log`가 발산(`-inf`)하는 수치 문제를 막는다. 따라서 실제 출력은 유한한 큰 값으로 포화된다.

---

## 2. Shannon 엔트로피 `H(X)`와 프레임 엔트로피(`image_entropy`)

### 엔트로피: 자기정보의 기댓값

확률분포 `X`의 **Shannon 엔트로피**는 자기정보의 기댓값, 즉 "평균 놀라움"이다.

```
H(X) = E[ I(x) ] = -Σ_x p(x) log2 p(x)   [bits]
```

- 분포가 한 점에 몰려 있으면(확실) `H = 0`.
- 분포가 균등(uniform)하면 `H`가 최대 — `n`개 결과의 균등분포에서 `H = log2 n`.
- 그러므로 엔트로피는 **불확실성/다양성/복잡도**의 척도다.

```python
def shannon_entropy(probs, base=2.0):
    p = np.asarray(probs, dtype=np.float64)
    p = p[p > 0]            # 0*log0 = 0 처리
    if p.size == 0:
        return 0.0
    p = p / p.sum()         # 정규화
    return -np.sum(p * (np.log(p) / np.log(base)))
```

### 프레임 엔트로피(`image_entropy`) — 화면의 공간 복잡도

한 프레임을 8-bit 그레이스케일로 본 뒤, **픽셀 강도 히스토그램(0~255)의 분포 엔트로피**를 구한다.

```
프레임 → 강도 히스토그램 p(intensity) → H = -Σ p log2 p   (0 ~ 8 bits)
```

- 강도가 256단계이므로 이론상 최댓값은 `log2 256 = 8 bits`.
- **단조로운 화면**(예: 로딩 화면, 단색 배경): 강도가 몇 값에 몰려 분포가 뾰족함 → 낮은 엔트로피.
- **복잡/혼란스러운 화면**(예: 교전, 폭발, 파티클): 강도가 넓게 퍼짐 → 높은 엔트로피.

```python
def image_entropy(gray):
    g = np.asarray(gray).ravel()
    counts = np.bincount(g.astype(np.uint8), minlength=256).astype(np.float64)
    total = counts.sum()
    if total <= 0:
        return 0.0
    p = counts / total
    return shannon_entropy(p)
```

```
강도 히스토그램의 두 극단
  단조로운 화면 (H ≈ 2 bits)        복잡한 화면 (H ≈ 7 bits)
  count                              count
   |█                                 |  ▁▃▅▆▇▆▅▃▂▁
   |█                                 | ▂████████████▂
   |█▁          ▁                     |▃██████████████▃
   +----------------→ intensity       +----------------→ intensity
   분포가 한쪽에 몰림 → 낮음           분포가 넓게 퍼짐 → 높음
```

> **참고: `image_entropy`(공간 엔트로피) ≠ `frame_entropy` 채널.**
> `image_entropy`는 *한 프레임의 절대 복잡도(0~8 bits)*다. 반면 융합에 들어가는 `frame_entropy` **채널**은 이 시계열의 *시간적 급변에 대한 surprise(`running_surprise`, 5절)*다. 즉 "화면이 복잡하다"가 아니라 "화면 복잡도가 평소와 달리 갑자기 변했다"를 측정한다. 같은 논리로 `motion` 채널은 옵티컬 플로우 magnitude 분포 엔트로피(`distribution_entropy`)의 급변에서 나온다.

`distribution_entropy`는 연속값(예: 옵티컬 플로우 magnitude)을 히스토그램으로 묶어 같은 방식으로 엔트로피를 구하는 헬퍼다.

```python
def distribution_entropy(values, bins=32, value_range=None):
    p = histogram_probs(values, bins=bins, value_range=value_range, smooth=0.0)
    return shannon_entropy(p)
```

---

## 3. 상호정보량 `I(X;Y)`와 정규화 NMI

### 정의

두 변수 `X`, `Y`가 **얼마나 정보를 공유하는가**를 재는 것이 **상호정보량(mutual information)**이다.

```
I(X;Y) = Σ_{x,y} p(x,y) log2 [ p(x,y) / ( p(x) p(y) ) ]
       = H(X) + H(Y) - H(X,Y)
```

- `X`, `Y`가 **독립**이면 `p(x,y) = p(x)p(y)` → `I(X;Y) = 0` (공유 정보 없음).
- 둘이 강하게 연동될수록 `I(X;Y)`가 커진다 — 한쪽을 알면 다른 쪽의 불확실성이 줄어든다.
- 항상 `I(X;Y) ≥ 0`이며 대칭이다: `I(X;Y) = I(Y;X)`.

`H(X)+H(Y)-H(X,Y)` 형태가 보여주듯, 상호정보량은 "각자의 불확실성 합에서 결합 불확실성을 뺀 **겹치는 부분**"이다.

```
   H(X)               H(Y)
 .------.           .------.
 |      |  I(X;Y)   |      |
 |   H(X|Y)  ▒▒▒  H(Y|X)  |
 |      |▒▒▒▒▒▒▒▒▒▒▒|      |
 '------'           '------'
            └── 겹치는 영역(▒) = I(X;Y) = 공유 정보 = 중복(redundancy)
```

### 구현 — 2D 히스토그램으로 결합분포 추정

```python
def mutual_information(x, y, bins=24):
    # ... 길이/분산 유효성 검사 ...
    c_xy, _, _ = np.histogram2d(x, y, bins=bins)   # 결합 카운트
    p_xy = c_xy / c_xy.sum()                        # 결합분포 p(x,y)
    p_x = p_xy.sum(axis=1, keepdims=True)           # 주변분포 p(x)
    p_y = p_xy.sum(axis=0, keepdims=True)           # 주변분포 p(y)
    denom = p_x * p_y
    mask = (p_xy > 0) & (denom > 0)
    mi = np.sum(p_xy[mask] * np.log2(p_xy[mask] / denom[mask]))
    return max(0.0, mi)
```

샘플이 8개 미만이거나 한쪽 분산이 0이면 추정이 무의미하므로 `0.0`을 반환한다(수치 안정성).

### 정규화 상호정보량(NMI) — 0~1 스케일

`I(X;Y)`의 크기는 각 변수의 엔트로피에 의존하므로, 채널 간 비교나 행렬 시각화에는 **정규화 버전**이 편하다.

```
NMI(X;Y) = I(X;Y) / max( H(X), H(Y) )   ∈ [0, 1]
```

```python
def normalized_mutual_information(x, y, bins=24):
    mi = mutual_information(x, y, bins=bins)
    hx = distribution_entropy(x, bins=bins)
    hy = distribution_entropy(y, bins=bins)
    denom = max(hx, hy, _EPS)
    return np.clip(mi / denom, 0.0, 1.0)
```

- `NMI = 0`: 두 채널이 독립(서로 다른 정보를 본다).
- `NMI = 1`: 한 채널이 다른 채널을 사실상 결정한다(완전 중복).

이 NMI가 4절의 융합 가중치와 `fuse_and_detect`의 `mi_matrix`(대시보드용 채널 간 중복 행렬)를 만든다.

---

## 4. 최대엔트로피 원리와 채널 융합 가중치 유도

### 최대엔트로피 원리(maximum entropy principle)

> "주어진 제약(아는 것) 외에는 **가장 편향이 적은**, 즉 엔트로피가 최대인 분포를 택하라."

라벨이 없는(unsupervised) 상황에서 5개 채널을 결합할 때, 어떤 채널이 더 중요한지에 대한 **사전 정보가 없다.** 최대엔트로피 원리에 따르면 이때 가장 편향 없는 선택은 **균등 가중(uniform prior)** `w_i = 1/n`이다.

```
fused(t) = Σ_i w_i · s_i(t)
```

여기서 `s_i(t)`는 채널 `i`의 surprise 시계열(bits, 5절)이다. 채널 선택 prior `w` 하에서 `fused(t)`는 **기대 자기정보**이며, 여전히 bits 단위로 "이 순간의 총 놀라움"으로 해석된다.

### 중복(redundancy) 보정 — 균등에서 한 발 더

균등 가중에는 함정이 있다. 두 채널이 **거의 같은 정보**를 본다면(예: 음량과 환호성이 늘 동시에 튄다 → 높은 NMI), 균등 합산은 그 증거를 **이중 계산(double counting)**한다. 같은 놀라움을 두 번 더하는 셈이다.

이를 파시모니(parsimony)/최대엔트로피 관점에서 보정한다: **다른 채널과 평균 중복(NMI)이 큰 채널의 가중치를 낮춘다(down-weight).**

```
w_i ∝ ( 1 - 평균 NMI_i ) · liveness_i
```

- `평균 NMI_i` = 채널 `i`와 나머지 채널들 간 NMI의 평균(자기 자신 제외). 클수록 중복이 큼 → `(1 - 평균 NMI_i)`가 작아짐 → 가중치 down.
- `liveness_i` = 채널이 "살아 있는지"(`std > 1e-6`이면 1, 아니면 0). **죽은(변화 없는) 채널은 가중치 ~0**으로 자동 배제된다.
- 마지막에 `Σ w_i = 1`이 되도록 정규화. 모든 채널이 죽으면 균등 가중 `1/n`으로 폴백.

```python
def _auto_weights(series):
    # 각 채널의 다른 채널과의 평균 NMI 계산
    for i, ki in enumerate(keys):
        vals = [normalized_mutual_information(series[ki], series[kj])
                for j, kj in enumerate(keys) if i != j]
        avg_nmi[ki] = np.mean(vals) if vals else 0.0
    # raw 가중치 = (1 - 평균 NMI) * liveness
    for k in keys:
        live = 1.0 if (series[k].size and series[k].std() > 1e-6) else 0.0
        raw[k] = max(0.0, (1.0 - avg_nmi[k])) * live
    total = sum(raw.values())
    if total < 1e-9:
        return {k: 1.0 / n for k in keys}   # 전부 죽으면 균등 폴백
    return {k: raw[k] / total for k in keys}
```

### 수동 가중치와의 결합

`_resolve_weights`는 사용자가 `config.py`에서 채널별 가중치(`weight_frame_entropy` 등)를 직접 줄 수 있게 한다.

- **모든** 채널을 수동 지정 → 그 값을 정규화해 사용.
- **일부만** 지정 → 지정된 값은 존중하고, 나머지는 위 auto 비율로 채운 뒤 전체 정규화.
- **아무것도 지정 안 함**(기본값, 전부 `None`) → 순수 `_auto_weights`(최대엔트로피) 사용.

```
중복 down-weight 흐름

 채널들의 surprise 시계열
        │
        ▼
  NMI 행렬 계산 (normalized_mutual_information)
        │
        ▼
  평균 NMI_i 산출 ──► (1 - 평균 NMI_i)  : 중복 클수록 작아짐
        │                    ×
        ▼              liveness_i (죽은 채널 0)
   raw_i = max(0, 1-평균NMI_i) · liveness_i
        │
        ▼
  Σ 로 정규화 → w_i  (Σ w_i = 1)
        │
        ▼
  fused(t) = Σ w_i · s_i(t)   [bits]
```

> **요지:** 균등 가중(최대엔트로피 prior)에서 출발하되, **측정된 채널 간 중복만큼만** 균등에서 벗어난다. 새로운 정보를 주는 독립적 채널은 살리고, 남의 정보를 베끼는 중복 채널은 누른다.

---

## 5. running self-information — surprise를 시계열에 적용하기

### 아이디어

1·2절의 자기정보는 "분포 `p`가 주어졌을 때 한 사건의 놀라움"이었다. 하지만 게임 영상에는 고정된 `p`가 없다. 그래서 **시간에 따라 분포를 적응적으로 추정**한다.

> 시점 `i`의 값이, **직전 `win`개 샘플이 그리는 분포**에서 얼마나 드문가?

이것이 `running_surprise`이며, 각 채널의 원시 특징 시계열(프레임 엔트로피, 모션 엔트로피, 스펙트럼 변화, 환호, 음량)을 **bits 단위 surprise 시계열**로 바꾼다.

### 절차

각 시점 `i`에 대해:

1. **최근 과거 윈도** `s[i-win : i]`를 잘라낸다(미래를 보지 않는 인과적 추정).
2. 그 윈도를 히스토그램으로 만들고 **라플라스 평활**(`+1`)로 확률 `p_hat`을 추정한다 — 본 적 없는 빈에도 0이 아닌 확률을 부여해 `-log 0` 발산을 막는다.
3. 현재 값 `s[i]`가 떨어지는 빈의 확률 `p_hat(현재 빈)`을 읽어 **`-log2 p_hat`**를 출력한다.

급변(드문 값)일수록 그 빈의 추정 확률이 작아 큰 bits가 나온다 → 그 순간이 놀랍다.

```python
def running_surprise(series, win, bins=32):
    # ... lo, hi 로 공통 edges 구성, win = max(4, win) ...
    for i in range(n):
        a = max(0, i - win)
        hist = s[a:i]                 # 직전 win 개 (인과적)
        if hist.size < 4:
            continue                  # 표본 부족하면 surprise 0 유지
        counts, _ = np.histogram(hist, bins=edges)
        counts = counts.astype(np.float64) + 1.0      # 라플라스 평활
        probs = counts / counts.sum()
        b = int(np.clip(np.searchsorted(edges, s[i], side="right") - 1, 0, bins - 1))
        out[i] = self_information(probs[b])           # -log2 p_hat
    return out
```

```
running_surprise 의 슬라이딩 윈도 (시점 i)

  과거 ←----- win 개 ------→ │ 현재
  ┌───┬───┬───┬───┬───┬───┐ │ ┌───┐
  │ s │ s │ s │ s │ s │ s │ │ │s_i│
  └───┴───┴───┴───┴───┴───┘ │ └───┘
   └──── 분포 p_hat 추정 ────┘   ▲
                                 └ p_hat(s_i 의 빈)을 읽어 -log2 → surprise[i]
```

### 설정 손잡이(`config.py`)

- `surprise_window_sec = 6.0` — "최근 과거"로 볼 시간 길이(초). `analysis_fps`와 곱해 윈도 샘플 수 `win`을 정한다.
- `surprise_bins = 32` — 특징값 히스토그램 빈 수.

이렇게 5개 채널이 모두 `-log2 p` 라는 **동일한 surprise 정의·동일한 단위(bits)**로 환산되므로, 4절의 가중 합산이 의미를 갖는다.

---

## 6. 개념 ↔ 코드 매핑

### 함수 매핑 (`engine/infotheory.py`)

| 개념 | 수식 | 함수 | 파일 |
|------|------|------|------|
| 자기정보(surprise) | `I(x) = -log2 p(x)` | `self_information` | `engine/infotheory.py` |
| Shannon 엔트로피 | `H(X) = -Σ p log2 p` | `shannon_entropy` | `engine/infotheory.py` |
| 프레임 공간 엔트로피 | 강도 히스토그램 `H` (0~8 bits) | `image_entropy` | `engine/infotheory.py` |
| 연속값 분포 엔트로피 | 히스토그램 `H` | `distribution_entropy` | `engine/infotheory.py` |
| 히스토그램 확률(평활) | 라플라스 평활 `p` | `histogram_probs` | `engine/infotheory.py` |
| running self-information | 윈도 `p_hat`의 `-log2 p_hat` | `running_surprise` | `engine/infotheory.py` |
| 상호정보량 | `I(X;Y)=H(X)+H(Y)-H(X,Y)` | `mutual_information` | `engine/infotheory.py` |
| 정규화 상호정보량(NMI) | `I(X;Y)/max(H(X),H(Y))` | `normalized_mutual_information` | `engine/infotheory.py` |
| 이상치 강건 정규화 | 1~99% min-max | `robust_minmax` | `engine/infotheory.py` |

### 융합·설정 매핑 (`engine/fusion.py`, `engine/config.py`)

| 개념 | 수식/역할 | 함수 또는 변수 | 파일 |
|------|-----------|----------------|------|
| 최대엔트로피 가중치 | `w_i ∝ (1-평균NMI_i)·liveness_i` | `_auto_weights` | `engine/fusion.py` |
| 수동/자동 가중치 결합 | 정규화 `Σ w_i = 1` | `_resolve_weights` | `engine/fusion.py` |
| 채널 스케일 보정 | 95퍼센타일 기준 완만 보정 | `_percentile_scale` | `engine/fusion.py` |
| 융합·하이라이트 검출 | `fused = Σ w_i·s_i`, peak 검출·적분 | `fuse_and_detect` | `engine/fusion.py` |
| 구간 확장 | 임계값 위 좌우 확장+길이 제약 | `_expand_segment` | `engine/fusion.py` |
| 채널 정의 | 5개 채널 식별자 | `CHANNELS` | `engine/config.py` |
| 분석 파라미터 | fps·윈도·임계값 등 | `AnalysisParams` | `engine/config.py` |
| surprise 윈도/빈 | `surprise_window_sec`, `surprise_bins` | `AnalysisParams` 필드 | `engine/config.py` |
| 가중치 수동 지정 | `weight_*`(None=자동) | `AnalysisParams` 필드 | `engine/config.py` |

### 5개 채널(`CHANNELS`)

| 채널 | 한국어 라벨 | 그룹 | 원시 특징 → surprise |
|------|-------------|------|----------------------|
| `frame_entropy` | 프레임 엔트로피 | video | `image_entropy` 시계열의 `running_surprise` |
| `motion` | 모션 엔트로피 | video | 옵티컬 플로우 magnitude `distribution_entropy`의 `running_surprise` |
| `spectral` | 스펙트럼 변화 | audio | 스펙트럼 novelty의 `running_surprise` |
| `cheer` | 환호성 | audio | 환호/함성 강도의 `running_surprise` |
| `loudness` | 음량 변화 | audio | RMS 음량의 `running_surprise` |

### 전체 파이프라인 요약

```
원본 영상/오디오
   │  (analysis_fps 로 샘플링)
   ▼
채널별 원시 특징 시계열
   image_entropy / 플로우 entropy / spectral / cheer / loudness
   │  running_surprise (5절)  ── 모두 -log2 p, 단위 bits
   ▼
5개 surprise 시계열  s_i(t)
   │  _auto_weights (4절)  ── 중복 채널 down-weight
   ▼
가중 융합  fused(t) = Σ w_i · s_i(t)   [bits = 총 놀라움]
   │  find_peaks + _expand_segment
   ▼
하이라이트 구간 + 채널별 bits 기여(설명) + NMI 행렬(대시보드)
```

이로써 각 하이라이트는 `fused`의 구간 적분값(`total_bits`)으로 점수가 매겨지고, 채널별 적분 기여(`contributions`)가 **"왜 이 순간이 뽑혔는가"를 bits 단위로 분해**해준다. 이것이 본 프로젝트가 단순 분류기와 구별되는 설명가능성의 핵심이다.

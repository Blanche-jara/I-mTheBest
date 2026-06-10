# 06 · 프로젝트 종합 분석 리포트 (코드·문서 감사)

> 작성일 2026-06-09 · 대상 커밋 `825a7c6` 기준
> 방법: 6개 서브시스템 병렬 심층 리딩 → 문서↔코드 정합성 검증 · 정보이론 수학 적대적 검증 · 리스크 감사(멀티 에이전트) → 메인 검토자가 핵심 주장(정보이론 코어·서버·빌드)을 직접 재실행·교차검증.
> 이 리포트는 **외부 검토자 시점의 평가**다. 발표/제출 시 "알면서 만든 약점"을 먼저 말하는 데 쓰라.

---

## 0. 한 줄 결론

**정보이론 코어(self-information·entropy·MI·기여 분해)는 교과서적으로 정확하고 설명가능성 주장은 수학적으로 참이다.** 다만 마케팅 문구 두 개 — "최대엔트로피 융합"과 "점수 = bits" — 는 코드가 실제로 하는 것보다 과장돼 있으며, **로컬 서버에 인증·경로검증이 없어 보안상 critical 이슈 2건**이 있다. 학술 데모로서는 강하고, 제품으로 가려면 보안·견고성·테스트 보강이 필요하다.

| 항목 | 평가 |
|---|---|
| 이론적 정직성 (코어 수학) | 🟢 강함 — 핵심 정의는 정확, 설명가능성 분해는 **수학적으로 정확(exact)** |
| 이론 ↔ 코드 일치 | 🟡 대체로 일치, 헤드라인 2건 과장 (bits 의미·최대엔트로피) |
| 문서 품질 | 🟢 높음 — 코드 대비 충실도 높고 한계도 솔직히 기재 |
| 보안 | 🔴 critical 2건 (인증 없는 임의 파일 읽기 · 와일드카드 CORS) |
| 견고성/운영 | 🟡 동시성·정리·ffmpeg 프리플라이트 부재 |
| 테스트/CI | 🔴 엔진 10모듈 중 3개만 테스트, 서버·앱 사실상 0, CI 없음 |
| 긴 영상 상수 메모리 | 🟢 주장대로 실제 스트리밍 구현됨 |
| 라벨 불필요 | 🟢 참 — 학습 모델·라벨 전혀 없음 |

---

## 1. 시스템 개요

3계층 + 문서로 구성된 멀티모달 게임 하이라이트 추출기.

```
engine/ (정보이론 엔진, CLI 단독 실행 가능)   ─ NumPy·SciPy·OpenCV·librosa·ffmpeg
   └─ 영상(프레임 엔트로피·모션) + 오디오(스펙트럼·환호성·음량)
      → 채널별 running_surprise(-log₂p) → MI 기반 가중 융합 → 피크 검출 → 클립/썸네일
server/ (FastAPI 로컬 API)                  ─ 작업 스레드·진행률 WS·정적 서빙
app/    (Flutter 데스크톱 GUI)               ─ 대시보드·타임라인·MI 히트맵·플레이어
docs/   (이론·아키텍처·설명가능성·발표·튜닝·인수인계)
```

데이터 흐름은 [pipeline.py](../engine/pipeline.py)가 오케스트레이션한다: probe → 영상 채널 → 오디오 채널 → 공통 시간축 정렬 → 채널별 surprise → 융합/검출 → 클립.

---

## 2. 정보이론 코어 검증 (이 프로젝트의 심장)

프로젝트의 핵심 주장은 "ML 블랙박스 대신 Shannon 정보이론으로 *왜* 하이라이트인지 bits로 설명한다"이다. 코어를 줄 단위로 적대적 검증한 결과:

### 2.1 정확한 것 (🟢 — 진짜 정보이론)

| 요소 | 위치 | 판정 |
|---|---|---|
| `self_information` I(x)=−log₂p | [infotheory.py:32-36](../engine/infotheory.py#L32-L36) | ✅ 정확. base-2, `[1e-12,1]` 클립으로 수치 안정(최대 ~39.86 bits) |
| `shannon_entropy` H=−Σp·log₂p | [infotheory.py:22-29](../engine/infotheory.py#L22-L29) | ✅ 정확. 0·log0 처리·재정규화 적절 |
| `mutual_information` = H(X)+H(Y)−H(X,Y) | [infotheory.py:104-126](../engine/infotheory.py#L104-L126) | ✅ 교과서적 plug-in MI (2D 히스토그램, ≥0 클램프) |
| `running_surprise` 인과적 추정 | [infotheory.py:71-101](../engine/infotheory.py#L71-L101) | ✅ 현재 표본을 **제외한** 과거 윈도(`s[a:i]`)로 추정 → 진짜 one-step-ahead surprise |
| **채널 기여 분해** Σ contrib = total | [fusion.py:135-137](../engine/fusion.py#L135-L137) | ✅ **정확한 가법 분해**. trapezoid 선형성으로 Σ기여 = 점수 (수치오차 0). SHAP/saliency 같은 근사가 아님 — 가장 강한 설명가능성 자산 |

> **이 5개가 프로젝트의 진짜 가치다.** "환호성 3.7 bits + 모션 4.7 bits" 같은 분해는 사후 근사가 아니라 점수의 정확한 가법 분해이며, 이것이 "label-free explainability"의 핵심 근거다.

### 2.2 과장된 것 (🔴 — 정보이론 용어로 포장된 휴리스틱)

**(a) "최대엔트로피 융합"은 최대엔트로피 원리가 아니다.**
[fusion.py:51-73](../engine/fusion.py#L51-L73)의 `_auto_weights`는 `w_i ∝ (1 − 평균NMI_i)·liveness_i`다. 이는 **중복(redundancy) 페널티 선형 가중**으로 합리적 휴리스틱이지만, 최대엔트로피 원리(모멘트 제약 하 H 최대화 → Lagrangian → 지수족)와는 무관하다. 라그랑지안도, 제약식도, 지수족 형태도 없다. → *"MI 기반 중복 보정 가중"* 으로 부르는 게 정직하다.

**(b) "점수 = bits"는 차원상 bits·초이고, 그 전에 bits 의미가 깨진다.**
- `total_bits = trapz(fused, seg_t)` ([fusion.py:133](../engine/fusion.py#L133))는 fused(bits)를 **시간(초)에 대해 적분** → 단위는 **bits·초**. "X bits"라는 헤드라인은 차원이 틀렸다. 부작용: **긴 클립이 기계적으로 높은 점수** → 선택이 길이 쪽으로 편향.
- 게다가 융합 전 `_percentile_scale`([fusion.py:30-48](../engine/fusion.py#L30-L48))가 각 채널을 `clip(ref/p95, 0.25, 4.0)`로 곱한다. −log₂p에 임의의 0.25~4배를 곱하면 **더 이상 self-information(bits)이 아니다.** 주석의 "bits 해석 유지"와 상충. find_peaks 임계값(mean+z·std)도 이 임의 스케일을 그대로 물려받는다.

### 2.3 caveat 있는 것 (🟡)

- **전역 bin edge의 look-ahead**: `running_surprise`가 bin 경계를 시리즈 **전체**의 min/max로 한 번에 계산([infotheory.py:86-89](../engine/infotheory.py#L86-L89)) → 카운트는 인과적이지만 **비닝 격자는 미래 정보를 포함.** "온라인/스트리밍 surprise" 주장과 충돌(순위는 대체로 보존되나 절대 bits·실시간성은 비honored).
- **이중 엔트로피**: `frame_entropy`·`motion`은 이미 엔트로피(bits)인데 여기에 또 `running_surprise(−log p)`를 적용 → "엔트로피의 self-information". 작동은 하나 의미가 모호.
- **이종 채널의 bits 비교 가능성**: spectral(onset)·loudness(dB)·cheer(휴리스틱 곱)는 확률적 의미가 없는 엔지니어링 피처 → 이들의 surprise를 같은 "bits"로 더하는 전제는 약함.
- **NMI 추정기 불일치**: 분자 MI(bins=24, smooth 없음)와 분모 H(X)/H(Y)(`distribution_entropy`, smooth=0.0, 별도 비닝)가 **다른 추정기** → NMI가 1을 넘을 수 있어 clip으로 가림. 이 NMI가 가중치·히트맵 둘 다에 전파.
- **MI 편향**: 고정 bins plug-in MI는 짧은 시리즈에서 양의 편향. `n<8` 가드만 있고 편향 보정 없음 → 독립 채널도 MI>0.
- **under-sampling**: win=6s×3fps=18표본을 32 bins에 → 빈당 평균 <1표본, p̂가 Laplace prior에 지배됨.

---

## 3. 서브시스템별 평가

### 3.1 엔진 — 신호처리 파이프라인
**강점**: 양 모달 모두 상수 메모리 스트리밍(영상 `grab()/retrieve()` 샘플링 + 직전 프레임만 보유, 오디오 15s ffmpeg PCM 윈도) → **1시간+ 주장 실제 성립**. 적응형 검출(mean+z·std, prominence, min-gap), 단계별 진행률 보고.
**약점**: ① **fps 커플링** — `step=round(src_fps/analysis_fps)`이라 실제 샘플레이트는 `src_fps/step`이고, surprise 윈도는 *명목* `analysis_fps`로 계산 → 25fps에서 윈도 실제 길이가 어긋남([video_channel.py:66](../engine/video_channel.py#L66) vs [pipeline.py:79](../engine/pipeline.py#L79)). ② **오디오 15s 하드 경계, 오버랩 없음** + per-window `ref=np.max` dB → 경계마다 불연속 → surprise가 봉합선을 가짜 변화로 읽음. ③ ffmpeg 프리플라이트 없음 — 실패가 `False`/`0.0`로 조용히 강등.

### 3.2 서버 — FastAPI 작업 API
**강점**: 깔끔한 계층 분리(transport/lifecycle/contract), 비차단 작업 제출, 합리적 HTTP 시맨틱(400/404/409), 127.0.0.1 바인딩.
**약점**: → 4장 리스크 감사 참조(critical 2 + high 3 집중 영역). 동시성 무제한, 작업/디스크 정리 없음, 공유 Job 상태 무동기화 읽기.

### 3.3 앱 — Flutter GUI
**강점**: 계층 분리(api/models/state/screens/widgets), **모든 HTTP에 타임아웃 + `detail` 표면화**, 부분/불량 페이로드에 강한 coercion 가드, 좋은 UX 디테일(파일 존재 확인 후 `Image.file`, tabular figures).
**약점**: ① 거대 단일 `ChangeNotifier` + 수동 listener 배선. ② `clipUrl`/`thumbnailUrl` 파싱하지만 미사용 → 원격 재생 불가. ③ 파라미터 기본값이 engine config·Dart model·폼 폴백 **3곳에 중복**, 폼 검증 없음.

### 3.4 문서
**강점**: **코드 대비 충실도 매우 높음**(20여 개 함수/필드/기본값 spot-check 일치), 공식·단위·워크드 예제 구체적, 한계 섹션 솔직(휴리스틱 cheer, total_bits 차원 등 선제 고백), 청중 분리 명확.
**약점**: "fused는 여전히 bits" 다소 과장(§2.2), README의 "60초→하이라이트 3개/12.8초"는 **재현 불가/구버전 의심**(합성 생성기·sample_output·result.json 미커밋, 게다가 12/30/8초 기본값으로 60초에 3개는 빠듯), 거의 모든 수치 예제가 가상(실측 1건도 없음), 환경 버전 표기 불일치(3.13.13 vs 3.10+).

### 3.5 빌드·테스트·설정
**강점**: 존재하는 단위테스트는 의미 있음(수학 항등식·검출/귀속 검증, 무거운 의존성 0), 최근 설치 버그 2건(uvicorn 따옴표·BOM) 근거와 함께 수정, `.gitignore` 철저, pubspec.lock 커밋.
**약점**: → 4장 참조. **엔진 10모듈 중 7개·서버 전체·앱 거의 전부 무테스트, CI 없음, pytest 미포함, requirements 핀 고정/락 없음 + docs/requirements.txt 중복.**

---

## 4. 리스크 & 품질 감사 (우선순위)

> 메인 검토자가 critical/high를 코드로 재확인함. 위치는 `file:line`.

### 🔴 Critical (2)
1. **인증 없는 임의 파일 읽기** — `POST /analyze`가 `video_path`를 `os.path.exists`만 보고 그대로 ffprobe/ffmpeg/cv2에 전달([app.py:68-73](../server/app.py#L68-L73), [jobs.py:44-65](../server/jobs.py#L44-L65)). allowlist·base-dir 봉인 없음 → 서버 프로세스가 읽을 수 있는 임의 절대경로(`/etc/passwd` 등) 접근. **조치**: `realpath`+`commonpath`로 입력 루트에 봉인, 확장자 제한.
2. **와일드카드 CORS + 무인증** — `allow_origins=['*']` 전 메서드/헤더, 토큰 없음([app.py:31-33](../server/app.py#L31-L33)). 127.0.0.1 바인딩이라도 **사용자 브라우저의 임의 웹페이지가** 분석 시작(→#1 파일읽기)·`/jobs` 열람·`/files` 정적 콘텐츠 읽기 가능(CSRF/유출 표면). **조치**: 와일드카드 제거, 세션 토큰 도입.

### 🟠 High (5)
3. **bits 의미 파괴를 bits로 보고** (math-error) — §2.2(b). `_percentile_scale` 임의 스케일이 점수·기여·검출 임계 전체를 오염.
4. **인과 위반: 전역 bin edge** (math-error) — §2.3. "온라인" 주장과 충돌.
5. **무제한 스레드 동시성** (DoS/OOM) — `/analyze`마다 무한 daemon 스레드, 큐·상한·백프레셔 없음([jobs.py:40-51](../server/jobs.py#L40-L51)). **조치**: 경계 워커 풀(데스크톱이면 1~2) + 429.
6. **작업/출력 무한 누적** — `_jobs` 영구 증가 + `out_dir` 디스크 영구 적재, lifespan/정리 없음([jobs.py:37,73-74](../server/jobs.py#L37)). **조치**: LRU 제거+TTL+디렉터리 청소.
7. **ffmpeg/ffprobe 프리플라이트 없음** — 실패가 빈 오디오/`0.0` 길이로 조용히 강등([clipper.py](../engine/clipper.py), [audio_channel.py:138](../engine/audio_channel.py#L138)). **조치**: 시작 시 `-version` 확인, returncode 체크.

### 🟡 Medium (대표)
- surprise 윈도 길이 fps 라운딩 불일치(§3.1①) · 이중 엔트로피 · NMI 추정기 불일치 · 오디오 15s 경계 아티팩트 · Job 상태 무동기화 읽기 · **테스트 커버리지 갭/ CI 부재**.

### 🟢 Low / Info
- 죽은 `enable_cheer_model` 플래그(정의·문서화되나 **코드에서 읽지 않음**, [config.py:48](../engine/config.py#L48)) · requirements 중복/미핀 · 파라미터 기본값 3중 중복 · `clip_url` 미사용 · 오디오 tail 상수 외삽(양성) · 예외 텍스트(경로) 유출.

---

## 5. 권장 로드맵

| 우선순위 | 조치 | 영향 |
|---|---|---|
| P0 | 입력 경로 봉인 + 세션 토큰 + CORS 축소 | critical 2건 해소 |
| P0 | 워커 동시성 상한 + 작업 TTL/정리 + 종료 lifespan | DoS/누수 제거 |
| P1 | ffmpeg 프리플라이트 + 클립 실패 시 stderr 표면화 | 진단성 |
| P1 | 점수 라벨 정정: "bits·초" 또는 시간평균으로 변경, `_percentile_scale`은 시각화 전용으로 분리 | 이론 정직성 회복 |
| P1 | "최대엔트로피" → "MI 기반 중복 보정 가중"으로 문서 표현 정정 | 과장 제거 |
| P2 | running_surprise bin edge를 trailing/expanding 윈도로 → 진짜 인과 | 스트리밍 주장 성립 |
| P2 | pytest 도입 + 파이프라인/서버 통합테스트 + GitHub Actions CI | 회귀 방지 |
| P2 | NMI 분모를 2D 히스토그램 marginal과 동일 추정기로 통일 | 가중치·히트맵 일관성 |
| P3 | requirements 단일화+핀고정, 파라미터 기본값 단일 출처화, `enable_cheer_model` 구현 또는 제거 | 유지보수성 |

---

## 6. 실행 환경 (검증됨)

- **백엔드(engine+server)는 완전 크로스플랫폼.** `requirements.txt`는 순수(토치는 선택·주석). macOS에서 서버 `/health` 200·엔진 e2e(합성영상→클립+썸네일, ffmpeg 컷 포함) 실측 성공.
- **Flutter 앱은 macOS 타깃 추가됨**(이 세션). 변경: `flutter create --platforms=macos`, `media_kit_libs_macos_video` 추가, 샌드박스 해제+`network.client`. macOS 빌드(`✓ Built highlight_studio.app`)·실행·서버연결(`GET /health 200`) 실측 성공. 상세는 인수인계 메모 참조.
- **Windows GUI 빌드**는 `app/windows` 타깃으로 그대로 동작(이 세션 변경의 영향 없음).

## 7. 독립 재실행으로 확인한 검증 상태

| 검증 | 결과 |
|---|---|
| `tests/test_infotheory.py` (5) · `tests/test_fusion.py` (3) | ✅ 전부 PASS (self-info=1bit, 스파이크 검출, 가중치 합=1, MI 행렬) |
| `flutter analyze` | ✅ No issues found |
| 서버 라우트 등록 | ✅ `/health /analyze /jobs/{id} /jobs/{id}/result /ws/{id} /files` 전부 |
| 엔진 end-to-end (macOS) | ✅ 20초 합성영상 → 하이라이트 1개(42.8) + 클립·썸네일, 6.8초 |
| 기여 가법성 | ✅ Σcontrib = total_bits, 오차 0.00e+00 |
| README "60초→3개/12.8초" | ⚠️ 재현 불가/구버전 의심(합성 생성기·산출물 미커밋) |

---

*이 리포트는 [01-theory](01-theory.md)·[02-architecture](02-architecture.md)·[03-explainability](03-explainability.md)와 함께 읽으면 "주장 → 코드 → 검증"의 폐루프가 완성된다.*

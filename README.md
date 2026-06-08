# 🎮 게임 영상 자동 하이라이트 추출 (Highlight Studio)

긴 게임 플레이 영상에서 **의미 있는 순간을 정보이론으로 자동 검출**하는 시스템.
머신러닝 분류기로 "하이라이트다/아니다"를 블랙박스로 판단하는 대신,
Shannon의 **자기정보 `I(x) = -log₂ p(x)`(surprise)** 로 "이 순간이 얼마나 놀라운가"를
**bits 단위로 정량화**해서, *왜* 그 순간이 하이라이트인지 설명한다.

```
영상 ─┬─ 프레임 엔트로피 (공간 복잡도 급변)
      └─ 모션 엔트로피 (옵티컬 플로우)      ┐
                                            ├─▶ surprise(-log p) ─▶ MI 기반
오디오 ┬─ 스펙트럼 변화 (novelty)           │   (채널별 bits)        max-entropy 융합
       ├─ 환호성 (crowd/cheer)              │                       └─▶ fused ─▶ 피크 검출
       └─ 음량 (RMS) 급변                   ┘                            └─▶ 하이라이트 클립 + 설명
```

## 핵심 차별점
- **설명가능**: 각 하이라이트의 점수 = 구간 적분 정보량(bits), 채널별 기여로 분해 → "환호성 3.7 bits + 모션 4.7 bits..."
- **라벨 불필요**: 학습 데이터 없이 정보량만으로 동작 (최대엔트로피 원리로 채널 융합)
- **긴 영상 지원**: 1시간+ 영상도 프레임 샘플링·다운스케일·ffmpeg PCM 스트리밍으로 메모리 상수 처리

## 구성 (3계층)
| 폴더 | 역할 | 기술 |
|---|---|---|
| `engine/` | 정보이론 분석 엔진 (CLI 단독 실행 가능) | NumPy·SciPy·OpenCV·librosa·ffmpeg |
| `server/` | 로컬 API 서버 (작업관리·진행률·정적서빙) | FastAPI·uvicorn·pydantic |
| `app/` | Windows 데스크톱 GUI (대시보드·차트·플레이어) | Flutter·fl_chart·media_kit |
| `docs/` | 발표/제출용 문서 + 인수인계 | — |

## 빠른 시작
```powershell
# 1) 최초 1회 환경 설정 (가상환경 + 의존성)
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1

# 2-A) CLI 로 영상 1개 바로 분석 (서버/GUI 불필요)
powershell -ExecutionPolicy Bypass -File scripts\run_cli.ps1 "C:\게임영상.mp4"
#   → output\게임영상\result.json + clips\*.mp4 + thumbs\*.jpg

# 2-B) 서버 + GUI
powershell -ExecutionPolicy Bypass -File scripts\run_server.ps1   # 터미널 1
cd app; flutter run -d windows                                     # 터미널 2
```
> ⚠️ Flutter 데스크톱 **빌드**는 경로에 아포스트로피(`'`)가 있으면 실패한다. 이 폴더명 `I'mTheBest` 때문에
> `flutter run -d windows` 가 막히므로, **폴더명을 바꾸거나**(`ImTheBest`) **`app/` 만 특수문자 없는 경로로 복사**해 실행할 것.
> (엔진·서버·CLI·`flutter analyze` 는 영향 없음.) 자세한 건 [docs/HANDOVER.md](docs/HANDOVER.md) 참고.

## 검증 상태
- ✅ 단위테스트: `tests/test_infotheory.py`, `tests/test_fusion.py` 통과 (self-information=1bit, 스파이크 검출, MI 행렬)
- ✅ 엔진 end-to-end: 60초 합성영상 → 하이라이트 3개 + 클립/썸네일 생성 (12.8초)
- ✅ 서버 `/health`, 전 라우트 등록 확인
- ✅ Flutter `flutter analyze` 이슈 0건

## 문서
- [docs/01-theory.md](docs/01-theory.md) — 정보이론 배경 (self-info·entropy·MI·최대엔트로피) + 코드 매핑
- [docs/02-architecture.md](docs/02-architecture.md) — 시스템 아키텍처·데이터 흐름·긴 영상 처리 전략
- [docs/03-explainability.md](docs/03-explainability.md) — 설명가능성 방법론 (왜 이 순간인가)
- [docs/04-presentation.md](docs/04-presentation.md) — 발표 슬라이드 아웃라인·데모 시나리오·Q&A
- [docs/05-tuning.md](docs/05-tuning.md) — **튜닝 가이드** (하이라이트 길이·분석 파라미터·설정 이식·알려진 경고)
- [docs/HANDOVER.md](docs/HANDOVER.md) — **인수인계** (다른 PC에서 0부터 실행)

## 요구사항
Python 3.10+ · Flutter 3.x(stable) · **ffmpeg**(PATH 등록) · (선택) NVIDIA GPU + CUDA 12.8 (PyTorch 가속)

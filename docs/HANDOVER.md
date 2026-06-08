# 인수인계 문서 — 게임 영상 자동 하이라이트 추출 엔진

이 문서는 **아무 PC에서도 0부터** 프로젝트를 받아 실행할 수 있도록 작성되었습니다.
기준 OS는 **Windows 11 + PowerShell** 이며, 개발 환경은 Python 3.13.13 입니다.

프로젝트는 정보이론(Shannon self-information / entropy / mutual information) 관점에서
영상·오디오 채널의 "놀라움(surprise)"을 계산·융합하여 하이라이트 구간을 자동 검출하는
**Python 분석 엔진** + **로컬 FastAPI 서버** + **Flutter(Windows) 데스크톱 GUI** 로 구성됩니다.

---

## 1. 사전 요구사항 (Prerequisites)

| 항목 | 버전 / 비고 | 필수 여부 |
|------|-------------|-----------|
| **Python** | 3.10 이상 (개발/검증 환경 3.13.13) | 필수 |
| **Flutter SDK** | 3.x stable (Dart SDK `^3.10.7` 이상) | GUI를 쓸 때 필수 |
| **ffmpeg / ffprobe** | 최신 stable, **PATH 등록 필수** | 필수 (영상/오디오 처리 전부 ffmpeg 위임) |
| **Visual Studio (Desktop C++)** | "Desktop development with C++" 워크로드 | Flutter Windows 빌드 시 필수 |
| **NVIDIA GPU + CUDA 12.8** | RTX 50 시리즈(Blackwell) 등 | 선택 (torch GPU 가속용) |

### ffmpeg 설치 확인
엔진은 `ffmpeg`/`ffprobe` 를 **외부 실행 파일로 직접 호출**합니다
(`engine/clipper.py`, `engine/audio_channel.py`). 둘 다 PATH에 있어야 합니다.

```powershell
ffmpeg -version
ffprobe -version
```

위 두 명령이 버전을 출력하지 않으면 먼저 ffmpeg를 설치하고 PATH에 등록하세요.
(예: `winget install Gyan.FFmpeg` 또는 https://www.gyan.dev/ffmpeg/builds/ 의 빌드를 받아 `bin` 폴더를 PATH에 추가)

### Python / Flutter 설치 확인
```powershell
python --version      # 3.10+ 이어야 함
flutter --version     # GUI를 쓸 경우
flutter doctor        # Windows 빌드 toolchain 점검 (선택)
```

---

## 2. 설치 단계 (Setup)

### 2-1. 저장소 복사
프로젝트 폴더 전체(`I'mTheBest`)를 대상 PC로 복사합니다.

> 주의: 기존 `.venv` 폴더는 **복사하지 마세요**. 가상환경은 PC마다 경로가 박혀 있어
> 다른 PC에서 재사용하면 깨집니다. `.venv` 는 아래 setup 스크립트가 새로 만듭니다.
> 마찬가지로 `app/.dart_tool`, `app/build` 도 복사 대상이 아닙니다(재생성됨).

### 2-2. Python 가상환경 + 의존성 설치 (필수)
프로젝트 루트에서:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
```

`scripts/setup.ps1` 이 하는 일:
1. `.venv` 가상환경 생성 (`python -m venv .venv`)
2. `.venv` 의 pip 업그레이드
3. 루트 `requirements.txt` 의 의존성 설치
   (numpy, scipy, opencv-python, librosa, soundfile, fastapi, uvicorn[standard], pydantic, python-multipart, websockets)

완료되면 GPU torch 설치 명령을 안내(출력)만 하고 끝납니다. (자동 설치하지 않음)

### 2-3. (선택) PyTorch GPU 설치
torch는 **선택**입니다. 설치하지 않아도 엔진은 휴리스틱 폴백으로 전체가 동작합니다
(학습형 환호성 분류기만 비활성). GPU 가속을 원할 때만:

```powershell
# NVIDIA GPU (CUDA 12.8 / RTX 50 · Blackwell)
.\.venv\Scripts\python.exe -m pip install torch --index-url https://download.pytorch.org/whl/cu128

# CPU 전용 torch (GPU 없이 torch만 쓰고 싶을 때)
.\.venv\Scripts\python.exe -m pip install torch --index-url https://download.pytorch.org/whl/cpu
```

### 2-4. Flutter 의존성 (GUI를 쓸 때만)
```powershell
cd app
flutter pub get
```

---

## 3. 실행 (Run)

엔진은 **3가지 경로**로 사용할 수 있습니다. GUI는 백엔드 서버가 떠 있어야 합니다.

### (A) 로컬 서버 실행 — Flutter GUI의 백엔드
```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_server.ps1
```
- `scripts/run_server.ps1` 은 `HL_PORT=8000` 으로 설정한 뒤 `python -m server.app` 을 실행합니다.
- 주소: **http://127.0.0.1:8000** (호스트는 `127.0.0.1` 로 고정, 포트는 `HL_PORT`)
- 종료: `Ctrl + C`
- `.venv` 가 없으면 "먼저 scripts\setup.ps1 을 실행하세요" 메시지 후 종료합니다.

제공 엔드포인트 (`server/app.py`):

| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/health` | 서버/Python/GPU(torch·cuda)/opencv/librosa 상태 |
| POST | `/analyze` | 분석 시작 → `{ "job_id": "..." }` |
| GET | `/jobs/{id}` | 작업 상태(+완료 시 결과) |
| GET | `/jobs/{id}/result` | 완료된 결과(AnalysisResult) |
| WS | `/ws/{id}` | 진행률 실시간 스트림 |
| GET | `/files/...` | 생성된 클립/썸네일 정적 서빙 (`HL_OUTPUT_DIR` 기준) |

서버를 uvicorn으로 직접 띄우는 것도 가능합니다(동등):
```powershell
.\.venv\Scripts\python.exe -m uvicorn server.app:app --host 127.0.0.1 --port 8000
```

### (B) Flutter 데스크톱 앱 실행
**먼저 (A) 서버를 띄운 상태**에서, 별도 터미널에서:
```powershell
cd app
flutter run -d windows
```
- 패키지명: `highlight_studio` (`app/pubspec.yaml`)
- 주요 의존성: `http`, `fl_chart`, `intl`, `media_kit` / `media_kit_video` / `media_kit_libs_windows_video`(영상 재생), `file_selector`(파일 선택)
- 앱은 로컬 서버(기본 `http://127.0.0.1:8000`)에 접속해 분석을 요청하고 진행률·결과를 표시합니다. 앱 화면 상단에서 서버 URL을 직접 바꿀 수 있습니다.

> ⚠️ **중요 — 폴더 경로에 특수문자(아포스트로피 ' 등) 금지.**
> Flutter의 Windows 빌드(CMake/MSBuild)는 경로에 `' # ! $ ^ & * = | , ; < > ?` 문자가 있으면
> `flutter build windows` / `flutter run -d windows` 가 실패합니다.
> 이 프로젝트 폴더명 `I'mTheBest` 에는 아포스트로피가 있어 **현재 위치에서는 데스크톱 앱 빌드가 불가**합니다.
> (단, `flutter analyze` · `flutter pub get` · Python 엔진/서버/CLI 는 영향 없이 정상 동작합니다.)
> 해결책 — 둘 중 하나:
> 1. 워크스페이스 폴더명을 아포스트로피 없이 변경 (예: `ImTheBest`). 가장 깔끔하며 모든 게 그대로 동작.
> 2. `app/` 폴더만 특수문자 없는 경로(예: `C:\dev\highlight_app`)로 복사해 거기서 `flutter run -d windows`.
>    엔진/서버는 원래 위치에서 그대로 돌리고, GUI만 다른 경로에서 띄워 `http://127.0.0.1:8000` 에 접속하면 됩니다.

> 참고 1 (첫 빌드 다운로드): 첫 Windows 빌드 시 `media_kit_libs_windows_video` 가 mpv·ANGLE 네이티브
> 바이너리(.7z)를 GitHub 릴리스에서 자동 다운로드합니다. "Integrity check failed, please try to re-build"
> 오류가 나면 일시적 다운로드 문제이니 `build` 폴더를 지우고 다시 실행하거나, 네트워크를 확인하세요.
> (참고로 이 두 아카이브의 MD5: mpv=`a832ef24b3a6ff97cd2560b5b9d04cd8`, ANGLE=`e866f13e8d552348058afaafe869b1ed`)
>
> 참고 2 (개발 시엔 `flutter run` 권장): 본 프로젝트는 `flutter analyze` 0건이며 실제로 컴파일·링크되어
> `build\windows\x64\runner\Debug\highlight_studio.exe` 가 생성됨을 확인했습니다. 다만 매우 최신 CMake
> (VS Build Tools 2022 17.14+ 동봉)에서 `flutter build windows` 의 마지막 **INSTALL 패키징 단계가
> MSB3073 으로 실패**할 수 있습니다(media_kit 1.0.11 의 CMake 스크립트 ↔ CMP0175 정책 마찰, exe 생성
> *이후* 단계라 실행 파일 자체는 만들어짐). 개발/실행은 `flutter run -d windows` 를 쓰면 이 단계를 거치지
> 않아 정상 동작합니다. 배포용 빌드가 꼭 필요하면 media_kit 상위 버전으로 올리거나 CMake 버전을 낮추세요.

### (C) CLI 실행 — 서버/GUI 없이 영상 1개 직접 분석
```powershell
# 기본 (출력 폴더 자동: output\<영상이름>)
powershell -ExecutionPolicy Bypass -File scripts\run_cli.ps1 "C:\path\game.mp4"

# 출력 폴더 지정
powershell -ExecutionPolicy Bypass -File scripts\run_cli.ps1 "C:\path\game.mp4" "C:\out\game1"
```
`scripts/run_cli.ps1` 은 내부적으로 `python -m engine.cli` 를 호출합니다.
`engine.cli` 를 직접 실행하면 더 많은 옵션을 쓸 수 있습니다:

```powershell
.\.venv\Scripts\python.exe -m engine.cli "C:\path\game.mp4" -o output\game1 --fps 3 --top-k 10
.\.venv\Scripts\python.exe -m engine.cli "C:\path\game.mp4" --no-reencode    # 빠른 copy 컷
```

CLI 옵션(`engine/cli.py`):

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `video` (위치인자) | 입력 영상 경로 | (필수) |
| `-o, --out` | 출력 폴더 | `output\<영상이름>` |
| `--fps` | 분석 프레임/초(샘플링 레이트) | 3.0 |
| `--width` | 분석 다운스케일 가로폭(px) | 256 |
| `--top-k` | 최대 하이라이트 수 | 12 |
| `--min-gap` | 하이라이트 간 최소 간격(초) | 8.0 |
| `--peak-z` | 피크 임계 z (mean + z·std) | 1.2 |
| `--no-reencode` | 재인코딩 없이 빠른 copy 컷 | off(=재인코딩) |
| `--no-thumb` | 썸네일 생략 | off(=썸네일 생성) |

CLI 산출물: `<out>\result.json`, `<out>\clips\*.mp4`, `<out>\thumbs\*.jpg`

> 처리량 핵심 손잡이는 `--fps` 와 `--width` 입니다. 예) 1시간 30fps 영상 = 108,000 프레임이지만
> `--fps 3 --width 256` 이면 실제로 다루는 건 약 10,800개의 작은 프레임뿐이라 매우 빠릅니다.

---

## 4. 폴더 구조

```
I'mTheBest\
├─ engine\                # 분석 엔진 (순수 Python, 서버 의존 없음)
│   ├─ __init__.py        # 진입점: analyze, AnalysisParams 등 export
│   ├─ config.py          # AnalysisParams 기본값 · 채널 정의(CHANNELS 등)
│   ├─ models.py          # pydantic 데이터 모델(AnalysisResult, Highlight, JobStatus 등)
│   ├─ infotheory.py      # 정보이론 핵심(entropy, self-information, MI ...)
│   ├─ video_channel.py   # 영상 채널: 프레임 엔트로피 · 옵티컬 플로우 모션
│   ├─ audio_channel.py   # 오디오 채널: ffmpeg PCM 스트리밍 → 스펙트럼/음량/환호성
│   ├─ fusion.py          # 채널 융합 + 적응형 피크 검출
│   ├─ clipper.py         # ffmpeg/ffprobe 로 클립 컷 · 썸네일 · 길이 probe
│   ├─ pipeline.py        # 전체 파이프라인 오케스트레이션(analyze)
│   └─ cli.py             # CLI 진입점 (python -m engine.cli)
│
├─ server\                # 로컬 FastAPI 서버 (GUI 백엔드)
│   ├─ app.py             # FastAPI 앱 · 엔드포인트 · main()(python -m server.app)
│   └─ jobs.py            # JobManager: 백그라운드 스레드로 analyze 실행 · 진행률 관리
│
├─ app\                   # Flutter(Windows) 데스크톱 GUI (highlight_studio)
│   ├─ lib\main.dart      # 앱 진입점
│   ├─ pubspec.yaml       # Flutter 의존성
│   ├─ windows\           # Windows 러너
│   └─ test\
│
├─ tests\                 # Python 단위테스트 (pytest 스타일 함수)
│   ├─ test_infotheory.py
│   └─ test_fusion.py
│
├─ scripts\               # 운영 스크립트 (PowerShell)
│   ├─ setup.ps1          # venv 생성 + 의존성 설치
│   ├─ run_server.ps1     # 서버 실행 (HL_PORT=8000)
│   └─ run_cli.ps1        # CLI 래퍼
│
├─ docs\                  # 문서 (이 파일 + 튜닝 가이드 + requirements.txt 사본)
│   ├─ HANDOVER.md
│   ├─ 05-tuning.md       # 하이라이트 길이·분석 파라미터 튜닝 + 설정 이식 + 알려진 경고
│   └─ requirements.txt   # 루트 requirements.txt 와 동일(자급자족용)
│
├─ output\                # 실행 산출물(작업별 폴더, 클립/썸네일/result.json)
├─ sample_output\         # 예시 산출물 보관용
└─ requirements.txt       # Python 의존성 (정본)
```

---

## 5. 환경변수

| 변수 | 의미 | 기본값 | 설정 위치 |
|------|------|--------|-----------|
| `HL_PORT` | 서버 리슨 포트 | `8000` | `scripts/run_server.ps1` 에서 8000 으로 설정. `server/app.py`의 `main()`이 읽음 |
| `HL_OUTPUT_DIR` | 산출물(클립/썸네일/result.json) 기본 출력 디렉터리 | `<실행 위치>\output` 의 절대경로 | `server/app.py` 가 읽고 `/files` 정적 서빙 루트로 사용 |

직접 변경 예:
```powershell
$env:HL_PORT = "8080"
$env:HL_OUTPUT_DIR = "D:\highlights_out"
.\.venv\Scripts\python.exe -m server.app
```
> 포트를 바꾸면 GUI/클라이언트가 접속하는 베이스 URL도 같은 포트로 맞춰야 합니다.

---

## 6. 트러블슈팅

### 6-1. ffmpeg / ffprobe 를 찾을 수 없음
증상: 분석이 즉시 실패하거나 영상 길이가 0, 오디오 채널 결과가 비어 있음.
- `ffmpeg -version`, `ffprobe -version` 이 둘 다 동작하는지 확인.
- 설치 후에는 **새 PowerShell 창**을 열어야 PATH가 반영됩니다.
- ffmpeg는 단순 라이브러리가 아니라 **외부 실행파일**로 호출되므로 pip로는 해결되지 않습니다.

### 6-2. opencv-python / librosa 설치 실패
- 먼저 pip와 빌드 도구를 최신화: `.\.venv\Scripts\python.exe -m pip install --upgrade pip setuptools wheel`
- `librosa` 는 내부적으로 `numba`/`soundfile` 등을 끌어옵니다. Python 버전이 너무 최신/예전이면 휠이 없을 수 있으니 3.10~3.13 범위인지 확인.
- 휠 빌드가 막히면 네트워크/프록시로 PyPI 접근이 되는지 확인(사내망 등).
- `opencv-python` 이 import 시 DLL 오류면 Microsoft Visual C++ 재배포 패키지(x64)를 설치.
- 설치 검증: `.\.venv\Scripts\python.exe -c "import cv2, librosa; print(cv2.__version__, librosa.__version__)"`

### 6-3. media_kit (Flutter 영상 재생) 빌드 문제
- `media_kit_libs_windows_video` 가 의존성에 포함되어 있어야 네이티브 코덱이 따라옵니다(`app/pubspec.yaml`에 포함됨).
- Windows 데스크톱 빌드에는 **Visual Studio "Desktop development with C++"** 워크로드가 필요합니다(`flutter doctor` 로 확인).
- 빌드가 꼬이면 `app` 폴더에서 정리 후 재시도:
  ```powershell
  cd app
  flutter clean
  flutter pub get
  flutter run -d windows
  ```

### 6-4. 8000 포트 충돌 (Address already in use)
- 다른 프로세스가 8000을 점유 중인 경우입니다. 점유 프로세스 확인:
  ```powershell
  Get-NetTCPConnection -LocalPort 8000 -State Listen | Select-Object OwningProcess
  Get-Process -Id <PID>
  ```
- 해결: 점유 프로세스를 종료하거나, 다른 포트로 서버를 실행:
  ```powershell
  $env:HL_PORT = "8001"; .\.venv\Scripts\python.exe -m server.app
  ```
  (이때 클라이언트/GUI 베이스 URL도 8001로 변경)

### 6-5. 한글 / 공백이 들어간 경로
- CLI/서버에 영상 경로를 줄 때 **반드시 큰따옴표로 감싸세요**:
  `... "C:\내 영상\게임 클립.mp4"`
- 콘솔 한글 깨짐(예: 진행바/한글 라벨)이 보이면 UTF-8 코드페이지로 전환:
  ```powershell
  chcp 65001
  ```
- 가능하면 프로젝트 자체는 한글·공백이 적은 경로(예: `C:\work\...`)에 두는 것이 안전합니다.

### 6-6. GPU(CUDA)가 인식되지 않음
- 먼저 torch가 설치돼 있는지, CUDA 빌드인지 확인:
  ```powershell
  .\.venv\Scripts\python.exe -c "import torch; print(torch.__version__, torch.cuda.is_available())"
  ```
- `False` 이면: (1) CPU 휠을 설치했거나, (2) NVIDIA 드라이버가 CUDA 12.8을 지원하지 않거나, (3) GPU가 없는 경우입니다.
- GPU 휠 재설치:
  ```powershell
  .\.venv\Scripts\python.exe -m pip uninstall -y torch
  .\.venv\Scripts\python.exe -m pip install torch --index-url https://download.pytorch.org/whl/cu128
  ```
- GPU가 안 잡혀도 **엔진은 정상 동작**합니다(휴리스틱 폴백). 서버 `/health` 의 `cuda` 값으로 현재 상태를 확인할 수 있습니다.

### 6-7. "가상환경이 없습니다" / `.venv` 누락
- `run_server.ps1`·`run_cli.ps1` 이 `.\.venv\Scripts\python.exe` 를 찾지 못하면 출력되는 메시지입니다.
- 해결: `scripts\setup.ps1` 을 먼저 실행. (다른 PC에서 복사해 온 `.venv` 는 깨지므로 삭제 후 재생성)

### 6-8. PowerShell 실행 정책으로 스크립트가 막힘
- 모든 스크립트는 `-ExecutionPolicy Bypass` 와 함께 호출하도록 안내되어 있습니다:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
  ```

---

## 7. 빠른 점검 (Smoke Test)

### 7-1. 단위테스트
`tests\` 의 테스트는 pytest 스타일 함수이며, `sys.path` 를 스스로 보정하므로 어느 위치에서 실행해도 됩니다.
pytest는 `requirements.txt` 에 포함돼 있지 **않으므로**(런타임 불필요) 먼저 설치해야 합니다:

```powershell
.\.venv\Scripts\python.exe -m pip install pytest
.\.venv\Scripts\python.exe -m pytest -q
```

pytest 설치 없이 핵심 모듈만 빠르게 확인하려면(개별 테스트 함수 직접 호출):
```powershell
.\.venv\Scripts\python.exe -c "import tests.test_infotheory as t; t.test_self_information_bits(); t.test_shannon_entropy_bounds(); print('infotheory OK')"
```

### 7-2. 서버 헬스 체크
서버를 띄운 뒤(섹션 3-A), 다른 터미널에서:
```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```
정상이면 대략 다음과 같은 JSON이 반환됩니다:
```json
{
  "status": "ok",
  "python": "3.13.13",
  "output_dir": "C:\\...\\output",
  "torch": null,          // torch 미설치 시 null
  "cuda": false,          // GPU 가속 가능 여부
  "device": "cpu",
  "opencv": "4.x.x",
  "librosa": "0.10.x"
}
```
- `opencv`/`librosa` 가 `null` 이면 해당 패키지 설치가 실패한 것 → 섹션 6-2 참고.
- `cuda` 가 `true` 면 GPU 가속이 활성화된 상태입니다.

### 7-3. 엔드투엔드(선택)
실제 영상으로 CLI를 한 번 돌려보면 ffmpeg·opencv·librosa·엔진이 한 번에 검증됩니다:
```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_cli.ps1 "C:\path\game.mp4"
```
완료 후 `output\game\result.json` 과 `output\game\clips\*.mp4` 가 생성되면 정상입니다.

---

## 8. 메모 (인수자 참고)

- **엔진은 서버/GUI와 독립**입니다. `from engine import analyze, AnalysisParams` 로 파이썬 코드에서 바로 호출 가능.
- 서버는 분석을 **백그라운드 스레드**로 돌리고(`server/jobs.py`), 진행률을 REST(`/jobs/{id}`) 와 WebSocket(`/ws/{id}`) 로 노출합니다.
- 산출물은 `HL_OUTPUT_DIR` 아래 **작업ID 폴더**로 떨어지며, 클립/썸네일은 `/files/...` 로 정적 서빙됩니다.
- torch는 어디까지나 **선택 가속기**입니다. 없으면 휴리스틱 환호성 검출로 폴백하므로 결과 산출 자체는 막히지 않습니다.
- 의존성 정본은 루트 `requirements.txt` 이며, `docs\requirements.txt` 는 그 **동일 사본**(docs만으로 자급자족용)입니다. 둘을 함께 갱신하세요.

# 최초 1회 환경 설정: 가상환경 생성 + 의존성 설치
# 사용법:  powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "[1/3] 가상환경(.venv) 생성..." -ForegroundColor Cyan
if (-not (Test-Path ".venv")) { python -m venv .venv }

$py = ".\.venv\Scripts\python.exe"
Write-Host "[2/3] pip 업그레이드 + 필수 패키지 설치..." -ForegroundColor Cyan
& $py -m pip install --upgrade pip
& $py -m pip install -r requirements.txt

Write-Host "[3/3] (선택) PyTorch GPU 설치를 원하면 아래를 실행:" -ForegroundColor Yellow
Write-Host '    .\.venv\Scripts\python.exe -m pip install torch --index-url https://download.pytorch.org/whl/cu128'
Write-Host ""
Write-Host "완료! 서버 실행:  powershell -ExecutionPolicy Bypass -File scripts\run_server.ps1" -ForegroundColor Green

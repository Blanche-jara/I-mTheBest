# 분석 엔진 로컬 서버 실행 (Flutter GUI 가 접속하는 백엔드)
# 사용법:  powershell -ExecutionPolicy Bypass -File scripts\run_server.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$py = ".\.venv\Scripts\python.exe"
if (-not (Test-Path $py)) {
    Write-Host "가상환경이 없습니다. 먼저 scripts\setup.ps1 을 실행하세요." -ForegroundColor Red
    exit 1
}
$env:HL_PORT = "8000"
Write-Host "서버 시작: http://127.0.0.1:8000  (Ctrl+C 로 종료)" -ForegroundColor Green
& $py -m server.app

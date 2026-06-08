# CLI 로 영상 1개를 직접 분석 (서버/GUI 없이)
# 사용법:  powershell -ExecutionPolicy Bypass -File scripts\run_cli.ps1 "C:\path\game.mp4"
param([Parameter(Mandatory=$true)][string]$Video, [string]$Out = "")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$py = ".\.venv\Scripts\python.exe"
if (-not (Test-Path $py)) { Write-Host "먼저 scripts\setup.ps1 실행" -ForegroundColor Red; exit 1 }
if ($Out -eq "") { & $py -m engine.cli $Video } else { & $py -m engine.cli $Video -o $Out }

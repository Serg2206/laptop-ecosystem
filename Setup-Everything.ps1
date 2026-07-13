<#
.SYNOPSIS
    Установка экосистемы ноутбука одной командой: клонирование, разблокировка скриптов,
    автодиагностика, первый запуск.

.DESCRIPTION
    Работает в двух режимах:

    1) Bootstrap (запуск через iwr | iex с главной страницы витрины):
       iwr -useb https://raw.githubusercontent.com/Serg2206/laptop-ecosystem/main/Setup-Everything.ps1 | iex
       — клонирует репозиторий в ~\laptop-ecosystem (или обновляет существующий)
       и продолжает установку из клона.

    2) Локальный (запуск из клона репозитория):
       .\Setup-Everything.ps1
       — пропускает клонирование, сразу настраивает.

    Шаги установки:
    - Проверка требований: PowerShell 5.1+, git (для bootstrap)
    - Разблокировка скриптов (Unblock-File — снятие Zone.Identifier)
    - Предложение зарегистрировать еженедельную автодиагностику (Task Scheduler)
    - Первая диагностика Test-LaptopHealth с экспортом отчёта
    - Запуск Command Center

.PARAMETER InstallPath
    Куда клонировать в bootstrap-режиме. По умолчанию: ~\laptop-ecosystem

.PARAMETER NoPrompt
    Без вопросов: клонировать/обновить, разблокировать, выполнить диагностику.
    Задачу в Scheduler в этом режиме НЕ регистрирует и Command Center не запускает.

.PARAMETER SkipDiagnostics
    Не запускать первую диагностику.

.EXAMPLE
    .\Setup-Everything.ps1
    .\Setup-Everything.ps1 -NoPrompt -SkipDiagnostics
#>
param (
    [string]$InstallPath = (Join-Path $HOME 'laptop-ecosystem'),
    [switch]$NoPrompt,
    [switch]$SkipDiagnostics
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Msg); Write-Host ""; Write-Host "  ▶ $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg); Write-Host "    ✅ $Msg" -ForegroundColor Green }
function Write-Warn2 { param([string]$Msg); Write-Host "    ⚠️  $Msg" -ForegroundColor Yellow }

function Read-YesNo {
    param([string]$Question, [bool]$Default = $true)
    if ($NoPrompt) { return $Default }
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    Write-Host "  $Question ${hint}: " -ForegroundColor Yellow -NoNewline
    $ans = (Read-Host).Trim()
    if ($ans -eq '') { return $Default }
    return $ans -match '^[YyДд]'
}

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "  ║      ЭКОСИСТЕМА НОУТБУКА — Setup-Everything                ║" -ForegroundColor Magenta
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

# ── Требования ──────────────────────────────────────────────────
Write-Step "Проверка требований"
if ($PSVersionTable.PSVersion.Major -lt 5) { throw "Требуется PowerShell 5.1+, найден $($PSVersionTable.PSVersion)" }
Write-Ok "PowerShell $($PSVersionTable.PSVersion)"
$isWindowsOS = $PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows
if (-not $isWindowsOS) { Write-Warn2 "Не Windows: планировщик и часть диагностики будут недоступны" }

# ── Режим: локальный или bootstrap ─────────────────────────────
# $PSScriptRoot пуст при запуске через iwr | iex
$root = $null
if ($PSScriptRoot -and (Test-Path (Join-Path (Join-Path $PSScriptRoot 'scripts') 'Test-LaptopHealth.ps1'))) {
    $root = $PSScriptRoot
    Write-Ok "Локальный режим: $root"
} else {
    Write-Step "Bootstrap: получение репозитория"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git не найден. Установите: winget install Git.Git — и повторите."
    }
    if (Test-Path (Join-Path $InstallPath '.git')) {
        Write-Ok "Репозиторий уже есть: $InstallPath — обновляю (git pull)"
        git -C $InstallPath pull --ff-only 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    } else {
        Write-Ok "Клонирую в $InstallPath"
        git clone https://github.com/Serg2206/laptop-ecosystem.git $InstallPath 2>&1 |
            ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
    if (-not (Test-Path (Join-Path (Join-Path $InstallPath 'scripts') 'Test-LaptopHealth.ps1'))) {
        throw "Клонирование не удалось: не найден $InstallPath\scripts\Test-LaptopHealth.ps1"
    }
    $root = $InstallPath
}
$scripts = Join-Path $root 'scripts'

# ── Разблокировка скриптов ──────────────────────────────────────
Write-Step "Разблокировка скриптов (Zone.Identifier)"
try {
    Get-ChildItem $root -Recurse -Filter '*.ps1' | Unblock-File -ErrorAction Stop
    Write-Ok "Скрипты разблокированы"
} catch { Write-Warn2 "Unblock-File недоступен — пропущено" }

# ── Автодиагностика (Task Scheduler) ────────────────────────────
if ($isWindowsOS -and -not $NoPrompt) {
    Write-Step "Автодиагностика"
    if (Read-YesNo "Зарегистрировать еженедельную автодиагностику (Пн 09:00, отчёты в OneDrive)?") {
        & (Join-Path $scripts 'Register-HealthCheckTask.ps1')
    } else { Write-Warn2 "Пропущено. Позже: .\scripts\Register-HealthCheckTask.ps1 или пункт [A] в Command Center" }
}

# ── Первая диагностика ──────────────────────────────────────────
if (-not $SkipDiagnostics) {
    Write-Step "Первая диагностика ноутбука"
    if ($NoPrompt -or (Read-YesNo "Запустить диагностику сейчас (~1 мин)?")) {
        & (Join-Path $scripts 'Test-LaptopHealth.ps1') -Export
    }
}

# ── Финал ───────────────────────────────────────────────────────
Write-Step "Установка завершена"
Write-Ok "Экосистема: $root"
Write-Host ""
Write-Host "  Дальше:" -ForegroundColor Cyan
Write-Host "    • Command Center:  .\scripts\New-CommandCenter.ps1" -ForegroundColor Gray
Write-Host "    • Диагностика:     .\scripts\Test-LaptopHealth.ps1 -Full -Export" -ForegroundColor Gray
Write-Host "    • Оптимизация:     .\scripts\Optimize-Laptop.ps1 -WhatIf" -ForegroundColor Gray
Write-Host "    • Витрина Health:  webapp — npm install; npm run dev" -ForegroundColor Gray
Write-Host ""

if ($isWindowsOS -and -not $NoPrompt) {
    if (Read-YesNo "Открыть Command Center сейчас?") {
        Set-Location $root
        & (Join-Path $scripts 'New-CommandCenter.ps1')
    }
}

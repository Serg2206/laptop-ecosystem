#requires -Version 5.1
<#
.SYNOPSIS
    Регистрирует задачу Task Scheduler для автоматической диагностики ноутбука (Test-LaptopHealth.ps1).

.DESCRIPTION
    Создаёт задачу "MS365-LaptopHealth" (префикс MS365 — задача видна в меню
    Task Scheduler Command Center'а). По расписанию запускает Test-LaptopHealth.ps1
    с экспортом JSON + HTML отчётов.

    По умолчанию: еженедельно, понедельник 09:00, отчёты в OneDrive\LaptopHealth
    (если OneDrive настроен — отчёты синхронизируются и доступны с любого устройства;
    иначе — папка reports репозитория).

    Задача запускается и от батареи, а пропущенный запуск (ноутбук был выключен)
    выполняется при первой возможности (StartWhenAvailable).

.PARAMETER Time
    Время запуска в формате HH:mm. По умолчанию: 09:00

.PARAMETER DayOfWeek
    День недели для еженедельного запуска. По умолчанию: Monday

.PARAMETER Daily
    Запускать ежедневно вместо еженедельного расписания.

.PARAMETER ReportPath
    Папка для отчётов. По умолчанию: OneDrive\LaptopHealth или ..\reports

.PARAMETER Full
    Запускать диагностику в расширенном режиме (стресс-проба CPU, замер диска).

.PARAMETER RunNow
    Сразу после регистрации выполнить задачу для проверки.

.PARAMETER Unregister
    Удалить задачу и выйти.

.EXAMPLE
    .\Register-HealthCheckTask.ps1
    .\Register-HealthCheckTask.ps1 -Daily -Time 08:30 -Full
    .\Register-HealthCheckTask.ps1 -RunNow
    .\Register-HealthCheckTask.ps1 -Unregister
#>
[CmdletBinding()]
param (
    [ValidatePattern('^\d{1,2}:\d{2}$')][string]$Time = '09:00',
    [ValidateSet('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')][string]$DayOfWeek = 'Monday',
    [switch]$Daily,
    [string]$ReportPath,
    [switch]$Full,
    [switch]$RunNow,
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'
$TaskName = 'MS365-LaptopHealth'

if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    Write-Error 'Скрипт работает только на Windows: требуется Task Scheduler.'
    exit 1
}
if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    Write-Error 'Командлеты ScheduledTasks недоступны. Требуется Windows 8/Server 2012 или новее.'
    exit 1
}

function Write-Info { param([string]$Msg, [string]$Color = 'Cyan'); Write-Host "  $Msg" -ForegroundColor $Color }

# ── Удаление ────────────────────────────────────────────────────
if ($Unregister) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Info "✅ Задача '$TaskName' удалена" 'Green'
    } else {
        Write-Info "ℹ️  Задача '$TaskName' не найдена — удалять нечего" 'Yellow'
    }
    exit 0
}

# ── Пути ────────────────────────────────────────────────────────
$healthScript = Join-Path $PSScriptRoot 'Test-LaptopHealth.ps1'
if (-not (Test-Path $healthScript)) { Write-Error "Не найден Test-LaptopHealth.ps1 рядом со скриптом: $healthScript"; exit 1 }
$healthScript = (Resolve-Path $healthScript).Path

if (-not $ReportPath) {
    $ReportPath = if ($env:OneDrive -and (Test-Path $env:OneDrive)) { Join-Path $env:OneDrive 'LaptopHealth' }
                  else { Join-Path (Split-Path $PSScriptRoot -Parent) 'reports' }
}
if (-not (Test-Path $ReportPath)) { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
$ReportPath = (Resolve-Path $ReportPath).Path

# ── Действие, расписание, настройки ─────────────────────────────
$psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$healthScript`" -Export -ReportPath `"$ReportPath`""
if ($Full) { $psArgs += ' -Full' }
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs

$trigger = if ($Daily) { New-ScheduledTaskTrigger -Daily -At $Time }
           else { New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $Time }

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -MultipleInstances IgnoreNew

$description = "Автодиагностика ноутбука (Test-LaptopHealth.ps1). Отчёты JSON+HTML: $ReportPath. Часть экосистемы laptop-ecosystem."

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description $description -Force | Out-Null

$schedStr = if ($Daily) { "ежедневно в $Time" } else { "еженедельно, $DayOfWeek в $Time" }
Write-Host ""
Write-Info "✅ Задача '$TaskName' зарегистрирована" 'Green'
Write-Info "   Расписание: $schedStr"
Write-Info "   Скрипт:     $healthScript"
Write-Info "   Отчёты:     $ReportPath"
Write-Info "   Режим:      $(if ($Full) { 'Full (стресс-проба, замер диска)' } else { 'стандартный' })"

$info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
if ($info -and $info.NextRunTime) { Write-Info "   След. запуск: $($info.NextRunTime)" }

if ($RunNow) {
    Write-Host ""
    Write-Info "🚀 Пробный запуск..." 'Yellow'
    Start-ScheduledTask -TaskName $TaskName
    # Ждём завершения (State: Running -> Ready), максимум 3 минуты
    $deadline = (Get-Date).AddMinutes(3)
    do { Start-Sleep -Seconds 5; $state = (Get-ScheduledTask -TaskName $TaskName).State } while ($state -eq 'Running' -and (Get-Date) -lt $deadline)
    $result = (Get-ScheduledTaskInfo -TaskName $TaskName).LastTaskResult
    if ($result -eq 0) {
        Write-Info "✅ Пробный запуск успешен. Свежий отчёт:" 'Green'
        Get-ChildItem $ReportPath -Filter 'laptop-health-*.html' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { Write-Info "   $($_.FullName)" }
    } else {
        Write-Info "⚠️  Код завершения: $result (0x$('{0:X}' -f $result)). Проверьте журнал Task Scheduler." 'Yellow'
    }
}
Write-Host ""

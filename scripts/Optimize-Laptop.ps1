#requires -Version 5.1
<#
.SYNOPSIS
    Безопасная оптимизация ноутбука: очистка, кэши, автозагрузка, питание, TRIM.

.DESCRIPTION
    Оптимизирует работу ноутбука по принципу "сначала покажи, потом делай":
    поддерживает -WhatIf (предпросмотр без изменений) для всех операций удаления.

    СТАНДАРТНЫЙ РЕЖИМ (безопасно, без прав администратора):
    - Временные файлы: %TEMP% и C:\Windows\Temp старше -OlderThanDays (по умолч. 7)
    - Кэш DNS: сброс (ipconfig /flushdns)
    - Автозагрузка: аудит программ (реестр Run + папки Startup) — только отчёт
    - Питание: активная схема + рекомендации — только отчёт
    - Топ процессов по памяти — только отчёт

    РЕЖИМ -Deep (запускать от администратора):
    - Корзина: полная очистка
    - Кэш Windows Update: SoftwareDistribution\Download
    - TRIM для SSD / дефрагментация HDD (Optimize-Volume)

    Итог: сколько места освобождено по каждой категории и всего.
    Скрипт НЕ трогает: браузерные профили, документы, реестр, службы,
    файл гибернации, точки восстановления.

.PARAMETER OlderThanDays
    Удалять временные файлы старше N дней. По умолчанию: 7. 0 = все.

.PARAMETER Deep
    Расширенная очистка: корзина, кэш Windows Update, TRIM/дефрагментация.

.PARAMETER Export
    Сохранить итоги в JSON (папка reports).

.EXAMPLE
    .\Optimize-Laptop.ps1 -WhatIf     # предпросмотр: что будет удалено
    .\Optimize-Laptop.ps1             # безопасная очистка
    .\Optimize-Laptop.ps1 -Deep      # полная (от администратора)
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [ValidateRange(0, 365)][int]$OlderThanDays = 7,
    [switch]$Deep,
    [switch]$Export,
    [string]$ReportPath = (Join-Path $PSScriptRoot ".." "reports")
)

$ErrorActionPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    Write-Warning 'Скрипт предназначен для Windows.'
}
$script:FreedBytes = 0
$script:Summary = [ordered]@{ GeneratedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Computer = $env:COMPUTERNAME; WhatIf = [bool]$WhatIfPreference; Deep = [bool]$Deep; Categories = [ordered]@{} }

function Write-StatusLine {
    param([string]$Label, [string]$Value, [ValidateSet('OK','WARN','ERROR','INFO','SKIP')][string]$Status = 'INFO')
    $color = switch ($Status) { 'OK' { 'Green' }; 'WARN' { 'Yellow' }; 'ERROR' { 'Red' }; 'INFO' { 'Cyan' }; 'SKIP' { 'DarkGray' } }
    $icon = switch ($Status) { 'OK' { '[OK]' }; 'WARN' { '[!] ' }; 'ERROR' { '[X]' }; 'INFO' { '[i]' }; 'SKIP' { '[-]' } }
    Write-Host "  $($icon.PadRight(5)) " -ForegroundColor $color -NoNewline
    Write-Host "${Label}: " -ForegroundColor Gray -NoNewline
    Write-Host $Value -ForegroundColor White
}

function Write-Section {
    param([string]$Title)
    Write-Host ""; Write-Host "  $( '=' * 58 )" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "  $( '=' * 58 )" -ForegroundColor DarkGray
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    return "{0:N0} KB" -f ($Bytes / 1KB)
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# Удаляет файлы старше порога из папки; возвращает освобождённые байты.
# Уважает -WhatIf через ShouldProcess.
function Clear-FolderAged {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path, [string]$Purpose)
    if (-not $Path -or -not (Test-Path $Path)) { return 0 }
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $files = Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff }
    if (-not $files) { return 0 }
    $bytes = ($files | Measure-Object Length -Sum).Sum
    if ($PSCmdlet.ShouldProcess("$Path ($($files.Count) файлов, $(Format-Size $bytes))", "Удалить $Purpose")) {
        $deleted = 0
        foreach ($f in $files) {
            try { Remove-Item $f.FullName -Force -ErrorAction Stop; $deleted += $f.Length } catch { } # занятые файлы пропускаем
        }
        # Подчищаем опустевшие подпапки
        Get-ChildItem $Path -Recurse -Directory -Force -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Where-Object { -not (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue) } |
            ForEach-Object { try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch { } }
        return $deleted
    }
    return $bytes  # -WhatIf: показываем потенциал
}

$isAdmin = Test-IsAdmin
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "  ║         ОПТИМИЗАЦИЯ НОУТБУКА — Optimize-Laptop            ║" -ForegroundColor Magenta
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
if ($WhatIfPreference) { Write-Host "  РЕЖИМ ПРЕДПРОСМОТРА (-WhatIf): ничего не удаляется" -ForegroundColor Yellow }
if ($Deep -and -not $isAdmin) { Write-Host "  ⚠ -Deep без прав администратора: часть операций будет пропущена" -ForegroundColor Yellow }

# ── 1. Временные файлы ──────────────────────────────────────────
Write-Section "1. ВРЕМЕННЫЕ ФАЙЛЫ (старше $OlderThanDays дн.)"
$tempTargets = @(
    @{ Path = $env:TEMP; Name = 'TEMP пользователя' },
    @{ Path = "$env:WINDIR\Temp"; Name = 'Windows\Temp' }
) | Where-Object { $_.Path } | Sort-Object -Property Path -Unique
$tempFreed = 0
foreach ($t in $tempTargets) {
    $freed = Clear-FolderAged -Path $t.Path -Purpose "врем. файлы ($($t.Name))"
    $tempFreed += $freed
    Write-StatusLine $t.Name $(if ($freed -gt 0) { Format-Size $freed } else { 'нечего удалять' }) $(if ($freed -gt 0) { 'OK' } else { 'SKIP' })
}
$script:FreedBytes += $tempFreed
$script:Summary.Categories['TempFiles'] = @{ FreedBytes = $tempFreed }

# ── 2. Кэш DNS ──────────────────────────────────────────────────
Write-Section "2. КЭШ DNS"
if (Get-Command ipconfig -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess('DNS cache', 'Сбросить')) {
        $null = ipconfig /flushdns 2>&1
        Write-StatusLine 'DNS' 'кэш сброшен' 'OK'
        $script:Summary.Categories['DnsFlush'] = @{ Done = $true }
    } else { Write-StatusLine 'DNS' 'будет сброшен' 'INFO' }
} else { Write-StatusLine 'DNS' 'ipconfig недоступен' 'SKIP' }

# ── 3. Автозагрузка (аудит) ─────────────────────────────────────
Write-Section "3. АВТОЗАГРУЗКА (аудит — ничего не отключается)"
try {
    $startup = @()
    if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
        $startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue |
            Select-Object @{n='Name';e={$_.Name}}, @{n='Command';e={$_.Command}}, @{n='Location';e={$_.Location}})
    }
    $script:Summary.Categories['StartupAudit'] = @{ Count = $startup.Count; Items = @($startup | ForEach-Object { $_.Name }) }
    if ($startup.Count -eq 0) { Write-StatusLine 'Автозагрузка' 'записей не найдено' 'OK' }
    else {
        $stStatus = if ($startup.Count -gt 12) { 'WARN' } else { 'INFO' }
        Write-StatusLine 'Программ в автозагрузке' "$($startup.Count)$(if ($stStatus -eq 'WARN') { ' — много, замедляет старт системы' })" $stStatus
        foreach ($s in ($startup | Select-Object -First 15)) { Write-Host "         • $($s.Name)" -ForegroundColor DarkGray }
        Write-Host "         Отключение: Диспетчер задач → вкладка Автозагрузка" -ForegroundColor DarkGray
    }
} catch { Write-StatusLine 'Автозагрузка' $_.Exception.Message 'ERROR' }

# ── 4. Схема питания (аудит) ────────────────────────────────────
Write-Section "4. СХЕМА ПИТАНИЯ"
if (Get-Command powercfg -ErrorAction SilentlyContinue) {
    try {
        $scheme = (powercfg /getactivescheme 2>&1) -join ' '
        if ($scheme -match '\((.+)\)') {
            $planName = $Matches[1]
            $script:Summary.Categories['PowerPlan'] = @{ Active = $planName }
            Write-StatusLine 'Активная схема' $planName 'INFO'
            if ($planName -match 'High performance|Высокая производительность') {
                Write-StatusLine 'Рекомендация' 'на батарее выгоднее «Сбалансированная» — High Perf греет и сажает АКБ' 'WARN'
            } else {
                Write-StatusLine 'Рекомендация' 'схема подходит для ноутбука' 'OK'
            }
        } else { Write-StatusLine 'Схема' 'не удалось определить' 'SKIP' }
    } catch { Write-StatusLine 'Питание' $_.Exception.Message 'ERROR' }
} else { Write-StatusLine 'powercfg' 'недоступен' 'SKIP' }

# ── 5. Топ процессов по памяти (аудит) ─────────────────────────
Write-Section "5. ПАМЯТЬ: ТОП-5 ПРОЦЕССОВ"
try {
    $top = Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 5
    $script:Summary.Categories['TopMemory'] = @($top | ForEach-Object { @{ Name = $_.ProcessName; MemMB = [math]::Round($_.WorkingSet64 / 1MB, 0) } })
    foreach ($p in $top) { Write-StatusLine $p.ProcessName "$([math]::Round($p.WorkingSet64 / 1MB, 0)) MB" 'INFO' }
} catch { Write-StatusLine 'Процессы' $_.Exception.Message 'ERROR' }

# ── 6. Deep: корзина, Windows Update, TRIM ─────────────────────
if ($Deep) {
    Write-Section "6. ГЛУБОКАЯ ОЧИСТКА (-Deep)"

    # Корзина
    if (Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess('Корзина', 'Очистить')) {
            try { Clear-RecycleBin -Force -ErrorAction Stop; Write-StatusLine 'Корзина' 'очищена' 'OK'; $script:Summary.Categories['RecycleBin'] = @{ Done = $true } }
            catch { Write-StatusLine 'Корзина' $(if ($_.Exception.Message -match 'empty|пуст') { 'уже пуста' } else { $_.Exception.Message }) 'SKIP' }
        } else { Write-StatusLine 'Корзина' 'будет очищена' 'INFO' }
    } else { Write-StatusLine 'Корзина' 'Clear-RecycleBin недоступен' 'SKIP' }

    # Кэш Windows Update
    if ($isAdmin) {
        $wuCache = "$env:WINDIR\SoftwareDistribution\Download"
        if (Test-Path $wuCache) {
            $wuBytes = (Get-ChildItem $wuCache -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            if ($wuBytes -gt 0 -and $PSCmdlet.ShouldProcess("Кэш Windows Update ($(Format-Size $wuBytes))", 'Очистить')) {
                # Останавливаем службу, чистим, запускаем обратно
                try {
                    Stop-Service wuauserv -Force -ErrorAction Stop
                    Get-ChildItem $wuCache -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    Start-Service wuauserv -ErrorAction SilentlyContinue
                    $script:FreedBytes += $wuBytes
                    $script:Summary.Categories['WindowsUpdateCache'] = @{ FreedBytes = $wuBytes }
                    Write-StatusLine 'Кэш Windows Update' "освобождено $(Format-Size $wuBytes)" 'OK'
                } catch { Start-Service wuauserv -ErrorAction SilentlyContinue; Write-StatusLine 'Кэш Windows Update' $_.Exception.Message 'ERROR' }
            } elseif ($wuBytes -gt 0) { Write-StatusLine 'Кэш Windows Update' "будет освобождено $(Format-Size $wuBytes)" 'INFO' }
            else { Write-StatusLine 'Кэш Windows Update' 'пуст' 'SKIP' }
        }
    } else { Write-StatusLine 'Кэш Windows Update' 'нужны права администратора' 'SKIP' }

    # TRIM / дефрагментация
    if ($isAdmin -and (Get-Command Optimize-Volume -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess('Системный том', 'TRIM (SSD) / дефрагментация (HDD)')) {
            try {
                $sysDrive = ($env:SystemDrive -replace ':', '')
                Optimize-Volume -DriveLetter $sysDrive -Verbose:$false -ErrorAction Stop
                Write-StatusLine "Том $env:SystemDrive" 'оптимизирован (TRIM/defrag по типу носителя)' 'OK'
                $script:Summary.Categories['VolumeOptimize'] = @{ Drive = $env:SystemDrive; Done = $true }
            } catch { Write-StatusLine 'Optimize-Volume' $_.Exception.Message 'ERROR' }
        } else { Write-StatusLine "Том $env:SystemDrive" 'будет оптимизирован' 'INFO' }
    } elseif ($Deep) { Write-StatusLine 'TRIM/дефрагментация' $(if ($isAdmin) { 'Optimize-Volume недоступен' } else { 'нужны права администратора' }) 'SKIP' }
}

# ── Итог ────────────────────────────────────────────────────────
Write-Section "ИТОГ"
$script:Summary.FreedBytes = $script:FreedBytes
Write-Host ""
if ($WhatIfPreference) {
    Write-Host "  Предпросмотр завершён. Потенциально освободится: $(Format-Size $script:FreedBytes)" -ForegroundColor Yellow
    Write-Host "  Запустите без -WhatIf для выполнения." -ForegroundColor Yellow
} else {
    Write-Host "  Освобождено: $(Format-Size $script:FreedBytes)" -ForegroundColor Green
    if (-not $Deep) { Write-Host "  Подсказка: -Deep (от администратора) добавит корзину, кэш обновлений и TRIM" -ForegroundColor DarkGray }
}
Write-Host ""

if ($Export) {
    if (-not (Test-Path $ReportPath)) { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    $file = Join-Path $ReportPath "optimize-$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"
    $script:Summary | ConvertTo-Json -Depth 6 | Out-File $file -Encoding UTF8
    Write-Host "  Отчёт: $file" -ForegroundColor Cyan
    Write-Host ""
}

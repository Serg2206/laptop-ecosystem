#requires -Version 5.1
<#
.SYNOPSIS
    Главное меню управления экосистемой ноутбука — Command Center.

.DESCRIPTION
    Интерактивное цветное меню для управления всей экосистемой:
    [1] Dashboard — проверить все компоненты
    [2] OneDrive — запустить/проверить
    [3] Daily Note — создать заметку
    [4] Obsidian → Notion — синхронизация
    [5] GitHub Backup — сделать backup
    [6] Junction Links — проверить связи
    [7] Task Scheduler — управление задачами
    [8] Academic Templates — открыть шаблоны
    [9] Fonts & Templates — установить шрифты
    [0] Выход

.PARAMETER VaultPath
    Путь к Obsidian Vault. По умолчанию: C:\Obsidian

.PARAMETER ScriptsPath
    Путь к папке со скриптами. По умолчанию: папка текущего скрипта

.EXAMPLE
    .\New-CommandCenter.ps1
    .\New-CommandCenter.ps1 -VaultPath "D:\Obsidian"
#>
[CmdletBinding()]
param (
    [string]$VaultPath   = "C:\Obsidian",
    [string]$ScriptsPath = $PSScriptRoot
)

$ErrorActionPreference = 'Continue'

function Show-Banner {
    Clear-Host
    $banner = @'

╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║     __  __  ____   _____ _    _  ____   _____ _______            ║
║    |  \/  |/ __ \ / ____| |  | |/ __ \ / ____|__   __|           ║
║    | \  / | |  | | (___ | |__| | |  | | (___    | |              ║
║    | |\/| | |  | |\___ \|  __  | |  | |\___ \   | |              ║
║    | |  | | |__| |____) | |  | | |__| |____) |  | |              ║
║    |_|  |_|\____/|_____/|_|  |_|\____/|_____/   |_|              ║
║                                                                  ║
║           Э К О С И С Т Е М А   Н О У Т Б У К А                  ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

'@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host "  Vault:  $VaultPath" -ForegroundColor Gray
    Write-Host "  Time:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
}

function Show-Menu {
    Show-Banner
    Write-Host '        ╔══════════════════════════════════════════╗' -ForegroundColor Cyan
    Write-Host '        ║      COMMAND CENTER — ГЛАВНОЕ МЕНЮ       ║' -ForegroundColor Cyan
    Write-Host '        ╠══════════════════════════════════════════╣' -ForegroundColor Cyan
    $items = @(
        @{ N='1'; I='📊'; L='Dashboard — проверить всё' },
        @{ N='2'; I='☁️ '; L='OneDrive — запустить/проверить' },
        @{ N='3'; I='📝'; L='Daily Note — создать заметку' },
        @{ N='4'; I='🔄'; L='Obsidian → Notion — синхронизация' },
        @{ N='5'; I='📤'; L='GitHub Backup — сделать backup' },
        @{ N='6'; I='🔗'; L='Junction Links — проверить связи' },
        @{ N='7'; I='📅'; L='Task Scheduler — управление' },
        @{ N='8'; I='📚'; L='Academic Templates — шаблоны' },
        @{ N='9'; I='🎨'; L='Fonts & Templates — шрифты' },
        @{ N='0'; I='❌'; L='Выход' }
    )
    foreach ($it in $items) {
        if ($it.N -eq '0') { Write-Host '        ║                                          ║' -ForegroundColor Cyan }
        $line = "        ║  [$($it.N)] $($it.I)  $($it.L)"
        $line = $line.PadRight(56) + '║'
        if ($it.N -eq '0') { Write-Host $line -ForegroundColor Red } else { Write-Host $line -ForegroundColor White }
    }
    Write-Host '        ╚══════════════════════════════════════════╝' -ForegroundColor Cyan
    Write-Host ''
}

function Read-Choice { Write-Host '  Введите номер: ' -ForegroundColor Yellow -NoNewline; return (Read-Host).Trim() }

function Invoke-Script {
    param([string]$ScriptName, [hashtable]$Parameters = @{})
    $scriptPath = Join-Path $ScriptsPath $ScriptName
    if (-not (Test-Path $scriptPath)) { Write-Host "  ❌ Не найден: $scriptPath" -ForegroundColor Red; return $false }
    Write-Host ""; Write-Host "  🚀 Запуск: $ScriptName" -ForegroundColor Cyan; Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray
    try { $args = @(); foreach ($k in $Parameters.Keys) { $v = $Parameters[$k]; if ($v -is [bool] -and $v) { $args += "-$k" } elseif ($v -is [string]) { $args += "-$k `"$v`"" } }; $cmd = "& `"$scriptPath`" $args"; Invoke-Expression $cmd; return $true }
    catch { Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red; return $false }
}

function Pause-Return { Write-Host ''; Write-Host '  Нажмите Enter для возврата...' -ForegroundColor DarkGray; [void][System.Console]::ReadLine() }

function Start-OneDriveCheck {
    Write-Host ""; Write-Host "  ☁️  OneDrive..." -ForegroundColor Cyan; Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray
    try {
        $proc = Get-Process 'OneDrive' -ErrorAction SilentlyContinue
        if ($proc) { Write-Host "  ✅ Запущен (PID: $($proc.Id))" -ForegroundColor Green }
        else {
            Write-Host "  ⚠️  Не запущен. Запуск..." -ForegroundColor Yellow
            $paths = @("$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe", "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe", "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")
            foreach ($p in $paths) { if (Test-Path $p) { Start-Process $p; Write-Host "  ✅ Запущен: $p" -ForegroundColor Green; break } }
        }
        $odPaths = @($env:OneDrive, "$env:USERPROFILE\OneDrive", "$env:USERPROFILE\OneDrive - Personal")
        foreach ($p in $odPaths) { if ($p -and (Test-Path $p)) { Write-Host "  ✅ Папка: $p" -ForegroundColor Green; return } }
        Write-Host "  ⚠️  Папка синхронизации не найдена" -ForegroundColor Yellow
    } catch { Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red }
    Pause-Return
}

function New-DailyNoteFunc {
    Write-Host ""; Write-Host "  📝 Daily Note..." -ForegroundColor Cyan; Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray
    try {
        $today = Get-Date -Format 'yyyy-MM-dd'
        $folder = Join-Path $VaultPath '01-DailyNotes'
        if (-not (Test-Path $folder)) { New-Item -ItemType Directory $folder -Force | Out-Null; Write-Host "  📁 Создана папка" -ForegroundColor Green }
        $notePath = Join-Path $folder "$today.md"
        if (Test-Path $notePath) { Write-Host "  ⚠️  Уже существует: $notePath" -ForegroundColor Yellow }
        else {
            $template = @"# $(Get-Date -Format 'yyyy-MM-dd dddd')

## 🌅 Morning
- 

## 📝 Notes
- 

## ✅ Tasks
- [ ] 

## 🌙 Evening Review
- 

---
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm')
"@
            $template | Set-Content $notePath -Encoding UTF8
            Write-Host "  ✅ Создана: $notePath" -ForegroundColor Green
        }
    } catch { Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red }
    Pause-Return
}

function Show-JunctionStatus {
    Write-Host ""; Write-Host "  🔗 Junction Links..." -ForegroundColor Cyan; Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray
    try {
        if (Test-Path $VaultPath) {
            $item = Get-Item $VaultPath -Force; $isJunction = $item.Attributes -match 'ReparsePoint'
            if ($isJunction) { Write-Host "  ✅ Vault is Junction -> $((Get-Item $VaultPath).Target)" -ForegroundColor Green }
            else { Write-Host "  ⚠️  Vault is regular folder (not junction)" -ForegroundColor Yellow }
        } else { Write-Host "  ❌ Vault not found: $VaultPath" -ForegroundColor Red }
    } catch { Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red }
    Pause-Return
}

function Show-TaskMenu {
    Write-Host ""; Write-Host "  📅 Task Scheduler..." -ForegroundColor Cyan; Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray
    try {
        $tasks = Get-ScheduledTask -TaskName 'MS365*' -ErrorAction SilentlyContinue
        if (-not $tasks) { Write-Host "  ⚠️  Задачи не найдены" -ForegroundColor Yellow }
        else { foreach ($t in $tasks) { try { $i = Get-ScheduledTaskInfo $t.TaskName -ErrorAction SilentlyContinue; Write-Host "  • $($t.TaskName) — $($t.State) | Next: $($i.NextRunTime)" } catch { Write-Host "  • $($t.TaskName) — ошибка" -ForegroundColor Red } } }
    } catch { Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red }
    Pause-Return
}

# ═══════════════════════════════════════════════════════════════
# ГЛАВНЫЙ ЦИКЛ
# ═══════════════════════════════════════════════════════════════
$running = $true
while ($running) {
    Show-Menu
    switch (Read-Choice) {
        '1' { Invoke-Script 'Get-WorkspaceStatus.ps1' @{ VaultPath = $VaultPath } | Out-Host; Pause-Return }
        '2' { Start-OneDriveCheck }
        '3' { New-DailyNoteFunc }
        '4' { Write-Host ''; Write-Host '  DryRun? (Y/N): ' -ForegroundColor Yellow -NoNewline; $dry = Read-Host; $p = @{ VaultPath = $VaultPath }; if ($dry -eq 'Y' -or $dry -eq 'y') { $p['DryRun'] = $true }; Invoke-Script 'Sync-ObsidianToNotion.ps1' $p | Out-Host; Pause-Return }
        '5' { Write-Host ''; Write-Host '  Push после commit? (Y/N): ' -ForegroundColor Yellow -NoNewline; $push = Read-Host; $p = @{ VaultPath = $VaultPath }; if ($push -eq 'Y' -or $push -eq 'y') { $p['AutoPush'] = $true }; Invoke-Script 'Backup-ToGitHub.ps1' $p | Out-Host; Pause-Return }
        '6' { Show-JunctionStatus }
        '7' { Show-TaskMenu }
        '8' { Write-Host ""; try { Start-Process explorer.exe (Join-Path $VaultPath '03-Academic') } catch { Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red }; Pause-Return }
        '9' { Write-Host ""; Write-Host '  Для установки используйте Setup-Everything.ps1' -ForegroundColor Yellow; Pause-Return }
        '0' { $running = $false; Clear-Host; Write-Host ""; Write-Host '  👋 До свидания!' -ForegroundColor Cyan; Write-Host ""; exit 0 }
        default { Write-Host ""; Write-Host '  ❌ Неверный выбор' -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
}

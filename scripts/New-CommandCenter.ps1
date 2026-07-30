#requires -Version 5.1
<#
.SYNOPSIS
    Главное меню управления MS 365 Workspace — Command Center.

.DESCRIPTION
    Интерактивное цветное меню для управления всем workspace:
    - Просмотр статуса всех компонентов (OneDrive, Obsidian, Notion, GitHub)
    - Запуск и проверка OneDrive
    - Создание ежедневных заметок
    - Синхронизация Obsidian → Notion
    - Backup в GitHub
    - Проверка junction-ссылок
    - Управление Task Scheduler
    - Академические шаблоны
    - Установка шрифтов и шаблонов

    После выполнения каждого действия возвращается в главное меню.
    Выход — пункт 0.

.PARAMETER VaultPath
    Путь к Obsidian Vault. По умолчанию: C:\Obsidian

.PARAMETER ScriptsPath
    Путь к папке со скриптами. По умолчанию: папка текущего скрипта

.EXAMPLE
    .\New-CommandCenter.ps1
    .\New-CommandCenter.ps1 -VaultPath "D:\Obsidian"

.NOTES
    Требования: все скрипты MS365 toolkit должны быть в папке ScriptsPath.
    Кодировка: UTF-8 with BOM для корректного отображения русского текста.
#>
[CmdletBinding()]
param (
    [string]$VaultPath   = "C:\Obsidian",
    [string]$ScriptsPath = $PSScriptRoot
)

# ═══════════════════════════════════════════════════════════════
# Константы
# ═══════════════════════════════════════════════════════════════
$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.BackgroundColor = 'Black'

# ═══════════════════════════════════════════════════════════════
# Вспомогательные функции
# ═══════════════════════════════════════════════════════════════
function Show-AsciiBanner {
    <#
    .SYNOPSIS
        Выводит цветной ASCII-art заголовок Command Center.
    #>
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
║           W O R K S P A C E   C O M M A N D   C E N T E R       ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

'@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host "  Vault:  $VaultPath" -ForegroundColor Gray
    Write-Host "  Time:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
}

function Show-MainMenu {
    <#
    .SYNOPSIS
        Выводит главное меню с пунктами.
    #>
    Show-AsciiBanner

    $menuItems = @(
        @{ Num = '1'; Icon = '📊'; Label = 'Workspace Status Dashboard'   }
        @{ Num = '2'; Icon = '☁️ '; Label = 'Start / Check OneDrive'         }
        @{ Num = '3'; Icon = '📝'; Label = 'Create Daily Note'              }
        @{ Num = '4'; Icon = '🔄'; Label = 'Sync Obsidian → Notion'         }
        @{ Num = '5'; Icon = '📤'; Label = 'Backup to GitHub'               }
        @{ Num = '6'; Icon = '🔗'; Label = 'Check Junction Links'           }
        @{ Num = '7'; Icon = '📅'; Label = 'Manage Task Scheduler'          }
        @{ Num = '8'; Icon = '📚'; Label = 'Open Academic Templates'        }
        @{ Num = '9'; Icon = '🎨'; Label = 'Install Fonts & Templates'      }
        @{ Num = '0'; Icon = '❌'; Label = 'Exit'                           }
    )

    Write-Host '        ╔══════════════════════════════════════════╗' -ForegroundColor Cyan
    Write-Host '        ║      MS 365 WORKSPACE COMMAND CENTER     ║' -ForegroundColor Cyan
    Write-Host '        ╠══════════════════════════════════════════╣' -ForegroundColor Cyan
    foreach ($item in $menuItems) {
        $num   = $item.Num
        $icon  = $item.Icon
        $label = $item.Label
        if ($num -eq '0') {
            Write-Host '        ║                                          ║' -ForegroundColor Cyan
        }
        $line = "        ║  [$num] $icon  $label"
        $line = $line.PadRight(56) + '║'
        if ($num -eq '0') {
            Write-Host $line -ForegroundColor Red
        } else {
            Write-Host $line -ForegroundColor White
        }
    }
    Write-Host '        ╚══════════════════════════════════════════╝' -ForegroundColor Cyan
    Write-Host ''
}

function Read-MenuChoice {
    <#
    .SYNOPSIS
        Читает выбор пользователя из меню.
    #>
    Write-Host '  Введите номер пункта: ' -ForegroundColor Yellow -NoNewline
    $choice = Read-Host
    return $choice.Trim()
}

function Invoke-Script {
    <#
    .SYNOPSIS
        Запускает указанный PowerShell скрипт с параметрами.
    #>
    param(
        [string]$ScriptName,
        [hashtable]$Parameters = @{}
    )

    $scriptPath = Join-Path -Path $ScriptsPath -ChildPath $ScriptName

    if (-not (Test-Path -Path $scriptPath)) {
        Write-Host ""
        Write-Host "  ❌ Скрипт не найден: $scriptPath" -ForegroundColor Red
        Write-Host "  Проверьте, что файл существует в папке $ScriptsPath" -ForegroundColor Yellow
        return $false
    }

    Write-Host ""
    Write-Host "  🚀 Запуск: $ScriptName" -ForegroundColor Cyan
    Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray

    try {
        $paramArgs = @()
        foreach ($key in $Parameters.Keys) {
            $value = $Parameters[$key]
            if ($value -is [bool] -and $value -eq $true) {
                $paramArgs += "-$key"
            } elseif ($value -is [string]) {
                $paramArgs += "-$key `"$value`""
            } else {
                $paramArgs += "-$key $value"
            }
        }

        $fullCommand = "& `"$scriptPath`" $paramArgs"
        Invoke-Expression $fullCommand
        return $true
    } catch {
        Write-Host ""
        Write-Host "  ❌ Ошибка выполнения: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Start-OneDriveCheck {
    <#
    .SYNOPSIS
        Проверяет и запускает OneDrive если не запущен.
    #>
    Write-Host ""
    Write-Host "  ☁️  Проверка OneDrive..." -ForegroundColor Cyan
    Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray

    try {
        $proc = Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "  ✅ OneDrive уже запущен (PID: $($proc.Id))" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  OneDrive не запущен. Попытка запуска..." -ForegroundColor Yellow
            $oneDrivePaths = @(
                "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
                "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe",
                "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe"
            )
            $started = $false
            foreach ($odPath in $oneDrivePaths) {
                if (Test-Path $odPath) {
                    Start-Process -FilePath $odPath -WindowStyle Normal
                    Write-Host "  ✅ OneDrive запущен: $odPath" -ForegroundColor Green
                    $started = $true
                    break
                }
            }
            if (-not $started) {
                Write-Host "  ❌ Не удалось найти OneDrive.exe" -ForegroundColor Red
            }
        }

        $odPaths = @(
            $env:OneDrive,
            "$env:USERPROFILE\OneDrive",
            "$env:USERPROFILE\OneDrive - Personal"
        )
        $foundPath = $null
        foreach ($p in $odPaths) {
            if ($p -and (Test-Path $p)) {
                $foundPath = $p
                break
            }
        }
        if ($foundPath) {
            Write-Host "  ✅ Папка синхронизации: $foundPath" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  Папка синхронизации не найдена" -ForegroundColor Yellow
        }

    } catch {
        Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Pause-AndReturn
}

function New-DailyNote {
    <#
    .SYNOPSIS
        Создаёт ежедневную заметку в Obsidian vault.
    #>
    Write-Host ""
    Write-Host "  📝 Создание ежедневной заметки..." -ForegroundColor Cyan
    Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray

    try {
        $today       = Get-Date -Format 'yyyy-MM-dd'
        $dayOfWeek   = (Get-Date).ToString('dddd', [System.Globalization.CultureInfo]::GetCultureInfo('ru-RU'))
        $dailyFolder = Join-Path -Path $VaultPath -ChildPath '01-DailyNotes'

        if (-not (Test-Path $dailyFolder)) {
            New-Item -ItemType Directory -Path $dailyFolder -Force | Out-Null
            Write-Host "  📁 Создана папка: 01-DailyNotes" -ForegroundColor Green
        }

        $notePath = Join-Path -Path $dailyFolder -ChildPath "$today.md"

        if (Test-Path $notePath) {
            Write-Host "  ⚠️  Заметка уже существует: $notePath" -ForegroundColor Yellow
        } else {
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
            $template | Set-Content -Path $notePath -Encoding UTF8
            Write-Host "  ✅ Создана заметка: $notePath" -ForegroundColor Green
        }

        $obsidianUri = "obsidian://open?path=$([System.Uri]::EscapeDataString($notePath))"
        Write-Host "  🔗 URI для Obsidian: $obsidianUri" -ForegroundColor Gray

    } catch {
        Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Pause-AndReturn
}

function Show-JunctionStatus {
    <#
    .SYNOPSIS
        Показывает статус junction-ссылок.
    #>
    Write-Host ""
    Write-Host "  🔗 Проверка Junction Links..." -ForegroundColor Cyan
    Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray

    try {
        if (Test-Path $VaultPath) {
            $item = Get-Item -Path $VaultPath -Force
            $isJunction = $item.Attributes -match 'ReparsePoint'

            if ($isJunction) {
                $target = (Get-Item -Path $VaultPath).Target
                Write-Host "  ✅ Vault is Junction" -ForegroundColor Green
                Write-Host "     Path:   $VaultPath" -ForegroundColor Gray
                Write-Host "     Target: $target" -ForegroundColor Gray
            } else {
                Write-Host "  ⚠️  Vault is regular folder (not junction)" -ForegroundColor Yellow
                Write-Host "     Path:   $VaultPath" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ❌ Vault not found: $VaultPath" -ForegroundColor Red
        }

        $configPaths = @(
            (Join-Path $PSScriptRoot ".." "config" "junctions.config.json"),
            (Join-Path $PSScriptRoot "junctions.config.json")
        )
        foreach ($configPath in $configPaths) {
            if (Test-Path $configPath) {
                Write-Host ""
                Write-Host "  📁 Конфиг: $configPath" -ForegroundColor Gray
                $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($j in $config.junctions) {
                    if (Test-Path $j.path) {
                        $item = Get-Item -Path $j.path -Force
                        $isJunction = $item.Attributes -match 'ReparsePoint'
                        if ($isJunction) {
                            Write-Host "  ✅ $($j.name): $($j.path) -> junction OK" -ForegroundColor Green
                        } else {
                            Write-Host "  ⚠️  $($j.name): $($j.path) — не junction" -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "  ❌ $($j.name): $($j.path) — не существует!" -ForegroundColor Red
                    }
                }
                break
            }
        }

    } catch {
        Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Pause-AndReturn
}

function Show-TaskSchedulerMenu {
    <#
    .SYNOPSIS
        Показывает статус задач Task Scheduler и позволяет управлять ими.
    #>
    Write-Host ""
    Write-Host "  📅 Task Scheduler — задачи MS365..." -ForegroundColor Cyan
    Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray

    try {
        $tasks = Get-ScheduledTask -TaskName 'MS365*' -ErrorAction SilentlyContinue

        if (-not $tasks) {
            Write-Host "  ⚠️  Задачи MS365* не найдены" -ForegroundColor Yellow
        } else {
            foreach ($task in $tasks) {
                try {
                    $info = Get-ScheduledTaskInfo -TaskName $task.TaskName
                    $stateColor = switch ($task.State) {
                        'Ready'    { 'Green' }
                        'Running'  { 'Green' }
                        'Disabled' { 'Yellow' }
                        default    { 'Gray' }
                    }
                    Write-Host "  • $($task.TaskName)" -ForegroundColor $stateColor
                    Write-Host "    State: $($task.State) | Next: $($info.NextRunTime) | Last: $($info.LastRunTime)" -ForegroundColor Gray
                } catch {
                    Write-Host "  • $($task.TaskName) — ошибка получения информации" -ForegroundColor Red
                }
            }
        }

        Write-Host ""
        Write-Host "  [1] Зарегистрировать все задачи (Register-AllTasks.ps1)" -ForegroundColor White
        Write-Host "  [2] Включить все задачи" -ForegroundColor White
        Write-Host "  [3] Отключить все задачи" -ForegroundColor White
        Write-Host "  [Enter] Назад в меню" -ForegroundColor Gray
        Write-Host ""
        Write-Host '  Выберите действие: ' -ForegroundColor Yellow -NoNewline
        $tsChoice = Read-Host

        switch ($tsChoice) {
            '1' {
                $registerPath = Join-Path $ScriptsPath 'Register-AllTasks.ps1'
                if (Test-Path $registerPath) {
                    & $registerPath
                } else {
                    Write-Host "  ❌ Register-AllTasks.ps1 не найден" -ForegroundColor Red
                }
            }
            '2' {
                Get-ScheduledTask -TaskName 'MS365*' | Enable-ScheduledTask | Out-Null
                Write-Host "  ✅ Все задачи включены" -ForegroundColor Green
            }
            '3' {
                Get-ScheduledTask -TaskName 'MS365*' | Disable-ScheduledTask | Out-Null
                Write-Host "  ✅ Все задачи отключены" -ForegroundColor Green
            }
        }

    } catch {
        Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Pause-AndReturn
}

function Open-AcademicTemplates {
    <#
    .SYNOPSIS
        Открывает папку с академическими шаблонами.
    #>
    Write-Host ""
    Write-Host "  📚 Академические шаблоны..." -ForegroundColor Cyan
    Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray

    try {
        $templatesPath = Join-Path $VaultPath '03-Academic'
        if (Test-Path $templatesPath) {
            Start-Process explorer.exe -ArgumentList $templatesPath
            Write-Host "  ✅ Открыта папка: $templatesPath" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  Папка не найдена: $templatesPath" -ForegroundColor Yellow
            Write-Host "  Создаю папку..." -ForegroundColor Gray
            New-Item -ItemType Directory -Path $templatesPath -Force | Out-Null
            Write-Host "  ✅ Папка создана" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Pause-AndReturn
}

function Install-FontsAndTemplates {
    <#
    .SYNOPSIS
        Устанавливает шрифты и шаблоны для workspace.
    #>
    Write-Host ""
    Write-Host "  🎨 Установка шрифтов и шаблонов..." -ForegroundColor Cyan
    Write-Host "  $( '-' * 50 )" -ForegroundColor DarkGray

    try {
        $assetsPath = Join-Path $PSScriptRoot ".." "assets"
        if (Test-Path $assetsPath) {
            $fontsPath = Join-Path $assetsPath "fonts"
            if (Test-Path $fontsPath) {
                $fontFiles = Get-ChildItem -Path $fontsPath -Filter '*.ttf' -ErrorAction SilentlyContinue
                Write-Host "  Найдено шрифтов: $($fontFiles.Count)" -ForegroundColor Gray
                foreach ($font in $fontFiles) {
                    Write-Host "    📄 $($font.Name)" -ForegroundColor White
                }
                foreach ($font in $fontFiles) {
                    try {
                        Copy-Item -Path $font.FullName -Destination "$env:WINDIR\Fonts\$($font.Name)" -Force -ErrorAction SilentlyContinue
                        Write-Host "    ✅ Установлен: $($font.Name)" -ForegroundColor Green
                    } catch {
                        Write-Host "    ⚠️  Не удалось установить: $($font.Name)" -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "  ℹ️  Папка со шрифтами не найдена" -ForegroundColor Gray
            }

            $templatesPath = Join-Path $assetsPath "templates"
            if (Test-Path $templatesPath) {
                Write-Host ""
                Write-Host "  📁 Шаблоны:" -ForegroundColor Gray
                $templates = Get-ChildItem -Path $templatesPath -File -ErrorAction SilentlyContinue
                foreach ($tmpl in $templates) {
                    Write-Host "    📄 $($tmpl.Name)" -ForegroundColor White
                }
            }
        } else {
            Write-Host "  ℹ️  Папка assets не найдена в $assetsPath" -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "  ✅ Установка завершена" -ForegroundColor Green

    } catch {
        Write-Host "  ❌ Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Pause-AndReturn
}

function Pause-AndReturn {
    <#
    .SYNOPSIS
        Ожидает нажатия Enter перед возвратом в меню.
    #>
    Write-Host '  Нажмите Enter для возврата в меню...' -ForegroundColor DarkGray
    [void][System.Console]::ReadLine()
}

# ═══════════════════════════════════════════════════════════════
# ГЛАВНЫЙ ЦИКЛ
# ═══════════════════════════════════════════════════════════════
$running = $true

while ($running) {
    Show-MainMenu
    $choice = Read-MenuChoice

    switch ($choice) {
        '1' {
            Invoke-Script -ScriptName 'Get-WorkspaceStatus.ps1' -Parameters @{
                VaultPath = $VaultPath
            } | Out-Host
            Pause-AndReturn
        }

        '2' {
            Start-OneDriveCheck
        }

        '3' {
            New-DailyNote
        }

        '4' {
            Write-Host ""
            Write-Host '  Запустить в режиме DryRun? (Y/N): ' -ForegroundColor Yellow -NoNewline
            $dry = Read-Host
            $params = @{ VaultPath = $VaultPath }
            if ($dry -eq 'Y' -or $dry -eq 'y') {
                $params['DryRun'] = $true
            }
            if ($env:NOTION_DATABASE_ID) {
                $params['DatabaseId'] = $env:NOTION_DATABASE_ID
            }
            Invoke-Script -ScriptName 'Sync-ObsidianToNotion.ps1' -Parameters $params | Out-Host
            Pause-AndReturn
        }

        '5' {
            Write-Host ""
            Write-Host '  Выполнить push после commit? (Y/N): ' -ForegroundColor Yellow -NoNewline
            $push = Read-Host
            $params = @{ VaultPath = $VaultPath }
            if ($push -eq 'Y' -or $push -eq 'y') {
                $params['AutoPush'] = $true
            }
            Invoke-Script -ScriptName 'Backup-ToGitHub.ps1' -Parameters $params | Out-Host
            Pause-AndReturn
        }

        '6' {
            Show-JunctionStatus
        }

        '7' {
            Show-TaskSchedulerMenu
        }

        '8' {
            Open-AcademicTemplates
        }

        '9' {
            Install-FontsAndTemplates
        }

        '0' {
            $running = $false
            Clear-Host
            Write-Host ""
            Write-Host '  👋 До свидания!' -ForegroundColor Cyan
            Write-Host ""
            exit 0
        }

        default {
            Write-Host ""
            Write-Host '  ❌ Неверный выбор. Попробуйте снова.' -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

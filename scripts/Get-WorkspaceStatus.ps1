#requires -Version 5.1
<#
.SYNOPSIS
    Дашборд статуса всего workspace: OneDrive, Obsidian, Notion, GitHub, Junctions, Task Scheduler.

.DESCRIPTION
    Проверяет и выводит статус всех компонентов workspace:
    - OneDrive: запущен ли процесс, путь синхронизации, размер данных, статус
    - Obsidian Vault: существование vault, количество .md файлов, размер, junction-ссылка, последнее изменение
    - Notion: подключение к API, количество баз данных и страниц
    - GitHub: статус репозитория, последний commit, commits за неделю, ahead/behind
    - Junction Links: чтение junctions.config.json, проверка каждого junction
    - Task Scheduler: задачи MS365*, их статус, следующий запуск, последний результат

    Выводит цветной ASCII-art заголовок, таблицы для каждого компонента,
    итоговый статус All Systems Operational / Issues Found,
    поддерживает экспорт в JSON.

.PARAMETER VaultPath
    Путь к Obsidian Vault. По умолчанию: C:\Obsidian

.PARAMETER JunctionConfigPath
    Путь к конфигурации junction-ссылок. По умолчанию: .\junctions.config.json

.PARAMETER Export
    Сохранить результат в JSON файл.

.PARAMETER ReportPath
    Путь для сохранения JSON-отчёта. По умолчанию: .\reports\

.EXAMPLE
    .\Get-WorkspaceStatus.ps1
    .\Get-WorkspaceStatus.ps1 -Export -ReportPath "C:\Reports"
    .\Get-WorkspaceStatus.ps1 -VaultPath "D:\Obsidian" -Export

.NOTES
    Требования: $env:NOTION_TOKEN для проверки Notion API.
    Зависимости: git (для проверки GitHub статуса).
    Кодировка: UTF-8 with BOM для корректного отображения русского текста.
#>
[CmdletBinding()]
param (
    [string]$VaultPath           = "C:\Obsidian",
    [string]$JunctionConfigPath   = (Join-Path $PSScriptRoot ".." "config" "junctions.config.json"),
    [switch]$Export,
    [string]$ReportPath          = (Join-Path $PSScriptRoot ".." "reports")
)

# ═══════════════════════════════════════════════════════════════
# Константы
# ═══════════════════════════════════════════════════════════════
$ErrorActionPreference = 'Stop'
$script:NotionApiBase = 'https://api.notion.com/v1'
$script:NotionVersion = '2022-06-28'
$script:IssuesFound   = 0

# ═══════════════════════════════════════════════════════════════
# Цветной вывод
# ═══════════════════════════════════════════════════════════════
function Write-StatusLine {
    <#
    .SYNOPSIS
        Выводит одну строку статуса с цветным индикатором.
    #>
    param(
        [string]$Label,
        [string]$Value,
        [ValidateSet('OK','WARN','ERROR','INFO','SKIP')][string]$Status = 'INFO'
    )
    $color = switch ($Status) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'INFO'  { 'Cyan' }
        'SKIP'  { 'DarkGray' }
    }
    $icon = switch ($Status) {
        'OK'    { '[OK]' }
        'WARN'  { '[!] ' }
        'ERROR' { '[X]' }
        'INFO'  { '[i]' }
        'SKIP'  { '[-]' }
    }
    Write-Host "  $($icon.PadRight(5)) " -ForegroundColor $color -NoNewline
    Write-Host "${Label}: " -ForegroundColor Gray -NoNewline
    Write-Host $Value -ForegroundColor White
}

function Write-Section {
    <#
    .SYNOPSIS
        Выводит заголовок секции с разделителем.
    #>
    param(
        [string]$Title,
        [ValidateSet('header','section')][string]$Type = 'section'
    )
    $color = if ($Type -eq 'header') { 'Magenta' } else { 'Cyan' }
    $width = 60
    $line = '=' * $width
    Write-Host ""
    Write-Host $line -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor $color
    Write-Host $line -ForegroundColor DarkGray
}

function Write-AsciiHeader {
    <#
    .SYNOPSIS
        Выводит цветной ASCII-art заголовок дашборда.
    #>
    $header = @'

    __  __  ____   _____ _    _  ____   _____ _______       _____ _______ 
   |  \/  |/ __ \ / ____| |  | |/ __ \ / ____|__   __|/\   / ____|__   __|
   | \  / | |  | | (___ | |__| | |  | | (___    | |  /  \ | |       | |   
   | |\/| | |  | |\___ \|  __  | |  | |\___ \   | | / /\ \| |       | |   
   | |  | | |__| |____) | |  | | |__| |____) |  | |/ ____ \ |____   | |   
   |_|  |_|\____/|_____/|_|  |_|\____/|_____/   |_/_/    \_\_____|  |_|   
                                                                          
       W O R K S P A C E   S T A T U S   D A S H B O A R D               

'@
    Write-Host $header -ForegroundColor Cyan
}

function Add-Issue {
    <#
    .SYNOPSIS
        Увеличивает счётчик проблем для итогового статуса.
    #>
    param([int]$Count = 1)
    $script:IssuesFound += $Count
}

# ═══════════════════════════════════════════════════════════════
# Сборщики данных — OneDrive
# ═══════════════════════════════════════════════════════════════
function Get-OneDriveStatus {
    <#
    .SYNOPSIS
        Проверяет статус OneDrive: процесс, путь синхронизации, размер, статус.
    .RETURNS
        Hashtable с полями: ProcessStatus, SyncPath, SyncPathExists, DataSizeGB,
        LastSync, FreeSpaceGB, TotalSpaceGB, Status (Running/Not Running/Syncing/Error)
    #>
    $result = @{
        Component     = 'OneDrive'
        ProcessStatus = 'Not Running'
        SyncPath      = $null
        SyncPathExists = $false
        DataSizeGB    = $null
        LastSync      = $null
        FreeSpaceGB   = $null
        TotalSpaceGB  = $null
        Status        = 'Error'
        Error         = $null
    }

    try {
        $proc = Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue
        if ($proc) {
            $result.ProcessStatus = 'Running'
            $result.Status        = 'Running'
        } else {
            $result.ProcessStatus = 'Not Running'
            $result.Status        = 'Not Running'
        }

        $odPaths = @(
            $env:OneDrive,
            "$env:USERPROFILE\OneDrive",
            "$env:USERPROFILE\OneDrive - $($env:USERDOMAIN)",
            "$env:USERPROFILE\OneDrive - Personal"
        )
        foreach ($p in $odPaths) {
            if ($p -and (Test-Path -Path $p)) {
                $result.SyncPath      = $p
                $result.SyncPathExists = $true
                break
            }
        }

        if ($result.SyncPath -and (Test-Path $result.SyncPath)) {
            try {
                $folderSize = (Get-ChildItem -Path $result.SyncPath -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                $result.DataSizeGB = [math]::Round($folderSize / 1GB, 2)
            } catch {
                $result.DataSizeGB = 'N/A'
            }
        }

        if ($result.SyncPath) {
            try {
                $drive    = Split-Path -Path $result.SyncPath -Qualifier
                $disk     = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction SilentlyContinue
                if ($disk) {
                    $result.FreeSpaceGB  = [math]::Round($disk.FreeSpace / 1GB, 2)
                    $result.TotalSpaceGB = [math]::Round($disk.Size / 1GB, 2)
                }
            } catch { }
        }

        try {
            $regPath = 'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1'
            if (Test-Path -Path $regPath) {
                $lastSync = Get-ItemPropertyValue -Path $regPath -Name 'LastSyncTime' -ErrorAction SilentlyContinue
                if ($lastSync) {
                    $result.LastSync = [DateTime]::FromFileTime($lastSync).ToString('yyyy-MM-dd HH:mm')
                    if ($result.Status -eq 'Running') {
                        $result.Status = 'Syncing'
                    }
                }
            }
        } catch { }

    } catch {
        $result.Status = 'Error'
        $result.Error  = $_.Exception.Message
    }

    return $result
}

# ═══════════════════════════════════════════════════════════════
# Сборщики данных — Obsidian Vault
# ═══════════════════════════════════════════════════════════════
function Get-ObsidianVaultStatus {
    <#
    .SYNOPSIS
        Проверяет статус Obsidian Vault: существование, .md файлы, размер,
        junction-ссылка, последнее изменение.
    .RETURNS
        Hashtable с полями: VaultPath, Exists, IsJunction, JunctionTarget,
        MdFileCount, VaultSizeMB, LastModified, Status
    #>
    param([string]$VaultPath)

    $result = @{
        Component     = 'ObsidianVault'
        VaultPath     = $VaultPath
        Exists        = $false
        IsJunction    = $false
        JunctionTarget = $null
        MdFileCount   = 0
        VaultSizeMB   = 0
        LastModified  = $null
        Status        = 'Missing'
        Error         = $null
    }

    try {
        if (-not (Test-Path -Path $VaultPath)) {
            $result.Status = 'Missing'
            return $result
        }

        $result.Exists = $true
        $item          = Get-Item -Path $VaultPath -Force

        $result.IsJunction = $item.Attributes -match 'ReparsePoint'
        if ($result.IsJunction) {
            try {
                $result.JunctionTarget = (Get-Item -Path $VaultPath).Target
            } catch {
                $result.JunctionTarget = 'Unknown'
            }
        }

        $mdFiles = Get-ChildItem -Path $VaultPath -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\\.obsidian\\' -and $_.FullName -notmatch '\\\.git\\' }

        $result.MdFileCount = $mdFiles.Count

        $allFiles = Get-ChildItem -Path $VaultPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\\.obsidian\\' -and $_.FullName -notmatch '\\\.git\\' }

        $totalBytes          = ($allFiles | Measure-Object -Property Length -Sum).Sum
        $result.VaultSizeMB  = [math]::Round($totalBytes / 1MB, 2)

        $newestFile          = $mdFiles | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
        if ($newestFile) {
            $result.LastModified = $newestFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        }

        $result.Status = 'OK'

    } catch {
        $result.Status = 'Error'
        $result.Error  = $_.Exception.Message
    }

    return $result
}

# ═══════════════════════════════════════════════════════════════
# Сборщики данных — Notion API
# ═══════════════════════════════════════════════════════════════
function Get-NotionConnectionStatus {
    <#
    .SYNOPSIS
        Проверяет подключение к Notion API: токен, количество баз данных и страниц.
    .RETURNS
        Hashtable с полями: Status (Connected/No Token/Error),
        DatabaseCount, PageCount, Error
    #>
    $result = @{
        Component     = 'Notion'
        Status        = 'No Token'
        DatabaseCount = 0
        PageCount     = 0
        Error         = $null
    }

    if ([string]::IsNullOrWhiteSpace($env:NOTION_TOKEN)) {
        $result.Status = 'No Token'
        return $result
    }

    try {
        $headers = @{
            'Authorization'  = "Bearer $($env:NOTION_TOKEN)"
            'Notion-Version' = $script:NotionVersion
        }

        try {
            $dbResponse = Invoke-RestMethod -Method GET `
                -Uri "$script:NotionApiBase/databases" `
                -Headers $headers `
                -TimeoutSec 15
            $result.DatabaseCount = $dbResponse.results.Count
        } catch {
            $result.DatabaseCount = 'N/A'
        }

        try {
            $searchBody = @{
                query     = ''
                page_size = 100
            } | ConvertTo-Json

            $searchResponse = Invoke-RestMethod -Method POST `
                -Uri "$script:NotionApiBase/search" `
                -Headers $headers `
                -Body $searchBody `
                -TimeoutSec 15

            $result.PageCount = ($searchResponse.results | Where-Object { $_.object -eq 'page' }).Count
        } catch {
            $result.PageCount = 'N/A'
        }

        $result.Status = 'Connected'

    } catch {
        $result.Status = 'Error'
        $result.Error  = $_.Exception.Message
    }

    return $result
}

# ═══════════════════════════════════════════════════════════════
# Сборщики данных — GitHub
# ═══════════════════════════════════════════════════════════════
function Get-GitHubRepoStatus {
    <#
    .SYNOPSIS
        Проверяет статус GitHub репозитория: git status, последний commit,
        количество commits за неделю, ahead/behind.
    .RETURNS
        Hashtable с полями: HasRepo, SyncStatus (Synced/Ahead/Behind/No repo),
        LastCommitHash, LastCommitDate, LastCommitMsg, CommitsThisWeek,
        Branch, ModifiedFiles, UntrackedFiles, RemoteUrl
    #>
    param([string]$RepoPath)

    $result = @{
        Component       = 'GitHub'
        HasRepo         = $false
        SyncStatus      = 'No repo'
        LastCommitHash  = $null
        LastCommitDate  = $null
        LastCommitMsg   = $null
        CommitsThisWeek = 0
        Branch          = $null
        ModifiedFiles   = 0
        UntrackedFiles  = 0
        RemoteUrl       = $null
        Error           = $null
    }

    try {
        $gitDir = Join-Path -Path $RepoPath -ChildPath '.git'
        if (-not (Test-Path -Path $gitDir)) {
            $result.HasRepo    = $false
            $result.SyncStatus = 'No repo'
            return $result
        }

        $result.HasRepo = $true

        function Invoke-GitCmd {
            param([string[]]$GitArgs, [int]$TimeoutMs = 5000)
            $psi                           = New-Object -TypeName System.Diagnostics.ProcessStartInfo
            $psi.FileName                  = 'git'
            $psi.Arguments                 = $GitArgs -join ' '
            $psi.WorkingDirectory          = $RepoPath
            $psi.RedirectStandardOutput    = $true
            $psi.RedirectStandardError     = $true
            $psi.UseShellExecute           = $false
            $psi.CreateNoWindow            = $true
            $psi.StandardOutputEncoding    = [System.Text.Encoding]::UTF8

            $proc    = [System.Diagnostics.Process]::Start($psi)
            $stdout  = $proc.StandardOutput.ReadToEnd()
            $proc.WaitForExit($TimeoutMs) | Out-Null
            return @{ ExitCode = $proc.ExitCode; Output = $stdout.Trim() }
        }

        $statusResult = Invoke-GitCmd -GitArgs @('status', '--porcelain')
        if ($statusResult.ExitCode -eq 0 -and $statusResult.Output) {
            $lines                    = $statusResult.Output -split "`r?`n" | Where-Object { $_ }
            $result.UntrackedFiles    = ($lines | Where-Object { $_ -match '^\?\?' }).Count
            $result.ModifiedFiles     = ($lines | Where-Object { $_ -match '^ M|^M|^ D|^D' }).Count
        }

        $lastCommit = Invoke-GitCmd -GitArgs @('log', '-1', '--format=%H|%ci|%s')
        if ($lastCommit.ExitCode -eq 0 -and $lastCommit.Output) {
            $parts                  = $lastCommit.Output -split '\|', 3
            $result.LastCommitHash  = if ($parts[0]) { $parts[0].Substring(0, 8) } else { 'N/A' }
            $result.LastCommitDate  = $parts[1]
            $result.LastCommitMsg   = $parts[2]
        }

        $branchResult = Invoke-GitCmd -GitArgs @('branch', '--show-current')
        if ($branchResult.ExitCode -eq 0) {
            $result.Branch = $branchResult.Output
        }

        $remoteResult = Invoke-GitCmd -GitArgs @('remote', 'get-url', 'origin')
        if ($remoteResult.ExitCode -eq 0) {
            $result.RemoteUrl = $remoteResult.Output
        }

        $weekAgo      = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd')
        $weekCommits  = Invoke-GitCmd -GitArgs @('log', "--since=$weekAgo", '--oneline')
        if ($weekCommits.ExitCode -eq 0 -and $weekCommits.Output) {
            $result.CommitsThisWeek = ($weekCommits.Output -split "`r?`n" | Where-Object { $_ }).Count
        }

        $aheadResult  = Invoke-GitCmd -GitArgs @('rev-list', '--count', '@{upstream}..HEAD')
        $behindResult = Invoke-GitCmd -GitArgs @('rev-list', '--count', 'HEAD..@{upstream}')
        if ($aheadResult.ExitCode -eq 0 -and $behindResult.ExitCode -eq 0) {
            $ahead  = [int]$aheadResult.Output
            $behind = [int]$behindResult.Output
            if ($ahead -gt 0 -and $behind -eq 0) {
                $result.SyncStatus = 'Ahead'
            } elseif ($behind -gt 0 -and $ahead -eq 0) {
                $result.SyncStatus = 'Behind'
            } elseif ($ahead -gt 0 -and $behind -gt 0) {
                $result.SyncStatus = 'Diverged'
            } else {
                $result.SyncStatus = 'Synced'
            }
        } else {
            if ($result.ModifiedFiles -gt 0 -or $result.UntrackedFiles -gt 0) {
                $result.SyncStatus = 'Uncommitted'
            } else {
                $result.SyncStatus = 'Synced'
            }
        }

    } catch {
        $result.Error  = $_.Exception.Message
        $result.Status = 'Error'
    }

    return $result
}

# ═══════════════════════════════════════════════════════════════
# Сборщики данных — Junction Links
# ═══════════════════════════════════════════════════════════════
function Get-JunctionLinksStatus {
    <#
    .SYNOPSIS
        Читает junctions.config.json и проверяет каждый junction:
        Test-Path + Attributes (ReparsePoint).
    .RETURNS
        Массив объектов с полями: Name, Path, Target, Exists, IsJunction, Status
    #>
    param([string]$ConfigPath)

    $junctions = @()

    $configLocations = @(
        $ConfigPath,
        (Join-Path $PSScriptRoot ".." "config" "junctions.config.json"),
        (Join-Path $PSScriptRoot "junctions.config.json")
    )

    $foundConfig = $null
    foreach ($loc in $configLocations) {
        if (Test-Path -Path $loc) {
            $foundConfig = $loc
            break
        }
    }

    if (-not $foundConfig) {
        try {
            if (Test-Path $VaultPath) {
                $item = Get-Item -Path $VaultPath -Force
                $isJunction = $item.Attributes -match 'ReparsePoint'
                $junctions += [PSCustomObject]@{
                    Name       = 'VaultPath'
                    Path       = $VaultPath
                    Target     = if ($isJunction) { (Get-Item $VaultPath).Target } else { 'N/A' }
                    Exists     = $true
                    IsJunction = $isJunction
                    Status     = if ($isJunction) { 'OK' } else { 'NOT_JUNCTION' }
                }
            } else {
                $junctions += [PSCustomObject]@{
                    Name       = 'VaultPath'
                    Path       = $VaultPath
                    Target     = $null
                    Exists     = $false
                    IsJunction = $false
                    Status     = 'MISSING'
                }
            }
        } catch {
            $junctions += [PSCustomObject]@{
                Name       = 'VaultPath'
                Path       = $VaultPath
                Target     = $null
                Exists     = $false
                IsJunction = $false
                Status     = "ERROR: $($_.Exception.Message)"
            }
        }
        return $junctions
    }

    try {
        $config = Get-Content -Path $foundConfig -Raw -Encoding UTF8 | ConvertFrom-Json

        foreach ($junction in $config.junctions) {
            try {
                $path = $junction.path
                $target = $junction.target
                $name   = $junction.name

                if (-not (Test-Path -Path $path)) {
                    $junctions += [PSCustomObject]@{
                        Name       = $name
                        Path       = $path
                        Target     = $target
                        Exists     = $false
                        IsJunction = $false
                        Status     = 'MISSING'
                    }
                    continue
                }

                $item       = Get-Item -Path $path -Force
                $isJunction = $item.Attributes -match 'ReparsePoint'

                if (-not $isJunction) {
                    $junctions += [PSCustomObject]@{
                        Name       = $name
                        Path       = $path
                        Target     = $target
                        Exists     = $true
                        IsJunction = $false
                        Status     = 'NOT_JUNCTION'
                    }
                    continue
                }

                $actualTarget = $null
                try { $actualTarget = (Get-Item -Path $path).Target } catch { }

                $targetExists = if ($actualTarget) { Test-Path -Path $actualTarget } else { $false }

                $junctions += [PSCustomObject]@{
                    Name       = $name
                    Path       = $path
                    Target     = "$target -> $actualTarget"
                    Exists     = $true
                    IsJunction = $true
                    Status     = if ($targetExists) { 'OK' } else { 'BROKEN_TARGET' }
                }

            } catch {
                $junctions += [PSCustomObject]@{
                    Name       = if ($junction.name) { $junction.name } else { 'Unknown' }
                    Path       = if ($junction.path) { $junction.path } else { 'Unknown' }
                    Target     = $null
                    Exists     = $false
                    IsJunction = $false
                    Status     = "ERROR: $($_.Exception.Message)"
                }
            }
        }

    } catch {
        Write-StatusLine 'Junction Config' "Ошибка чтения конфига: $($_.Exception.Message)" 'ERROR'
    }

    return $junctions
}

# ═══════════════════════════════════════════════════════════════
# Сборщики данных — Task Scheduler
# ═══════════════════════════════════════════════════════════════
function Get-TaskSchedulerStatus {
    <#
    .SYNOPSIS
        Получает задачи Task Scheduler с именем MS365* и их статус.
    .RETURNS
        Массив объектов с полями: Name, State, NextRunTime, LastRunTime, LastResult
    #>
    $tasks = @()

    try {
        $foundTasks = Get-ScheduledTask -TaskName 'MS365*' -ErrorAction SilentlyContinue

        if (-not $foundTasks) {
            return $tasks
        }

        foreach ($task in $foundTasks) {
            try {
                $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -ErrorAction SilentlyContinue

                $tasks += [PSCustomObject]@{
                    Name       = $task.TaskName
                    State      = $task.State.ToString()
                    NextRun    = if ($info.NextRunTime) { $info.NextRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'N/A' }
                    LastRun    = if ($info.LastRunTime) { $info.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'N/A' }
                    LastResult = if ($info.LastTaskResult -eq 0) { 'Success (0)' } else { "Code: $($info.LastTaskResult)" }
                    Exists     = $true
                }
            } catch {
                $tasks += [PSCustomObject]@{
                    Name       = $task.TaskName
                    State      = 'Error'
                    NextRun    = 'N/A'
                    LastRun    = 'N/A'
                    LastResult = 'N/A'
                    Exists     = $true
                }
            }
        }

    } catch {
        # Не удалось получить задачи
    }

    return $tasks
}

# ═══════════════════════════════════════════════════════════════
# Основная логика
# ═══════════════════════════════════════════════════════════════
try {
    $report = @{
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        System    = @{
            ComputerName = $env:COMPUTERNAME
            UserName     = $env:USERNAME
            PowerShell   = $PSVersionTable.PSVersion.ToString()
        }
        Summary   = @{
            TotalComponents = 6
            IssuesFound     = 0
            OverallStatus   = 'All Systems Operational'
        }
        OneDrive  = $null
        Obsidian  = $null
        Notion    = $null
        GitHub    = $null
        Junctions = @()
        Tasks     = @()
    }

    Write-AsciiHeader
    Write-Host "  Generated: $($report.Timestamp)" -ForegroundColor Gray
    Write-Host "  System:    $($report.System.ComputerName) | $($report.System.UserName)" -ForegroundColor Gray
    Write-Host "  Vault:     $VaultPath" -ForegroundColor Gray
    Write-Host ""

    # 1. ONEDRIVE
    Write-Section -Title '☁️  ONEDRIVE STATUS' -Type 'section'
    $od = Get-OneDriveStatus
    $report.OneDrive = $od

    Write-StatusLine -Label 'Process' -Value $od.ProcessStatus `
        -Status $(if ($od.ProcessStatus -eq 'Running') { 'OK' } else { 'WARN' })

    Write-StatusLine -Label 'Sync Folder' -Value $(if ($od.SyncPath) { $od.SyncPath } else { 'Not found' }) `
        -Status $(if ($od.SyncPathExists) { 'OK' } else { 'WARN' })

    if ($od.DataSizeGB) {
        Write-StatusLine -Label 'Data Size' -Value "$($od.DataSizeGB) GB" -Status 'INFO'
    }

    if ($od.LastSync) {
        Write-StatusLine -Label 'Last Sync' -Value $od.LastSync -Status 'INFO'
    } else {
        Write-StatusLine -Label 'Last Sync' -Value 'N/A' -Status 'SKIP'
    }

    if ($od.FreeSpaceGB -and $od.TotalSpaceGB) {
        $usedPct   = [math]::Round(($od.TotalSpaceGB - $od.FreeSpaceGB) / $od.TotalSpaceGB * 100, 1)
        $diskColor = if ($usedPct -gt 90) { 'ERROR' } elseif ($usedPct -gt 75) { 'WARN' } else { 'OK' }
        Write-StatusLine -Label 'Disk Space' `
            -Value "$od.FreeSpaceGB GB free / $od.TotalSpaceGB GB total (${usedPct}% used)" `
            -Status $diskColor
    }

    $odTable = @($od) | Select-Object -Property `
        @{N='Status'; E={$_.ProcessStatus}},
        @{N='SyncPath'; E={if ($_.SyncPath) { $_.SyncPath } else { 'N/A' }}},
        @{N='DataSizeGB'; E={if ($_.DataSizeGB) { $_.DataSizeGB } else { 'N/A' }}},
        @{N='LastSync'; E={if ($_.LastSync) { $_.LastSync } else { 'N/A' }}}
    Write-Host ""
    $odTable | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" -ForegroundColor White }

    if ($od.ProcessStatus -ne 'Running') { Add-Issue }

    # 2. OBSIDIAN VAULT
    Write-Section -Title '📝 OBSIDIAN VAULT STATUS' -Type 'section'
    $obs = Get-ObsidianVaultStatus -VaultPath $VaultPath
    $report.Obsidian = $obs

    if ($obs.Exists) {
        Write-StatusLine -Label 'Vault Path' -Value $obs.VaultPath -Status 'OK'
        Write-StatusLine -Label 'Is Junction' `
            -Value $(if ($obs.IsJunction) { "Yes -> $($obs.JunctionTarget)" } else { 'No' }) `
            -Status $(if ($obs.IsJunction) { 'OK' } else { 'WARN' })
        Write-StatusLine -Label 'MD Files' -Value $obs.MdFileCount -Status 'INFO'
        Write-StatusLine -Label 'Vault Size' -Value "$($obs.VaultSizeMB) MB" -Status 'INFO'
        Write-StatusLine -Label 'Last Modified' -Value $(if ($obs.LastModified) { $obs.LastModified } else { 'N/A' }) -Status 'INFO'
    } else {
        Write-StatusLine -Label 'Vault' -Value "Not found: $VaultPath" -Status 'ERROR'
        Add-Issue
    }

    $obsTable = @($obs) | Select-Object -Property `
        @{N='Exists'; E={$_.Exists}},
        @{N='IsJunction'; E={$_.IsJunction}},
        @{N='MdFiles'; E={$_.MdFileCount}},
        @{N='SizeMB'; E={$_.VaultSizeMB}},
        @{N='LastModified'; E={if ($_.LastModified) { $_.LastModified } else { 'N/A' }}}
    Write-Host ""
    $obsTable | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" -ForegroundColor White }

    if (-not $obs.Exists) { Add-Issue }

    # 3. NOTION API
    Write-Section -Title '🔗 NOTION CONNECTION' -Type 'section'
    $notion = Get-NotionConnectionStatus
    $report.Notion = $notion

    if ($notion.Status -eq 'Connected') {
        Write-StatusLine -Label 'API Status' -Value 'Connected' -Status 'OK'
        Write-StatusLine -Label 'Databases' -Value $notion.DatabaseCount -Status 'INFO'
        Write-StatusLine -Label 'Pages' -Value $notion.PageCount -Status 'INFO'
    } elseif ($notion.Status -eq 'No Token') {
        Write-StatusLine -Label 'API Status' -Value 'No Token (set $env:NOTION_TOKEN)' -Status 'SKIP'
    } else {
        Write-StatusLine -Label 'API Status' -Value "Error: $($notion.Error)" -Status 'ERROR'
        Add-Issue
    }

    $notionTable = @($notion) | Select-Object -Property `
        @{N='Status'; E={$_.Status}},
        @{N='Databases'; E={$_.DatabaseCount}},
        @{N='Pages'; E={$_.PageCount}}
    Write-Host ""
    $notionTable | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" -ForegroundColor White }

    # 4. GITHUB REPOSITORY
    Write-Section -Title '🐙 GITHUB BACKUP STATUS' -Type 'section'
    $git = Get-GitHubRepoStatus -RepoPath $VaultPath
    $report.GitHub = $git

    if ($git.HasRepo) {
        Write-StatusLine -Label 'Repository' -Value 'Initialized' -Status 'OK'
        Write-StatusLine -Label 'Sync Status' -Value $git.SyncStatus `
            -Status $(switch ($git.SyncStatus) {
                'Synced'       { 'OK' }
                'Ahead'        { 'OK' }
                'Behind'       { 'WARN' }
                'Diverged'     { 'WARN' }
                'Uncommitted'  { 'WARN' }
                default        { 'INFO' }
            })

        if ($git.LastCommitHash) {
            Write-StatusLine -Label 'Last Commit' -Value "$($git.LastCommitHash) | $($git.LastCommitDate)" -Status 'INFO'
            Write-StatusLine -Label 'Message' -Value $git.LastCommitMsg -Status 'INFO'
        }

        Write-StatusLine -Label 'Branch' -Value $(if ($git.Branch) { $git.Branch } else { 'N/A' }) -Status 'INFO'

        if ($git.RemoteUrl) {
            Write-StatusLine -Label 'Remote' -Value $git.RemoteUrl -Status 'OK'
        } else {
            Write-StatusLine -Label 'Remote' -Value 'Not configured' -Status 'WARN'
        }

        Write-StatusLine -Label 'Commits (7d)' -Value $git.CommitsThisWeek -Status 'INFO'

        if ($git.UntrackedFiles -gt 0) {
            Write-StatusLine -Label 'Untracked' -Value "$($git.UntrackedFiles) files" -Status 'WARN'
        }
        if ($git.ModifiedFiles -gt 0) {
            Write-StatusLine -Label 'Modified' -Value "$($git.ModifiedFiles) files" -Status 'WARN'
        }
    } else {
        Write-StatusLine -Label 'Repository' -Value 'Not initialized' -Status 'WARN'
        Add-Issue
    }

    $gitTable = @($git) | Select-Object -Property `
        @{N='HasRepo'; E={$_.HasRepo}},
        @{N='SyncStatus'; E={$_.SyncStatus}},
        @{N='LastCommit'; E={$_.LastCommitHash}},
        @{N='Branch'; E={if ($_.Branch) { $_.Branch } else { 'N/A' }}},
        @{N='CommitsWeek'; E={$_.CommitsThisWeek}},
        @{N='Modified'; E={$_.ModifiedFiles}},
        @{N='Untracked'; E={$_.UntrackedFiles}}
    Write-Host ""
    $gitTable | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" -ForegroundColor White }

    # 5. JUNCTION LINKS
    Write-Section -Title '🔗 JUNCTION LINKS STATUS' -Type 'section'
    $junctions = Get-JunctionLinksStatus -ConfigPath $JunctionConfigPath
    $report.Junctions = $junctions

    if ($junctions.Count -eq 0) {
        Write-StatusLine -Label 'Junctions' -Value 'No junctions configured' -Status 'SKIP'
    } else {
        foreach ($j in $junctions) {
            $jStatus = switch ($j.Status) {
                'OK'             { 'OK' }
                'MISSING'        { 'ERROR' }
                'NOT_JUNCTION'   { 'WARN' }
                'BROKEN_TARGET'  { 'ERROR' }
                default          { 'ERROR' }
            }
            $jValue = if ($j.IsJunction) {
                "Junction -> $($j.Target)"
            } elseif ($j.Exists) {
                'Regular folder'
            } else {
                'Missing!'
            }
            Write-StatusLine -Label $j.Name -Value $jValue -Status $jStatus

            if ($j.Status -ne 'OK' -and $j.Status -ne 'NOT_JUNCTION') { Add-Issue }
        }
    }

    if ($junctions.Count -gt 0) {
        Write-Host ""
        $junctions | Select-Object -Property Name, Path, Target, Status |
            Format-Table -AutoSize |
            Out-String |
            ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    }

    # 6. TASK SCHEDULER
    Write-Section -Title '📅 TASK SCHEDULER STATUS' -Type 'section'
    $tasks = Get-TaskSchedulerStatus
    $report.Tasks = $tasks

    if ($tasks.Count -eq 0) {
        Write-StatusLine -Label 'Tasks' -Value 'No MS365 tasks found' -Status 'SKIP'
    } else {
        foreach ($t in $tasks) {
            $stateColor = switch ($t.State) {
                'Ready'    { 'OK' }
                'Running'  { 'OK' }
                'Disabled' { 'WARN' }
                default    { 'WARN' }
            }
            Write-StatusLine -Label $t.Name -Value "$($t.State) | Next: $($t.NextRun) | Last: $($t.LastResult)" -Status $stateColor

            if ($t.State -eq 'Disabled') { Add-Issue }
        }

        Write-Host ""
        $tasks | Select-Object -Property Name, State, NextRun, LastRun, LastResult |
            Format-Table -AutoSize |
            Out-String |
            ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    }

    # ФИНАЛЬНАЯ СВОДКА
    Write-Host ""
    Write-Host "  $( '=' * 58 )" -ForegroundColor DarkGray

    $report.Summary.IssuesFound = $script:IssuesFound

    if ($script:IssuesFound -eq 0) {
        $report.Summary.OverallStatus = 'All Systems Operational'
        Write-Host ""
        Write-Host "        ╔══════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "        ║     ALL SYSTEMS OPERATIONAL ✅           ║" -ForegroundColor Green
        Write-Host "        ╚══════════════════════════════════════════╝" -ForegroundColor Green
    } elseif ($script:IssuesFound -le 2) {
        $report.Summary.OverallStatus = 'Issues Found'
        Write-Host ""
        Write-Host "        ╔══════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "        ║     ⚠️  $script:IssuesFound issue(s) found — attention    ║" -ForegroundColor Yellow
        Write-Host "        ╚══════════════════════════════════════════╝" -ForegroundColor Yellow
    } else {
        $report.Summary.OverallStatus = 'Multiple Issues Found'
        Write-Host ""
        Write-Host "        ╔══════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "        ║     ❌ $script:IssuesFound issues — setup required!  ║" -ForegroundColor Red
        Write-Host "        ╚══════════════════════════════════════════╝" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  $( '=' * 58 )" -ForegroundColor DarkGray

    # ЭКСПОРТ В JSON
    if ($Export) {
        if (-not (Test-Path -Path $ReportPath)) {
            New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
        }

        $fileName = "workspace-status-$(Get-Date -Format 'yyyy-MM-dd-HHmm').json"
        $filePath = Join-Path -Path $ReportPath -ChildPath $fileName

        $report | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8
        Write-Host ""
        Write-Host "  💾 Report saved: $filePath" -ForegroundColor Cyan
    }

} catch {
    Write-Host ""
    Write-Host "  ❌ CRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkGray
    exit 1
}

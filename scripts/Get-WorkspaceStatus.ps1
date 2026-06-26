#requires -Version 5.1
<#
.SYNOPSIS
    Дашборд статуса экосистемы ноутбука: OneDrive, Obsidian, Notion, GitHub, Junctions, Task Scheduler.

.DESCRIPTION
    Проверяет и выводит статус всех компонентов экосистемы:
    - OneDrive: процесс, путь синхронизации, размер, статус
    - Obsidian Vault: существование, .md файлы, размер, junction, последнее изменение
    - Notion: подключение к API, базы данных и страницы
    - GitHub: git status, последний commit, commits за неделю
    - Junction Links: проверка каждого junction из конфига
    - Task Scheduler: задачи MS365*, статус, следующий запуск

    Цветной ASCII-art заголовок, таблицы, итоговый статус, экспорт в JSON.

.PARAMETER VaultPath
    Путь к Obsidian Vault. По умолчанию: C:\Obsidian

.PARAMETER Export
    Сохранить результат в JSON файл.

.EXAMPLE
    .\Get-WorkspaceStatus.ps1
    .\Get-WorkspaceStatus.ps1 -Export
#>
[CmdletBinding()]
param (
    [string]$VaultPath = "C:\Obsidian",
    [switch]$Export,
    [string]$ReportPath = (Join-Path $PSScriptRoot ".." "reports")
)

$ErrorActionPreference = 'Continue'
$script:NotionApiBase = 'https://api.notion.com/v1'
$script:NotionVersion = '2022-06-28'
$script:IssuesFound = 0

function Write-StatusLine {
    param([string]$Label, [string]$Value, [ValidateSet('OK','WARN','ERROR','INFO','SKIP')][string]$Status = 'INFO')
    $color = switch ($Status) { 'OK' { 'Green' }; 'WARN' { 'Yellow' }; 'ERROR' { 'Red' }; 'INFO' { 'Cyan' }; 'SKIP' { 'DarkGray' } }
    $icon = switch ($Status) { 'OK' { '[OK]' }; 'WARN' { '[!] ' }; 'ERROR' { '[X]' }; 'INFO' { '[i]' }; 'SKIP' { '[-]' } }
    Write-Host "  $($icon.PadRight(5)) " -ForegroundColor $color -NoNewline
    Write-Host "${Label}: " -ForegroundColor Gray -NoNewline
    Write-Host $Value -ForegroundColor White
}

function Write-Section {
    param([string]$Title, [ValidateSet('header','section')][string]$Type = 'section')
    $color = if ($Type -eq 'header') { 'Magenta' } else { 'Cyan' }
    Write-Host ""; Write-Host "  $( '=' * 58 )" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor $color
    Write-Host "  $( '=' * 58 )" -ForegroundColor DarkGray
}

function Add-Issue { param([int]$Count = 1); $script:IssuesFound += $Count }

function Get-OneDriveStatus {
    $result = @{ Component = 'OneDrive'; ProcessStatus = 'Not Running'; SyncPath = $null; SyncPathExists = $false; DataSizeGB = $null; LastSync = $null; FreeSpaceGB = $null; TotalSpaceGB = $null; Status = 'Error'; Error = $null }
    try {
        $proc = Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue
        if ($proc) { $result.ProcessStatus = 'Running'; $result.Status = 'Running' } else { $result.ProcessStatus = 'Not Running'; $result.Status = 'Not Running' }
        $odPaths = @($env:OneDrive, "$env:USERPROFILE\OneDrive", "$env:USERPROFILE\OneDrive - Personal")
        foreach ($p in $odPaths) { if ($p -and (Test-Path $p)) { $result.SyncPath = $p; $result.SyncPathExists = $true; break } }
        if ($result.SyncPath -and (Test-Path $result.SyncPath)) {
            try { $size = (Get-ChildItem $result.SyncPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; $result.DataSizeGB = [math]::Round($size / 1GB, 2) } catch { $result.DataSizeGB = 'N/A' }
            try { $drive = Split-Path $result.SyncPath -Qualifier; $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction SilentlyContinue; if ($disk) { $result.FreeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2); $result.TotalSpaceGB = [math]::Round($disk.Size / 1GB, 2) } } catch { }
        }
    } catch { $result.Status = 'Error'; $result.Error = $_.Exception.Message }
    return $result
}

function Get-ObsidianVaultStatus {
    param([string]$VaultPath)
    $result = @{ Component = 'ObsidianVault'; VaultPath = $VaultPath; Exists = $false; IsJunction = $false; JunctionTarget = $null; MdFileCount = 0; VaultSizeMB = 0; LastModified = $null; Status = 'Missing'; Error = $null }
    try {
        if (-not (Test-Path $VaultPath)) { return $result }
        $result.Exists = $true; $item = Get-Item $VaultPath -Force
        $result.IsJunction = $item.Attributes -match 'ReparsePoint'
        if ($result.IsJunction) { try { $result.JunctionTarget = (Get-Item $VaultPath).Target } catch { $result.JunctionTarget = 'Unknown' } }
        $mdFiles = Get-ChildItem $VaultPath -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\\.obsidian\\' -and $_.FullName -notmatch '\\\.git\\' }
        $result.MdFileCount = $mdFiles.Count
        $allFiles = Get-ChildItem $VaultPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\\.obsidian\\' -and $_.FullName -notmatch '\\\.git\\' }
        $totalBytes = ($allFiles | Measure-Object -Property Length -Sum).Sum; $result.VaultSizeMB = [math]::Round($totalBytes / 1MB, 2)
        $newest = $mdFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($newest) { $result.LastModified = $newest.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
        $result.Status = 'OK'
    } catch { $result.Status = 'Error'; $result.Error = $_.Exception.Message }
    return $result
}

function Get-NotionConnectionStatus {
    $result = @{ Component = 'Notion'; Status = 'No Token'; DatabaseCount = 0; PageCount = 0; Error = $null }
    if ([string]::IsNullOrWhiteSpace($env:NOTION_TOKEN)) { return $result }
    try {
        $headers = @{ 'Authorization' = "Bearer $($env:NOTION_TOKEN)"; 'Notion-Version' = $script:NotionVersion }
        try { $db = Invoke-RestMethod -Method GET -Uri "$script:NotionApiBase/databases" -Headers $headers -TimeoutSec 15; $result.DatabaseCount = $db.results.Count } catch { $result.DatabaseCount = 'N/A' }
        try { $search = Invoke-RestMethod -Method POST -Uri "$script:NotionApiBase/search" -Headers $headers -Body (@{ query = ''; page_size = 100 } | ConvertTo-Json) -TimeoutSec 15; $result.PageCount = ($search.results | Where-Object { $_.object -eq 'page' }).Count } catch { $result.PageCount = 'N/A' }
        $result.Status = 'Connected'
    } catch { $result.Status = 'Error'; $result.Error = $_.Exception.Message }
    return $result
}

function Get-GitHubRepoStatus {
    param([string]$RepoPath)
    $result = @{ Component = 'GitHub'; HasRepo = $false; SyncStatus = 'No repo'; LastCommitHash = $null; LastCommitDate = $null; LastCommitMsg = $null; CommitsThisWeek = 0; Branch = $null; ModifiedFiles = 0; UntrackedFiles = 0; RemoteUrl = $null; Error = $null }
    try {
        if (-not (Test-Path (Join-Path $RepoPath '.git'))) { return $result }
        $result.HasRepo = $true
        function Invoke-GitCmd($Arguments, $TimeoutMs = 5000) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName = 'git'; $psi.Arguments = $Arguments -join ' '; $psi.WorkingDirectory = $RepoPath; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $proc = [System.Diagnostics.Process]::Start($psi); $stdout = $proc.StandardOutput.ReadToEnd(); $proc.WaitForExit($TimeoutMs) | Out-Null; return @{ ExitCode = $proc.ExitCode; Output = $stdout.Trim() }
        }
        $status = Invoke-GitCmd @('status', '--porcelain'); if ($status.ExitCode -eq 0 -and $status.Output) { $lines = $status.Output -split "`r?`n" | Where-Object { $_ }; $result.UntrackedFiles = ($lines | Where-Object { $_ -match '^\?\?' }).Count; $result.ModifiedFiles = ($lines | Where-Object { $_ -match '^ M|^M|^ D|^D' }).Count }
        $last = Invoke-GitCmd @('log', '-1', '--format=%H|%ci|%s'); if ($last.ExitCode -eq 0 -and $last.Output) { $parts = $last.Output -split '\|', 3; $result.LastCommitHash = if ($parts[0]) { $parts[0].Substring(0, 8) } else { 'N/A' }; $result.LastCommitDate = $parts[1]; $result.LastCommitMsg = $parts[2] }
        $branch = Invoke-GitCmd @('branch', '--show-current'); if ($branch.ExitCode -eq 0) { $result.Branch = $branch.Output }
        $remote = Invoke-GitCmd @('remote', 'get-url', 'origin'); if ($remote.ExitCode -eq 0) { $result.RemoteUrl = $remote.Output }
        $weekAgo = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd'); $week = Invoke-GitCmd @('log', "--since=$weekAgo", '--oneline'); if ($week.ExitCode -eq 0 -and $week.Output) { $result.CommitsThisWeek = ($week.Output -split "`r?`n" | Where-Object { $_ }).Count }
        $ahead = Invoke-GitCmd @('rev-list', '--count', '@{upstream}..HEAD'); $behind = Invoke-GitCmd @('rev-list', '--count', 'HEAD..@{upstream}')
        if ($ahead.ExitCode -eq 0 -and $behind.ExitCode -eq 0) { $a = [int]$ahead.Output; $b = [int]$behind.Output; if ($a -gt 0 -and $b -eq 0) { $result.SyncStatus = 'Ahead' } elseif ($b -gt 0 -and $a -eq 0) { $result.SyncStatus = 'Behind' } elseif ($a -gt 0 -and $b -gt 0) { $result.SyncStatus = 'Diverged' } else { $result.SyncStatus = 'Synced' } } else { $result.SyncStatus = if ($result.ModifiedFiles -gt 0 -or $result.UntrackedFiles -gt 0) { 'Uncommitted' } else { 'Synced' } }
    } catch { $result.Error = $_.Exception.Message; $result.Status = 'Error' }
    return $result
}

function Get-JunctionLinksStatus {
    param([string]$ConfigPath)
    $junctions = @(); $configLocations = @($ConfigPath, (Join-Path $PSScriptRoot "junctions.config.json"), (Join-Path $PSScriptRoot ".." "junctions.config.json"))
    $foundConfig = $null; foreach ($loc in $configLocations) { if (Test-Path $loc) { $foundConfig = $loc; break } }
    if (-not $foundConfig) {
        if (Test-Path $VaultPath) { $item = Get-Item $VaultPath -Force; $isJunction = $item.Attributes -match 'ReparsePoint'; $junctions += [PSCustomObject]@{ Name = 'VaultPath'; Path = $VaultPath; Target = if ($isJunction) { (Get-Item $VaultPath).Target } else { 'N/A' }; Exists = $true; IsJunction = $isJunction; Status = if ($isJunction) { 'OK' } else { 'NOT_JUNCTION' } } }
        else { $junctions += [PSCustomObject]@{ Name = 'VaultPath'; Path = $VaultPath; Target = $null; Exists = $false; IsJunction = $false; Status = 'MISSING' } }
        return $junctions
    }
    try {
        $config = Get-Content $foundConfig -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($j in $config.junctions) {
            try {
                $path = $j.path; $target = $j.target; $name = $j.name
                if (-not (Test-Path $path)) { $junctions += [PSCustomObject]@{ Name = $name; Path = $path; Target = $target; Exists = $false; IsJunction = $false; Status = 'MISSING' }; continue }
                $item = Get-Item $path -Force; $isJunction = $item.Attributes -match 'ReparsePoint'
                if (-not $isJunction) { $junctions += [PSCustomObject]@{ Name = $name; Path = $path; Target = $target; Exists = $true; IsJunction = $false; Status = 'NOT_JUNCTION' }; continue }
                $actualTarget = $null; try { $actualTarget = (Get-Item $path).Target } catch { }; $targetExists = if ($actualTarget) { Test-Path $actualTarget } else { $false }
                $junctions += [PSCustomObject]@{ Name = $name; Path = $path; Target = "$target -> $actualTarget"; Exists = $true; IsJunction = $true; Status = if ($targetExists) { 'OK' } else { 'BROKEN_TARGET' } }
            } catch { $junctions += [PSCustomObject]@{ Name = if ($j.name) { $j.name } else { 'Unknown' }; Path = if ($j.path) { $j.path } else { 'Unknown' }; Target = $null; Exists = $false; IsJunction = $false; Status = "ERROR: $($_.Exception.Message)" } }
        }
    } catch { Write-StatusLine 'Junction Config' "Ошибка чтения конфига: $($_.Exception.Message)" 'ERROR' }
    return $junctions
}

function Get-TaskSchedulerStatus {
    $tasks = @(); try {
        $foundTasks = Get-ScheduledTask -TaskName 'MS365*' -ErrorAction SilentlyContinue
        if (-not $foundTasks) { return $tasks }
        foreach ($task in $foundTasks) {
            try { $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -ErrorAction SilentlyContinue; $tasks += [PSCustomObject]@{ Name = $task.TaskName; State = $task.State.ToString(); NextRun = if ($info.NextRunTime) { $info.NextRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'N/A' }; LastRun = if ($info.LastRunTime) { $info.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'N/A' }; LastResult = if ($info.LastTaskResult -eq 0) { 'Success (0)' } else { "Code: $($info.LastTaskResult)" }; Exists = $true } }
            catch { $tasks += [PSCustomObject]@{ Name = $task.TaskName; State = 'Error'; NextRun = 'N/A'; LastRun = 'N/A'; LastResult = 'N/A'; Exists = $true } }
        }
    } catch { }
    return $tasks
}

# ═══════════════════════════════════════════════════════════════
# Главная логика
# ═══════════════════════════════════════════════════════════════
try {
    $report = @{ Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; System = @{ ComputerName = $env:COMPUTERNAME; UserName = $env:USERNAME; PowerShell = $PSVersionTable.PSVersion.ToString() }; Summary = @{ TotalComponents = 6; IssuesFound = 0; OverallStatus = 'All Systems Operational' }; OneDrive = $null; Obsidian = $null; Notion = $null; GitHub = $null; Junctions = @(); Tasks = @() }

    # ASCII Header
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
    Write-Host "  Generated: $($report.Timestamp)" -ForegroundColor Gray
    Write-Host "  System:    $($report.System.ComputerName) | $($report.System.UserName)" -ForegroundColor Gray
    Write-Host "  Vault:     $VaultPath" -ForegroundColor Gray
    Write-Host ""

    # 1. ONEDRIVE
    Write-Section '☁️  ONEDRIVE STATUS'
    $od = Get-OneDriveStatus; $report.OneDrive = $od
    Write-StatusLine 'Process' $od.ProcessStatus $(if ($od.ProcessStatus -eq 'Running') { 'OK' } else { 'WARN' })
    Write-StatusLine 'Sync Folder' $(if ($od.SyncPath) { $od.SyncPath } else { 'Not found' }) $(if ($od.SyncPathExists) { 'OK' } else { 'WARN' })
    if ($od.DataSizeGB) { Write-StatusLine 'Data Size' "$($od.DataSizeGB) GB" 'INFO' }
    if ($od.LastSync) { Write-StatusLine 'Last Sync' $od.LastSync 'INFO' } else { Write-StatusLine 'Last Sync' 'N/A' 'SKIP' }
    if ($od.FreeSpaceGB -and $od.TotalSpaceGB) { $usedPct = [math]::Round(($od.TotalSpaceGB - $od.FreeSpaceGB) / $od.TotalSpaceGB * 100, 1); $diskColor = if ($usedPct -gt 90) { 'ERROR' } elseif ($usedPct -gt 75) { 'WARN' } else { 'OK' }; Write-StatusLine 'Disk Space' "$od.FreeSpaceGB GB free / $od.TotalSpaceGB GB total (${usedPct}% used)" $diskColor }
    if ($od.ProcessStatus -ne 'Running') { Add-Issue }
    $odTable = @($od) | Select-Object @{N='Status'; E={$_.ProcessStatus}}, @{N='SyncPath'; E={if ($_.SyncPath) { $_.SyncPath } else { 'N/A' }}}, @{N='DataSizeGB'; E={if ($_.DataSizeGB) { $_.DataSizeGB } else { 'N/A' }}}, @{N='LastSync'; E={if ($_.LastSync) { $_.LastSync } else { 'N/A' }}}; Write-Host ""; $odTable | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" -ForegroundColor White }

    # 2. OBSIDIAN
    Write-Section '📝 OBSIDIAN VAULT STATUS'
    $obs = Get-ObsidianVaultStatus $VaultPath; $report.Obsidian = $obs
    if ($obs.Exists) {
        Write-StatusLine 'Vault Path' $obs.VaultPath 'OK'
        Write-StatusLine 'Is Junction' $(if ($obs.IsJunction) { "Yes -> $($obs.JunctionTarget)" } else { 'No' }) $(if ($obs.IsJunction) { 'OK' } else { 'WARN' })
        Write-StatusLine 'MD Files' $obs.MdFileCount 'INFO'
        Write-StatusLine 'Vault Size' "$($obs.VaultSizeMB) MB" 'INFO'
        Write-StatusLine 'Last Modified' $(if ($obs.LastModified) { $obs.LastModified } else { 'N/A' }) 'INFO'
    } else { Write-StatusLine 'Vault' "Not found: $VaultPath" 'ERROR'; Add-Issue }
    $obsTable = @($obs) | Select-Object @{N='Exists'; E={$_.Exists}}, @{N='IsJunction'; E={$_.IsJunction}}, @{N='MdFiles'; E={$_.MdFileCount}}, @{N='SizeMB'; E={$_.VaultSizeMB}}, @{N='LastModified'; E={if ($_.LastModified) { $_.LastModified } else { 'N/A' }}}; Write-Host ""; $obsTable | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    if (-not $obs.Exists) { Add-Issue }

    # 3. NOTION
    Write-Section '🔗 NOTION CONNECTION'
    $notion = Get-NotionConnectionStatus; $report.Notion = $notion
    if ($notion.Status -eq 'Connected') { Write-StatusLine 'API Status' 'Connected' 'OK'; Write-StatusLine 'Databases' $notion.DatabaseCount 'INFO'; Write-StatusLine 'Pages' $notion.PageCount 'INFO' }
    elseif ($notion.Status -eq 'No Token') { Write-StatusLine 'API Status' 'No Token (set $env:NOTION_TOKEN)' 'SKIP' }
    else { Write-StatusLine 'API Status' "Error: $($notion.Error)" 'ERROR'; Add-Issue }
    $notionTable = @($notion) | Select-Object @{N='Status'; E={$_.Status}}, @{N='Databases'; E={$_.DatabaseCount}}, @{N='Pages'; E={$_.PageCount}}; Write-Host ""; $notionTable | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" -ForegroundColor White }

    # 4. GITHUB
    Write-Section '🐙 GITHUB BACKUP STATUS'
    $git = Get-GitHubRepoStatus $VaultPath; $report.GitHub = $git
    if ($git.HasRepo) {
        Write-StatusLine 'Repository' 'Initialized' 'OK'
        Write-StatusLine 'Sync Status' $git.SyncStatus $(switch ($git.SyncStatus) { 'Synced' { 'OK' }; 'Ahead' { 'OK' }; 'Behind' { 'WARN' }; 'Diverged' { 'WARN' }; 'Uncommitted' { 'WARN' }; default { 'INFO' } })
        if ($git.LastCommitHash) { Write-StatusLine 'Last Commit' "$($git.LastCommitHash) | $($git.LastCommitDate)" 'INFO'; Write-StatusLine 'Message' $git.LastCommitMsg 'INFO' }
        Write-StatusLine 'Branch' $(if ($git.Branch) { $git.Branch } else { 'N/A' }) 'INFO'
        if ($git.RemoteUrl) { Write-StatusLine 'Remote' $git.RemoteUrl 'OK' } else { Write-StatusLine 'Remote' 'Not configured' 'WARN' }
        Write-StatusLine 'Commits (7d)' $git.CommitsThisWeek 'INFO'
        if ($git.UntrackedFiles -gt 0) { Write-StatusLine 'Untracked' "$($git.UntrackedFiles) files" 'WARN' }
        if ($git.ModifiedFiles -gt 0) { Write-StatusLine 'Modified' "$($git.ModifiedFiles) files" 'WARN' }
    } else { Write-StatusLine 'Repository' 'Not initialized' 'WARN'; Add-Issue }
    $gitTable = @($git) | Select-Object @{N='HasRepo'; E={$_.HasRepo}}, @{N='SyncStatus'; E={$_.SyncStatus}}, @{N='LastCommit'; E={$_.LastCommitHash}}, @{N='Branch'; E={if ($_.Branch) { $_.Branch } else { 'N/A' }}}, @{N='CommitsWeek'; E={$_.CommitsThisWeek}}, @{N='Modified'; E={$_.ModifiedFiles}}, @{N='Untracked'; E={$_.UntrackedFiles}}; Write-Host ""; $gitTable | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" -ForegroundColor White }

    # 5. JUNCTIONS
    Write-Section '🔗 JUNCTION LINKS STATUS'
    $junctions = Get-JunctionLinksStatus $JunctionConfigPath; $report.Junctions = $junctions
    if ($junctions.Count -eq 0) { Write-StatusLine 'Junctions' 'No junctions configured' 'SKIP' }
    else { foreach ($j in $junctions) { $jStatus = switch ($j.Status) { 'OK' { 'OK' }; 'MISSING' { 'ERROR' }; 'NOT_JUNCTION' { 'WARN' }; 'BROKEN_TARGET' { 'ERROR' }; default { 'ERROR' } }; $jValue = if ($j.IsJunction) { "Junction -> $($j.Target)" } elseif ($j.Exists) { 'Regular folder' } else { 'Missing!' }; Write-StatusLine $j.Name $jValue $jStatus; if ($j.Status -ne 'OK' -and $j.Status -ne 'NOT_JUNCTION') { Add-Issue } } }
    if ($junctions.Count -gt 0) { Write-Host ""; $junctions | Select-Object Name, Path, Target, Status | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" -ForegroundColor White } }

    # 6. TASK SCHEDULER
    Write-Section '📅 TASK SCHEDULER STATUS'
    $tasks = Get-TaskSchedulerStatus; $report.Tasks = $tasks
    if ($tasks.Count -eq 0) { Write-StatusLine 'Tasks' 'No MS365 tasks found' 'SKIP' }
    else { foreach ($t in $tasks) { $stateColor = switch ($t.State) { 'Ready' { 'OK' }; 'Running' { 'OK' }; 'Disabled' { 'WARN' }; default { 'WARN' } }; Write-StatusLine $t.Name "$($t.State) | Next: $($t.NextRun) | Last: $($t.LastResult)" $stateColor; if ($t.State -eq 'Disabled') { Add-Issue } } }
    if ($tasks.Count -gt 0) { Write-Host ""; $tasks | Select-Object Name, State, NextRun, LastRun, LastResult | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" -ForegroundColor White } }

    # ФИНАЛЬНАЯ СВОДКА
    Write-Host ""; Write-Host "  $( '=' * 58 )" -ForegroundColor DarkGray
    $report.Summary.IssuesFound = $script:IssuesFound
    if ($script:IssuesFound -eq 0) { $report.Summary.OverallStatus = 'All Systems Operational'; Write-Host ""; Write-Host "        ╔══════════════════════════════════════════╗" -ForegroundColor Green; Write-Host "        ║     ALL SYSTEMS OPERATIONAL ✅           ║" -ForegroundColor Green; Write-Host "        ╚══════════════════════════════════════════╝" -ForegroundColor Green }
    elseif ($script:IssuesFound -le 2) { $report.Summary.OverallStatus = 'Issues Found'; Write-Host ""; Write-Host "        ╔══════════════════════════════════════════╗" -ForegroundColor Yellow; Write-Host "        ║     ⚠️  $script:IssuesFound issue(s) found — attention    ║" -ForegroundColor Yellow; Write-Host "        ╚══════════════════════════════════════════╝" -ForegroundColor Yellow }
    else { $report.Summary.OverallStatus = 'Multiple Issues Found'; Write-Host ""; Write-Host "        ╔══════════════════════════════════════════╗" -ForegroundColor Red; Write-Host "        ║     ❌ $script:IssuesFound issues — setup required!  ║" -ForegroundColor Red; Write-Host "        ╚══════════════════════════════════════════╝" -ForegroundColor Red }
    Write-Host ""; Write-Host "  $( '=' * 58 )" -ForegroundColor DarkGray

    if ($Export) { if (-not (Test-Path $ReportPath)) { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }; $fn = "workspace-status-$(Get-Date -Format 'yyyy-MM-dd-HHmm').json"; $fp = Join-Path $ReportPath $fn; $report | ConvertTo-Json -Depth 10 | Set-Content $fp -Encoding UTF8; Write-Host ""; Write-Host "  💾 Report saved: $fp" -ForegroundColor Cyan }

} catch {
    Write-Host ""; Write-Host "  ❌ CRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red; Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkGray; exit 1
}

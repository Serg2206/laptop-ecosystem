#Requires -Version 5.1
<#
.SYNOPSIS
    Automated Git backup system for the laptop ecosystem.
.DESCRIPTION
    Backs up workspace files to GitHub with smart change detection,
    auto-initialization, and detailed logging.
.PARAMETER RepoUrl
    The GitHub repository URL to push backups to.
.PARAMETER BackupPath
    The local directory to back up.
.PARAMETER LogPath
    Directory for log files.
.PARAMETER Force
    Force backup even if minimum interval has not passed.
.PARAMETER DryRun
    Show what would be backed up without making changes.
.EXAMPLE
    .\Backup-ToGitHub.ps1 -Force
    Forces an immediate backup.
#>

[CmdletBinding()]
param(
    [string]$RepoUrl = "https://github.com/Serg2206/laptop-ecosystem.git",
    [string]$BackupPath = "$env:USERPROFILE\Workspace",
    [string]$LogPath = "$env:USERPROFILE\.laptop-ecosystem\logs",
    [switch]$Force,
    [switch]$DryRun
)

# Configuration
$script:Config = @{
    MaxRetries = 3
    RetryDelaySec = 5
    GitTimeoutSec = 120
    ExcludedPaths = @('.git', 'node_modules', '.obsidian', 'temp', 'tmp', 'cache')
    MinBackupIntervalMinutes = 30
    LogRetentionDays = 30
}

# Color output helpers
function Write-StatusLine {
    param([string]$Icon, [string]$Message, [string]$Color = "White")
    $colors = @{ "Green" = "Green"; "Red" = "Red"; "Yellow" = "Yellow"; "Cyan" = "Cyan" }
    Write-Host "$Icon $Message" -ForegroundColor $colors[$Color]
}

# Logging helper
function Write-Log {
    param([string]$Level = "INFO", [string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logFile = Join-Path $LogPath "backup-$(Get-Date -Format 'yyyyMMdd').log"
    "[$timestamp] [$Level] $Message" | Out-File -FilePath $logFile -Encoding UTF8 -Append
}

# Git execution with timeout
function Invoke-Git {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$WorkingDirectory = $PWD.Path,
        [int]$TimeoutSec = $script:Config.GitTimeoutSec
    )
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "git"
    $psi.Arguments = $Arguments -join " "
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    
    $completed = $proc.WaitForExit($TimeoutSec * 1000)
    if (-not $completed) {
        $proc.Kill()
        throw "Git command timed out after ${TimeoutSec}s: git $($Arguments -join ' ')"
    }
    
    Write-Log -Level "DEBUG" -Message "git $($Arguments -join ' ') -> exit $($proc.ExitCode)"
    
    return @{
        ExitCode = $proc.ExitCode
        StdOut = $stdout
        StdErr = $stderr
        Success = ($proc.ExitCode -eq 0)
    }
}

# Check if git is available
function Test-GitAvailable {
    try {
        $result = Invoke-Git -Arguments @("--version") -TimeoutSec 10
        if ($result.Success) {
            Write-StatusLine "✅" "Git found: $($result.StdOut.Trim())" "Green"
            return $true
        }
    }
    catch {
        Write-StatusLine "❌" "Git not found. Install from https://git-scm.com" "Red"
        return $false
    }
    return $false
}

# Initialize Git repository
function Initialize-GitRepo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoUrl)
    
    Write-StatusLine "📦" "Initializing Git repository..." "Cyan"
    Write-Log -Level "INFO" -Message "Initializing git repo at $BackupPath"
    
    $gitDir = Join-Path $BackupPath ".git"
    if (-not (Test-Path $gitDir)) {
        $result = Invoke-Git -Arguments @("init")
        if (-not $result.Success) { throw "git init failed: $($result.StdErr)" }
        
        # Configure git user if not set
        $nameResult = Invoke-Git -Arguments @("config", "user.name")
        if ([string]::IsNullOrWhiteSpace($nameResult.StdOut)) {
            Invoke-Git -Arguments @("config", "user.name", "Laptop Ecosystem")
            Write-Log -Level "INFO" -Message "Set git user.name"
        }
        $emailResult = Invoke-Git -Arguments @("config", "user.email")
        if ([string]::IsNullOrWhiteSpace($emailResult.StdOut)) {
            Invoke-Git -Arguments @("config", "user.email", "ecosystem@localhost")
            Write-Log -Level "INFO" -Message "Set git user.email"
        }
        
        # Add remote
        Invoke-Git -Arguments @("remote", "add", "origin", $RepoUrl)
        Write-StatusLine "✅" "Git repository initialized" "Green"
        Write-Log -Level "INFO" -Message "Git repo initialized with remote $RepoUrl"
    }
    else {
        Write-StatusLine "ℹ️" "Git repository already exists" "Yellow"
    }
}

# Get tracked file count
function Get-TrackedFileCount {
    $result = Invoke-Git -Arguments @("ls-files")
    if ($result.Success -and $result.StdOut) {
        return ($result.StdOut -split "`n" | Where-Object { $_.Trim() }).Count
    }
    return 0
}

# Get last backup time from git log
function Get-LastBackupTime {
    $result = Invoke-Git -Arguments @("log", "-1", "--format=%ci")
    if ($result.Success -and $result.StdOut) {
        try {
            return [DateTime]::Parse($result.StdOut.Trim())
        }
        catch {
            Write-Log -Level "WARN" -Message "Could not parse last backup time: $($result.StdOut)"
            return $null
        }
    }
    return $null
}

# Check if backup is needed
function Test-BackupNeeded {
    $lastBackup = Get-LastBackupTime
    if (-not $lastBackup) {
        Write-Log -Level "INFO" -Message "No previous backup found, backup needed"
        return $true
    }
    
    $minInterval = New-TimeSpan -Minutes $script:Config.MinBackupIntervalMinutes
    $elapsed = (Get-Date) - $lastBackup
    $needed = $elapsed -gt $minInterval
    
    if (-not $needed) {
        $remaining = $minInterval - $elapsed
        Write-Log -Level "INFO" -Message "Backup not needed. Next in $($remaining.ToString('mm\:ss'))"
    }
    
    return $needed
}

# Clean old log files
function Clear-OldLogs {
    $cutoff = (Get-Date).AddDays(-$script:Config.LogRetentionDays)
    $logFiles = Get-ChildItem -Path $LogPath -Filter "backup-*.log" -ErrorAction SilentlyContinue
    $removed = 0
    foreach ($file in $logFiles) {
        if ($file.LastWriteTime -lt $cutoff) {
            Remove-Item $file.FullName -Force
            $removed++
        }
    }
    if ($removed -gt 0) {
        Write-StatusLine "🗑️" "Removed $removed old log file(s)" "Gray"
    }
}

# Health check for backup path
function Test-BackupPathHealth {
    Write-StatusLine "🏥" "Checking backup path health..." "Cyan"
    
    $drive = Get-PSDrive -Name ($BackupPath[0])
    $freeGB = [math]::Round($drive.Free / 1GB, 2)
    Write-StatusLine "💾" "Free space: ${freeGB} GB" "Cyan"
    
    $fileCount = (Get-ChildItem -Path $BackupPath -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-StatusLine "📊" "Total files: $fileCount" "Cyan"
    
    foreach ($excluded in $script:Config.ExcludedPaths) {
        $excludedPath = Join-Path $BackupPath $excluded
        if (Test-Path $excludedPath) {
            $size = (Get-ChildItem -Path $excludedPath -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round($size / 1MB, 2)
            if ($sizeMB -gt 10) {
                Write-StatusLine "⚠️" "$excluded is ${sizeMB} MB (excluded from backup)" "Yellow"
            }
        }
    }
}

# Main backup function
function Start-GitBackup {
    [CmdletBinding()]
    param()
    
    Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "    🔄 GITHUB BACKUP STARTED" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════`n" -ForegroundColor Cyan
    
    Write-Log -Level "INFO" -Message "=== Backup started ==="
    
    # Ensure backup path exists
    if (-not (Test-Path $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        Write-StatusLine "📁" "Created backup directory: $BackupPath" "Green"
        Write-Log -Level "INFO" -Message "Created backup directory $BackupPath"
    }
    
    Push-Location $BackupPath
    try {
        # Initialize repo if needed
        Initialize-GitRepo -RepoUrl $RepoUrl
        
        # Check if backup is needed
        if (-not $Force -and -not (Test-BackupNeeded)) {
            $lastBackup = Get-LastBackupTime
            Write-StatusLine "⏱️" "Last backup was at $($lastBackup.ToString('HH:mm')). Skipping." "Yellow"
            return
        }
        
        # Stage all changes
        Write-StatusLine "📂" "Staging changes..." "Cyan"
        $result = Invoke-Git -Arguments @("add", ".")
        
        # Check if there are changes to commit
        $statusResult = Invoke-Git -Arguments @("status", "--porcelain")
        if ([string]::IsNullOrWhiteSpace($statusResult.StdOut)) {
            Write-StatusLine "✅" "No changes to backup" "Green"
            Write-Log -Level "INFO" -Message "No changes to backup"
            return
        }
        
        $changeCount = ($statusResult.StdOut -split "`n" | Where-Object { $_.Trim() }).Count
        Write-StatusLine "📝" "Found $changeCount changed file(s)" "Cyan"
        Write-Log -Level "INFO" -Message "Found $changeCount changed file(s)"
        
        if ($DryRun) {
            Write-StatusLine "🔍" "DRY RUN - Would commit $changeCount files" "Yellow"
            Write-Host $statusResult.StdOut
            return
        }
        
        # Commit
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $commitMsg = "Auto-backup: $timestamp ($changeCount files)"
        $result = Invoke-Git -Arguments @("commit", "-m", $commitMsg)
        if (-not $result.Success) {
            Write-StatusLine "⚠️" "Commit issue: $($result.StdErr)" "Yellow"
            Write-Log -Level "WARN" -Message "Commit issue: $($result.StdErr)"
            return
        }
        Write-StatusLine "💾" "Committed: $commitMsg" "Green"
        Write-Log -Level "INFO" -Message "Committed: $commitMsg"
        
        # Push with retry logic
        Write-StatusLine "🚀" "Pushing to GitHub..." "Cyan"
        $pushed = $false
        for ($i = 1; $i -le $script:Config.MaxRetries; $i++) {
            $pushResult = Invoke-Git -Arguments @("push", "origin", "HEAD:main")
            if ($pushResult.Success) {
                $pushed = $true
                break
            }
            
            Write-StatusLine "🔄" "Push attempt $i failed, retrying in $($script:Config.RetryDelaySec)s..." "Yellow"
            Write-Log -Level "WARN" -Message "Push attempt $i failed: $($pushResult.StdErr)"
            Start-Sleep -Seconds $script:Config.RetryDelaySec
            
            # Try pulling first
            $pullResult = Invoke-Git -Arguments @("pull", "origin", "main", "--rebase")
            if (-not $pullResult.Success) {
                Write-StatusLine "⚠️" "Pull failed: $($pullResult.StdErr)" "Yellow"
                Write-Log -Level "WARN" -Message "Pull failed: $($pullResult.StdErr)"
            }
        }
        
        if ($pushed) {
            $trackedCount = Get-TrackedFileCount
            Write-StatusLine "✅" "Backup complete! $trackedCount files tracked on GitHub" "Green"
            Write-Log -Level "INFO" -Message "Backup complete! $trackedCount files tracked"
        }
        else {
            Write-StatusLine "❌" "Failed to push after $($script:Config.MaxRetries) attempts" "Red"
            Write-Log -Level "ERROR" -Message "Failed to push after $($script:Config.MaxRetries) attempts"
        }
        
        # Summary
        Write-Host "`n───────────────────────────────────────────" -ForegroundColor Gray
        Write-Host "Backup Summary:" -ForegroundColor White
        Write-Host "  Files tracked: $trackedCount" -ForegroundColor Gray
        Write-Host "  Commit: $commitMsg" -ForegroundColor Gray
        Write-Host "───────────────────────────────────────────" -ForegroundColor Gray
        
    }
    finally {
        Pop-Location
    }
}

# Create .gitignore if not exists
function Initialize-GitIgnore {
    $gitignorePath = Join-Path $BackupPath ".gitignore"
    if (-not (Test-Path $gitignorePath)) {
        $content = @"
# Laptop Ecosystem - Auto-generated .gitignore
node_modules/
.obsidian/
temp/
tmp/
cache/
*.tmp
*.log
.DS_Store
Thumbs.db
"@
        $content | Out-File -FilePath $gitignorePath -Encoding UTF8
        Write-StatusLine "📝" "Created .gitignore" "Green"
        Write-Log -Level "INFO" -Message "Created .gitignore at $gitignorePath"
    }
}

# ─── MAIN ───
$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date

# Ensure log directory
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

# Clean old logs
Clear-OldLogs

# Check prerequisites
if (-not (Test-GitAvailable)) {
    exit 1
}

# Show configuration summary
Write-Host "Configuration:" -ForegroundColor Gray
Write-Host "  Backup Path: $BackupPath" -ForegroundColor Gray
Write-Host "  Repository:  $RepoUrl" -ForegroundColor Gray
Write-Host "  Log Path:    $LogPath" -ForegroundColor Gray
Write-Host "  Dry Run:     $DryRun" -ForegroundColor Gray
Write-Host "  Force:       $Force" -ForegroundColor Gray

# Health check
Test-BackupPathHealth

# Initialize .gitignore
Initialize-GitIgnore

# Run backup
Start-GitBackup

# Show elapsed time
$elapsed = (Get-Date) - $script:StartTime
Write-Host "`n⏱️  Elapsed: $($elapsed.ToString('mm\\:ss'))" -ForegroundColor Gray
Write-Log -Level "INFO" -Message "=== Backup completed in $($elapsed.ToString('mm\\:ss')) ==="
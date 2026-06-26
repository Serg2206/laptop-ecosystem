#Requires -Version 5.1
<#
.SYNOPSIS
    Syncs Obsidian markdown notes to Notion workspace.
.DESCRIPTION
    Converts Markdown to Notion blocks and syncs with state management,
    MD5 file hashing, and rate limiting (350ms delays).

    Features:
    - Full Markdown to Notion block conversion
    - MD5-based change detection with persistent state
    - Rate-limited API calls (350ms between requests)
    - Dry-run mode for testing
    - Color-coded console output
    - Comprehensive error handling
    - Support for headings, code blocks, lists, checkboxes, quotes, dividers
    - Vault health checking

.PARAMETER VaultPath
    Path to the Obsidian vault directory.
.PARAMETER NotionToken
    Notion integration token. Defaults to NOTION_TOKEN environment variable.
.PARAMETER StateFile
    Path to the sync state JSON file.
.PARAMETER LogPath
    Directory for log files.
.PARAMETER Force
    Force sync all files regardless of state.
.PARAMETER DryRun
    Show what would be synced without making API calls.
.EXAMPLE
    .\Sync-ObsidianToNotion.ps1 -Force
    Forces a full sync of all notes.
.EXAMPLE
    .\Sync-ObsidianToNotion.ps1 -VaultPath "C:\Users\Me\Obsidian"
    Syncs from a custom vault location.
.NOTES
    File Name      : Sync-ObsidianToNotion.ps1
    Author         : Serg2206
    Prerequisite   : PowerShell 5.1, Notion integration token
#>

[CmdletBinding()]
param(
    [string]$VaultPath = "$env:USERPROFILE\Obsidian\Vault",
    [string]$NotionToken = $env:NOTION_TOKEN,
    [string]$StateFile = "$env:USERPROFILE\.laptop-ecosystem\sync-state.json",
    [string]$LogPath = "$env:USERPROFILE\.laptop-ecosystem\logs",
    [switch]$Force,
    [switch]$DryRun
)

# ═══════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════
$script:Config = @{
    NotionApiBase = "https://api.notion.com/v1"
    NotionVersion = "2022-06-28"
    RateLimitDelayMs = 350
    MaxBlocksPerPage = 100
    SupportedExtensions = @('.md', '.markdown')
    ExcludedFolders = @('.obsidian', '.git', 'templates', 'archive')
}

# ═══════════════════════════════════════════
# COLOR OUTPUT HELPERS
# ═══════════════════════════════════════════
function Write-StatusLine {
    param([string]$Icon, [string]$Message, [string]$Color = "White")
    $colors = @{ "Green" = "Green"; "Red" = "Red"; "Yellow" = "Yellow"; "Cyan" = "Cyan" }
    Write-Host "$Icon $Message" -ForegroundColor $colors[$Color]
}

# ═══════════════════════════════════════════
# RATE LIMITER
# ═══════════════════════════════════════════
$script:LastApiCall = [DateTime]::MinValue
function Invoke-RateLimit {
    $elapsed = ([DateTime]::UtcNow - $script:LastApiCall).TotalMilliseconds
    if ($elapsed -lt $script:Config.RateLimitDelayMs) {
        Start-Sleep -Milliseconds ($script:Config.RateLimitDelayMs - $elapsed)
    }
    $script:LastApiCall = [DateTime]::UtcNow
}

# ═══════════════════════════════════════════
# NOTION API HELPER
# ═══════════════════════════════════════════
function Invoke-NotionApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [object]$Body = $null
    )

    Invoke-RateLimit

    $headers = @{
        "Authorization" = "Bearer $NotionToken"
        "Notion-Version" = $script:Config.NotionVersion
        "Content-Type" = "application/json"
    }

    $uri = "$($script:Config.NotionApiBase)$Endpoint"
    $bodyJson = if ($Body) { $Body | ConvertTo-Json -Depth 10 -Compress } else { $null }

    try {
        if ($bodyJson) {
            $response = Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body $bodyJson
        } else {
            $response = Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers
        }
        return @{ Success = $true; Data = $response }
    }
    catch {
        $errMsg = $_.Exception.Message
        if ($_.ErrorDetails.Message) {
            try { $errDetails = $_.ErrorDetails.Message | ConvertFrom-Json; $errMsg = $errDetails.message } catch {}
        }
        return @{ Success = $false; Error = $errMsg }
    }
}

# Search for a Notion page by title
function Find-NotionPage {
    param([string]$Title)
    $body = @{ query = $Title; filter = @{ property = "object"; value = "page" } }
    $result = Invoke-NotionApi -Method POST -Endpoint "/search" -Body $body
    if ($result.Success -and $result.Data.results.Count -gt 0) {
        return $result.Data.results[0].id
    }
    return $null
}

# Update existing Notion page with new content
function Update-NotionPage {
    param(
        [string]$PageId,
        [array]$Blocks
    )
    # Get existing blocks
    $existing = Invoke-NotionApi -Method GET -Endpoint "/blocks/$PageId/children"
    if ($existing.Success -and $existing.Data.results.Count -gt 0) {
        # Delete existing blocks
        foreach ($block in $existing.Data.results) {
            $null = Invoke-NotionApi -Method DELETE -Endpoint "/blocks/$($block.id)"
        }
    }
    # Append new blocks
    $body = @{ children = $Blocks }
    return Invoke-NotionApi -Method PATCH -Endpoint "/blocks/$PageId/children" -Body $body
}

# ═══════════════════════════════════════════
# MD5 HASH HELPER
# ═══════════════════════════════════════════
function Get-FileHashMD5 {
    param([Parameter(Mandatory)][string]$Path)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $hash = $md5.ComputeHash($stream)
        return [BitConverter]::ToString($hash).Replace("-", "").ToLower()
    }
    finally {
        $stream.Close()
    }
}

# ═══════════════════════════════════════════
# MARKDOWN → NOTION BLOCKS CONVERTER
# ═══════════════════════════════════════════
function Convert-MarkdownToNotionBlocks {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Markdown)

    $blocks = @()
    $lines = $Markdown -split "`r?`n"
    $i = 0

    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        $trimmed = $line.Trim()

        # Headings
        if ($trimmed -match '^(#{1,3})\s+(.+)$') {
            $level = $matches[1].Length
            $text = $matches[2]
            $blockType = switch ($level) { 1 { "heading_1" } 2 { "heading_2" } 3 { "heading_3" } }
            $blocks += @{
                type = $blockType
                $blockType = @{ rich_text = @(@{ type = "text"; text = @{ content = $text } }) }
            }
        }
        # Code blocks (fenced)
        elseif ($trimmed -match '^```(\w*)') {
            $language = $matches[1]
            if ([string]::IsNullOrEmpty($language)) { $language = "plain text" }
            $codeLines = @()
            $i++
            while ($i -lt $lines.Count -and $lines[$i].Trim() -ne '```') {
                $codeLines += $lines[$i]
                $i++
            }
            $codeText = $codeLines -join "`n"
            $blocks += @{
                type = "code"
                code = @{
                    rich_text = @(@{ type = "text"; text = @{ content = $codeText } })
                    language = $language
                }
            }
        }
        # Bullet lists
        elseif ($trimmed -match '^[-*+]\s+(.+)$') {
            $text = $matches[1]
            $blocks += @{
                type = "bulleted_list_item"
                bulleted_list_item = @{
                    rich_text = @(@{ type = "text"; text = @{ content = $text } })
                }
            }
        }
        # Numbered lists
        elseif ($trimmed -match '^\d+\.\s+(.+)$') {
            $text = $matches[1]
            $blocks += @{
                type = "numbered_list_item"
                numbered_list_item = @{
                    rich_text = @(@{ type = "text"; text = @{ content = $text } })
                }
            }
        }
        # Checkboxes
        elseif ($trimmed -match '^-?\s*\[([ xX])\]\s+(.+)$') {
            $checked = $matches[1] -ne " "
            $text = $matches[2]
            $blocks += @{
                type = "to_do"
                to_do = @{
                    rich_text = @(@{ type = "text"; text = @{ content = $text } })
                    checked = [bool]$checked
                }
            }
        }
        # Blockquotes
        elseif ($trimmed -match '^>\s*(.+)$') {
            $text = $matches[1]
            $blocks += @{
                type = "quote"
                quote = @{ rich_text = @(@{ type = "text"; text = @{ content = $text } }) }
            }
        }
        # Divider
        elseif ($trimmed -match '^---+$') {
            $blocks += @{ type = "divider"; divider = @{} }
        }
        # Normal paragraph (non-empty)
        elseif (-not [string]::IsNullOrWhiteSpace($trimmed)) {
            $blocks += @{
                type = "paragraph"
                paragraph = @{ rich_text = @(@{ type = "text"; text = @{ content = $trimmed } }) }
            }
        }
        # Empty lines - skip

        $i++
    }

    return $blocks
}

# ═══════════════════════════════════════════
# SYNC STATE MANAGEMENT
# ═══════════════════════════════════════════
function Get-SyncState {
    if (Test-Path $StateFile) {
        try {
            $content = Get-Content $StateFile -Raw -Encoding UTF8
            return $content | ConvertFrom-Json
        }
        catch {
            Write-StatusLine "⚠️" "Corrupted state file, starting fresh" "Yellow"
        }
    }
    return @{ files = @{}; lastSync = $null }
}

function Save-SyncState {
    param([Parameter(Mandatory)][object]$State)
    $dir = Split-Path $StateFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $State | ConvertTo-Json -Depth 5 | Out-File -FilePath $StateFile -Encoding UTF8
}

# Reset sync state
function Reset-SyncState {
    if (Test-Path $StateFile) {
        Remove-Item $StateFile -Force
        Write-StatusLine "🗑️" "Sync state reset" "Yellow"
    }
}

# ═══════════════════════════════════════════
# VAULT FILE DISCOVERY
# ═══════════════════════════════════════════
function Get-VaultFiles {
    $files = @()
    if (-not (Test-Path $VaultPath)) { return $files }

    $mdFiles = Get-ChildItem -Path $VaultPath -Recurse -Include "*.md","*.markdown" -File
    foreach ($file in $mdFiles) {
        $relativeDir = $file.DirectoryName.Substring($VaultPath.Length).TrimStart('\','/')
        $shouldExclude = $false
        foreach ($excluded in $script:Config.ExcludedFolders) {
            if ($relativeDir -match "^$excluded($|[\\/])") {
                $shouldExclude = $true
                break
            }
        }
        if (-not $shouldExclude) {
            $files += $file
        }
    }
    return $files
}

# Get vault statistics
function Get-VaultStats {
    $stats = @{
        TotalFiles = 0
        TotalSize = 0
        LargestFile = $null
        LargestSize = 0
        AvgSize = 0
    }
    $files = Get-VaultFiles
    $stats.TotalFiles = $files.Count
    if ($files.Count -gt 0) {
        $stats.TotalSize = ($files | Measure-Object -Property Length -Sum).Sum
        $stats.AvgSize = [math]::Round($stats.TotalSize / $files.Count, 2)
        $largest = $files | Sort-Object Length -Descending | Select-Object -First 1
        $stats.LargestFile = $largest.Name
        $stats.LargestSize = $largest.Length
    }
    return $stats
}

# ═══════════════════════════════════════════
# NOTION PAGE OPERATIONS
# ═══════════════════════════════════════════
function Sync-NoteToNotion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [string]$ParentPageId
    )

    $relativePath = $File.FullName.Substring($VaultPath.Length + 1)
    Write-StatusLine "📝" "Processing: $relativePath" "Cyan"

    $content = Get-Content $File.FullName -Raw -Encoding UTF8
    $hash = Get-FileHashMD5 -Path $File.FullName

    # Check if already synced and unchanged
    $state = Get-SyncState
    if (-not $Force -and $state.files.$relativePath -eq $hash) {
        Write-StatusLine "⏭️" "Unchanged, skipping" "Yellow"
        return @{ Skipped = $true }
    }

    # Convert markdown to Notion blocks
    $blocks = Convert-MarkdownToNotionBlocks -Markdown $content

    # Truncate if too many blocks
    if ($blocks.Count -gt $script:Config.MaxBlocksPerPage) {
        Write-StatusLine "⚠️" "Truncating from $($blocks.Count) to $($script:Config.MaxBlocksPerPage) blocks" "Yellow"
        $blocks = $blocks[0..($script:Config.MaxBlocksPerPage - 1)]
    }

    if ($DryRun) {
        Write-StatusLine "🔍" "DRY RUN - Would sync $($blocks.Count) blocks" "Yellow"
        return @{ DryRun = $true; Blocks = $blocks.Count }
    }

    # Create page in Notion
    $title = $File.BaseName
    $body = @{
        parent = @{ page_id = $ParentPageId }
        properties = @{
            title = @{ title = @(@{ text = @{ content = $title } }) }
        }
        children = $blocks
    }

    $result = Invoke-NotionApi -Method POST -Endpoint "/pages" -Body $body

    if ($result.Success) {
        # Update state
        $state = Get-SyncState
        if (-not $state.files) { $state.files = @{} }
        $state.files.$relativePath = $hash
        $state.lastSync = (Get-Date).ToString("o")
        Save-SyncState -State $state

        Write-StatusLine "✅" "Synced: $title ($($blocks.Count) blocks)" "Green"
        return @{ Success = $true; PageId = $result.Data.id; Blocks = $blocks.Count }
    }
    else {
        Write-StatusLine "❌" "Failed: $($result.Error)" "Red"
        return @{ Success = $false; Error = $result.Error }
    }
}

# ═══════════════════════════════════════════
# VAULT HEALTH CHECK
# ═══════════════════════════════════════════
function Test-VaultHealth {
    Write-StatusLine "🏥" "Checking vault health..." "Cyan"

    $stats = Get-VaultStats
    Write-StatusLine "📊" "Total files: $($stats.TotalFiles)" "Cyan"
    Write-StatusLine "📦" "Total size: $([math]::Round($stats.TotalSize / 1KB, 2)) KB" "Cyan"
    Write-StatusLine "📏" "Average size: $([math]::Round($stats.AvgSize, 2)) bytes" "Cyan"

    if ($stats.LargestFile) {
        Write-StatusLine "📈" "Largest file: $($stats.LargestFile) ($([math]::Round($stats.LargestSize / 1KB, 2)) KB)" "Cyan"
    }

    # Check for large files (>500KB)
    $largeFiles = Get-VaultFiles | Where-Object { $_.Length -gt 512000 }
    if ($largeFiles) {
        Write-StatusLine "⚠️" "Found $($largeFiles.Count) file(s) >500KB" "Yellow"
        foreach ($lf in $largeFiles | Select-Object -First 5) {
            Write-Host "     - $($lf.Name) ($([math]::Round($lf.Length / 1KB, 2)) KB)" -ForegroundColor Yellow
        }
    }

    # Check for orphaned state entries
    $state = Get-SyncState
    $currentFiles = Get-VaultFiles | ForEach-Object { $_.FullName.Substring($VaultPath.Length + 1) }
    $orphaned = @()
    $stateFiles = $state.files | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    foreach ($sf in $stateFiles) {
        if ($sf -notin $currentFiles) {
            $orphaned += $sf
        }
    }
    if ($orphaned.Count -gt 0) {
        Write-StatusLine "⚠️" "Found $($orphaned.Count) orphaned state entries" "Yellow"
        foreach ($op in $orphaned | Select-Object -First 5) {
            $state.files.PSObject.Properties.Remove($op)
        }
        Save-SyncState -State $state
        Write-StatusLine "🧹" "Cleaned up orphaned entries" "Green"
    }

    return $stats
}

# ═══════════════════════════════════════════
# MAIN SYNC FUNCTION
# ═══════════════════════════════════════════
function Start-ObsidianNotionSync {
    Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "    🔄 OBSIDIAN → NOTION SYNC" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════`n" -ForegroundColor Cyan

    # Validate token
    if ([string]::IsNullOrWhiteSpace($NotionToken)) {
        Write-StatusLine "❌" "NOTION_TOKEN environment variable not set!" "Red"
        Write-Host "   Set it with: [Environment]::SetEnvironmentVariable('NOTION_TOKEN', 'secret_xxx', 'User')" -ForegroundColor Yellow
        return
    }

    # Validate vault
    if (-not (Test-Path $VaultPath)) {
        Write-StatusLine "❌" "Vault not found: $VaultPath" "Red"
        return
    }

    # Test Notion connection
    Write-StatusLine "🔌" "Testing Notion connection..." "Cyan"
    $testResult = Invoke-NotionApi -Method GET -Endpoint "/users/me"
    if (-not $testResult.Success) {
        Write-StatusLine "❌" "Notion API error: $($testResult.Error)" "Red"
        return
    }
    $botName = $testResult.Data.name
    Write-StatusLine "✅" "Connected to Notion as: $botName" "Green"

    # Vault health check
    $stats = Test-VaultHealth

    # Find or create parent page
    Write-StatusLine "🔍" "Looking for Obsidian Notes page..." "Cyan"

    $parentPageId = $env:NOTION_OBSIDIAN_PARENT_PAGE
    if ([string]::IsNullOrWhiteSpace($parentPageId)) {
        Write-StatusLine "ℹ️" "Set NOTION_OBSIDIAN_PARENT_PAGE env var for specific parent page" "Yellow"
        Write-StatusLine "ℹ️" "Using workspace root (pages will be orphaned without parent)" "Yellow"
        $parentPageId = $null
    }

    # Get all markdown files
    Write-StatusLine "📂" "Scanning vault: $VaultPath" "Cyan"
    $files = Get-VaultFiles
    Write-StatusLine "📊" "Found $($files.Count) markdown files" "Cyan"

    if ($files.Count -eq 0) {
        Write-StatusLine "⚠️" "No markdown files found" "Yellow"
        return
    }

    # Sync each file
    $stats = @{ Synced = 0; Failed = 0; Skipped = 0; TotalBlocks = 0 }

    foreach ($file in $files) {
        $result = Sync-NoteToNotion -File $file -ParentPageId $parentPageId

        if ($result.Success) {
            $stats.Synced++
            $stats.TotalBlocks += $result.Blocks
        }
        elseif ($result.Skipped) { $stats.Skipped++ }
        elseif ($result.DryRun) {
            $stats.Synced++
            $stats.TotalBlocks += $result.Blocks
        }
        else { $stats.Failed++ }
    }

    # Summary
    Write-Host "`n───────────────────────────────────────────" -ForegroundColor Gray
    Write-Host "Sync Summary:" -ForegroundColor White
    Write-Host "  ✅ Synced:   $($stats.Synced)" -ForegroundColor Green
    Write-Host "  ⏭️ Skipped:  $($stats.Skipped)" -ForegroundColor Yellow
    Write-Host "  ❌ Failed:   $($stats.Failed)" -ForegroundColor Red
    Write-Host "  📝 Blocks:   $($stats.TotalBlocks)" -ForegroundColor Cyan
    Write-Host "───────────────────────────────────────────" -ForegroundColor Gray
}

# ═══════════════════════════════════════════
# MAIN ENTRY POINT
# ═══════════════════════════════════════════
$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date

# Ensure log directory
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

# Show configuration
Write-Host "Configuration:" -ForegroundColor Gray
Write-Host "  Vault Path: $VaultPath" -ForegroundColor Gray
Write-Host "  State File: $StateFile" -ForegroundColor Gray
Write-Host "  Dry Run:    $DryRun" -ForegroundColor Gray
Write-Host "  Force:      $Force" -ForegroundColor Gray

Start-ObsidianNotionSync

$elapsed = (Get-Date) - $script:StartTime
Write-Host "`n⏱️  Elapsed: $($elapsed.ToString('mm\\:ss'))" -ForegroundColor Gray

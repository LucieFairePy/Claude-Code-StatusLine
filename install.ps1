#Requires -Version 5.1

$ErrorActionPreference = "Stop"

$REPO_URL   = "https://raw.githubusercontent.com/LucieFairePy/Claude-Code-StatusLine/main"
$CLAUDE_DIR = Join-Path $env:USERPROFILE ".claude"
$SETTINGS   = Join-Path $CLAUDE_DIR "settings.json"

function Write-Step { param($msg) Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  !! $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "  XX $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  Claude Code Statusline -- Installer" -ForegroundColor Magenta
Write-Host "  =====================================" -ForegroundColor Magenta
Write-Host ""

Write-Step "Setting execution policy..."
try {
    $current = Get-ExecutionPolicy -Scope CurrentUser
    if ($current -eq "Restricted" -or $current -eq "Undefined") {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        Write-Ok "Execution policy set to RemoteSigned."
    } else {
        Write-Ok "Execution policy already permissive ($current)."
    }
} catch {
    Write-Warn "Could not set execution policy. If the status bar does not work, run: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
}

Write-Step "Checking for Git Bash..."

function Find-GitBash {
    $candidates = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) { return $found }
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$gitBash = Find-GitBash

if (-not $gitBash) {
    Write-Warn "Git Bash not found. Installing Git for Windows via winget..."
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements | Out-Null
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH","User")
    $gitBash = Find-GitBash
    if (-not $gitBash) { Write-Fail "Git install succeeded but bash.exe not found. Reopen PowerShell and retry." }
    Write-Ok "Git installed."
} else {
    Write-Ok "Git Bash: $gitBash"
}

Write-Step "Checking for jq..."

function Test-Jq {
    param($bash)
    $result = & $bash -c "command -v jq 2>/dev/null || ls '$env:LOCALAPPDATA/Microsoft/WinGet/Links/jq.exe' 2>/dev/null" 2>$null
    return ($LASTEXITCODE -eq 0 -and $result)
}

if (-not (Test-Jq $gitBash)) {
    Write-Warn "jq not found. Installing via winget..."
    winget install --id jqlang.jq -e --source winget --accept-package-agreements --accept-source-agreements | Out-Null
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH","User")
    Write-Ok "jq installed."
} else {
    Write-Ok "jq found."
}

Write-Step "Preparing ~/.claude directory..."
if (-not (Test-Path $CLAUDE_DIR)) {
    New-Item -ItemType Directory -Path $CLAUDE_DIR -Force | Out-Null
}
Write-Ok "Directory: $CLAUDE_DIR"

Write-Step "Installing statusline scripts..."

$shDest  = Join-Path $CLAUDE_DIR "statusline-command.sh"
$ps1Dest = Join-Path $CLAUDE_DIR "statusline-wrapper.ps1"

$localDir = $PSScriptRoot
if (-not $localDir) { $localDir = try { Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $null } }
$localSh = if ($localDir) { Join-Path $localDir "statusline-command.sh" } else { $null }

if ($localSh -and (Test-Path $localSh)) {
    Copy-Item $localSh $shDest -Force
    Copy-Item (Join-Path $localDir "statusline-wrapper.ps1") $ps1Dest -Force
    Write-Ok "Copied from local clone."
} else {
    try {
        Invoke-WebRequest "$REPO_URL/statusline-command.sh"  -OutFile $shDest  -UseBasicParsing
        Invoke-WebRequest "$REPO_URL/statusline-wrapper.ps1" -OutFile $ps1Dest -UseBasicParsing
        Write-Ok "Downloaded from GitHub."
    } catch {
        Write-Fail "Download failed. Check internet connection."
    }
}

$shContent = [System.IO.File]::ReadAllText($shDest) -replace "`r`n", "`n" -replace "`r", "`n"
[System.IO.File]::WriteAllText($shDest, $shContent, [System.Text.Encoding]::UTF8)

Write-Step "Patching Claude Code settings.json..."

$statusLineValue = [PSCustomObject]@{
    type    = "command"
    command = "powershell -NoProfile -NonInteractive -File `"$ps1Dest`""
}

if (Test-Path $SETTINGS) {
    $backup = "$SETTINGS.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $SETTINGS $backup
    Write-Ok "Settings backed up: $(Split-Path -Leaf $backup)"

    try {
        $settings = Get-Content $SETTINGS -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warn "Could not parse existing settings.json — will merge safely."
        $settings = [PSCustomObject]@{}
    }

    if ($settings.PSObject.Properties.Name -contains "statusLine") {
        $settings.statusLine = $statusLineValue
    } else {
        $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLineValue
    }

    $settings | ConvertTo-Json -Depth 10 | Set-Content $SETTINGS -Encoding UTF8
} else {
    [PSCustomObject]@{ statusLine = $statusLineValue } |
        ConvertTo-Json -Depth 10 | Set-Content $SETTINGS -Encoding UTF8
}

Write-Ok "settings.json updated."

Write-Step "Verifying installation..."

$resetAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 7200
$testJson = "{`"model`":{`"display_name`":`"Claude Sonnet 4.6`"},`"context_window`":{`"used_percentage`":35,`"remaining_percentage`":65,`"context_window_size`":200000,`"current_usage`":{`"input_tokens`":70000}},`"rate_limits`":{`"five_hour`":{`"used_percentage`":40,`"resets_at`":$resetAt},`"seven_day`":{`"used_percentage`":20}}}"

try {
    $result = $testJson | & powershell -NoProfile -NonInteractive -File $ps1Dest 2>$null
    if ($result) {
        Write-Host ""
        Write-Host "  Status bar preview:" -ForegroundColor DarkGray
        $result | ForEach-Object { Write-Host "    $_" }
        Write-Host ""
    }
} catch {
    Write-Warn "Live preview skipped. Restart Claude Code to verify."
}

Write-Host "  Done! Restart Claude Code to activate the status bar." -ForegroundColor Green
Write-Host ""
Write-Host "  Files installed to: $CLAUDE_DIR" -ForegroundColor DarkGray
Write-Host "  To uninstall: run uninstall.ps1 or see README" -ForegroundColor DarkGray
Write-Host ""

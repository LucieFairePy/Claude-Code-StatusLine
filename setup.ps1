#Requires -Version 5.1

param([string]$Action = "")

$ErrorActionPreference = "Stop"

$REPO_URL   = "https://raw.githubusercontent.com/LucieFairePy/Claude-Code-StatusLine/main"
$CLAUDE_DIR = Join-Path $env:USERPROFILE ".claude"
$SETTINGS   = Join-Path $CLAUDE_DIR "settings.json"
$CFG_FILE   = Join-Path $CLAUDE_DIR "statusline-config.json"
$PS1_DEST   = Join-Path $CLAUDE_DIR "statusline-wrapper.ps1"

function Write-Step { param($msg) Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  !! $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "  XX $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  Claude Code Statusline" -ForegroundColor Magenta
Write-Host "  =======================" -ForegroundColor Magenta
Write-Host ""

if ($Action -eq "") {
    Write-Host "  [1] Install" -ForegroundColor Cyan
    Write-Host "  [2] Uninstall" -ForegroundColor Cyan
    Write-Host "  [Q] Quit" -ForegroundColor DarkGray
    Write-Host ""
    $choice = (Read-Host "  Choice").Trim().ToUpper()
    switch ($choice) {
        "1" { $Action = "install" }
        "2" { $Action = "uninstall" }
        "Q" { exit 0 }
        default { Write-Host "  Invalid choice." -ForegroundColor Red; exit 1 }
    }
}

# ─── CUSTOMIZATION MENU ─────────────────────────────────────────────────────

function Show-CustomizeMenu {
    $BAR_WIDTHS = @(6, 8, 10, 12)

    $opts = [PSCustomObject]@{
        showSession   = $true
        showCountdown = $true
        showContext   = $true
        showCompact   = $true
        showWeekly    = $true
        barWidth      = 8
    }

    # Pre-fill from existing config if upgrading
    if (Test-Path $CFG_FILE) {
        try {
            $existing = Get-Content $CFG_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in @('showSession','showCountdown','showContext','showCompact','showWeekly','barWidth')) {
                if ($existing.PSObject.Properties.Name -contains $p) { $opts.$p = $existing.$p }
            }
        } catch {}
    }

    function Label($val) { if ($val) { "[ON ]" } else { "[OFF]" } }
    function Color($val) { if ($val) { "Cyan" } else { "DarkGray" } }

    while ($true) {
        Write-Host ""
        Write-Host "  Customize your status bar:" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "    [1] $(Label $opts.showSession)   Session bar (5-hour usage)"   -ForegroundColor (Color $opts.showSession)
        Write-Host "    [2] $(Label $opts.showCountdown) Reset countdown"               -ForegroundColor (Color $opts.showCountdown)
        Write-Host "    [3] $(Label $opts.showContext)   Context window bar"            -ForegroundColor (Color $opts.showContext)
        Write-Host "    [4] $(Label $opts.showCompact)   Compact warning (>80% ctx)"   -ForegroundColor (Color $opts.showCompact)
        Write-Host "    [5] $(Label $opts.showWeekly)    Weekly usage bar (>80%)"       -ForegroundColor (Color $opts.showWeekly)
        Write-Host "    [6] Bar width: $($opts.barWidth)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Type a number to toggle, N to continue:" -ForegroundColor DarkGray

        $c = (Read-Host "  >").Trim().ToUpper()
        switch ($c) {
            "1" { $opts.showSession   = -not $opts.showSession }
            "2" { $opts.showCountdown = -not $opts.showCountdown }
            "3" { $opts.showContext   = -not $opts.showContext }
            "4" { $opts.showCompact   = -not $opts.showCompact }
            "5" { $opts.showWeekly    = -not $opts.showWeekly }
            "6" {
                $idx = [Array]::IndexOf($BAR_WIDTHS, $opts.barWidth)
                $opts.barWidth = $BAR_WIDTHS[($idx + 1) % $BAR_WIDTHS.Length]
            }
            "N" { return $opts }
        }
    }
}

# ─── INSTALL ────────────────────────────────────────────────────────────────

function Invoke-Install {
    Write-Host ""
    Write-Host "  Installing..." -ForegroundColor Magenta
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
        Write-Warn "Could not set execution policy. If status bar does not work, run: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    }

    # Customization
    $config = Show-CustomizeMenu
    Write-Host ""

    Write-Step "Preparing ~/.claude directory..."
    if (-not (Test-Path $CLAUDE_DIR)) {
        New-Item -ItemType Directory -Path $CLAUDE_DIR -Force | Out-Null
    }
    Write-Ok "Directory: $CLAUDE_DIR"

    Write-Step "Installing statusline script..."

    $localDir = $PSScriptRoot
    if (-not $localDir) { $localDir = try { Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $null } }
    $localPs1 = if ($localDir) { Join-Path $localDir "statusline-wrapper.ps1" } else { $null }

    if ($localPs1 -and (Test-Path $localPs1)) {
        Copy-Item $localPs1 $PS1_DEST -Force
        Write-Ok "Copied from local clone."
    } else {
        try {
            Invoke-WebRequest "$REPO_URL/statusline-wrapper.ps1" -OutFile $PS1_DEST -UseBasicParsing
            Write-Ok "Downloaded from GitHub."
        } catch {
            Write-Fail "Download failed. Check internet connection."
        }
    }

    # Remove legacy bash script if present from old install
    $legacySh = Join-Path $CLAUDE_DIR "statusline-command.sh"
    if (Test-Path $legacySh) { Remove-Item $legacySh -Force; Write-Ok "Removed legacy statusline-command.sh." }

    Write-Step "Saving configuration..."
    $config | ConvertTo-Json -Depth 5 | Set-Content $CFG_FILE -Encoding UTF8
    Write-Ok "Config saved: statusline-config.json"

    Write-Step "Patching Claude Code settings.json..."

    $statusLineValue = [PSCustomObject]@{
        type    = "command"
        command = "powershell -NoProfile -NonInteractive -File `"$PS1_DEST`""
    }

    if (Test-Path $SETTINGS) {
        $backup = "$SETTINGS.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $SETTINGS $backup
        Write-Ok "Settings backed up: $(Split-Path -Leaf $backup)"

        try {
            $settings = Get-Content $SETTINGS -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Warn "Could not parse existing settings.json — merging safely."
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

    $resetAt  = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 7200
    $testJson = "{`"model`":{`"display_name`":`"Claude Sonnet 4.6`"},`"context_window`":{`"used_percentage`":35,`"remaining_percentage`":65,`"context_window_size`":200000,`"current_usage`":{`"input_tokens`":70000}},`"rate_limits`":{`"five_hour`":{`"used_percentage`":40,`"resets_at`":$resetAt},`"seven_day`":{`"used_percentage`":20}}}"

    try {
        $result = $testJson | & powershell -NoProfile -NonInteractive -File $PS1_DEST 2>$null
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
    Write-Host "  To customize: re-run this script and choose [1] Install again" -ForegroundColor DarkGray
    Write-Host ""
}

# ─── UNINSTALL ──────────────────────────────────────────────────────────────

function Invoke-Uninstall {
    Write-Host ""
    Write-Host "  Uninstalling..." -ForegroundColor Magenta
    Write-Host ""

    if (Test-Path $SETTINGS) {
        $backup = "$SETTINGS.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $SETTINGS $backup
        Write-Ok "Settings backed up: $(Split-Path -Leaf $backup)"

        try {
            $settings = Get-Content $SETTINGS -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($settings.PSObject.Properties.Name -contains "statusLine") {
                $settings.PSObject.Properties.Remove("statusLine")
                $settings | ConvertTo-Json -Depth 10 | Set-Content $SETTINGS -Encoding UTF8
                Write-Ok "Removed statusLine from settings.json."
            } else {
                Write-Warn "statusLine not found in settings.json — already removed?"
            }
        } catch {
            Write-Warn "Could not parse settings.json. Remove the statusLine key manually."
        }
    } else {
        Write-Warn "settings.json not found."
    }

    foreach ($f in @("statusline-wrapper.ps1", "statusline-command.sh", "statusline-config.json")) {
        $path = Join-Path $CLAUDE_DIR $f
        if (Test-Path $path) {
            Remove-Item $path -Force
            Write-Ok "Deleted: $f"
        }
    }

    Write-Host ""
    Write-Host "  Done. Restart Claude Code to complete removal." -ForegroundColor Green
    Write-Host ""
}

# ─── DISPATCH ───────────────────────────────────────────────────────────────

switch ($Action.ToLower()) {
    "install"   { Invoke-Install }
    "uninstall" { Invoke-Uninstall }
    default     { Write-Host "  Unknown action: $Action" -ForegroundColor Red; exit 1 }
}

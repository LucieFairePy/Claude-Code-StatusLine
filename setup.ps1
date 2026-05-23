#Requires -Version 5.1

param([string]$Action = "")

$ErrorActionPreference = "Stop"

# Force TLS 1.2 — required by GitHub, missing on some Windows 10 installs
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$REPO_URL  = "https://raw.githubusercontent.com/LucieFairePy/Claude-Code-StatusLine/main"
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
    $cfgFile    = Join-Path (Join-Path $env:USERPROFILE ".claude") "statusline-config.json"

    $opts = [PSCustomObject]@{
        showSession   = $true
        showCountdown = $true
        showContext   = $true
        showCompact   = $true
        showWeekly    = $true
        barWidth      = 8
    }

    # Pre-fill from existing config when reconfiguring
    if (Test-Path $cfgFile) {
        try {
            $existing = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in @('showSession','showCountdown','showContext','showCompact','showWeekly','barWidth')) {
                if ($existing.PSObject.Properties.Name -contains $p) { $opts.$p = $existing.$p }
            }
        } catch {}
    }

    function On-Off($val) { if ($val) { "[ON ]" } else { "[OFF]" } }
    function On-Color($val) { if ($val) { "Cyan" } else { "DarkGray" } }

    while ($true) {
        Write-Host ""
        Write-Host "  Customize your status bar:" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "    [1] $(On-Off $opts.showSession)   Session bar (5-hour usage)"   -ForegroundColor (On-Color $opts.showSession)
        Write-Host "    [2] $(On-Off $opts.showCountdown) Reset countdown"               -ForegroundColor (On-Color $opts.showCountdown)
        Write-Host "    [3] $(On-Off $opts.showContext)   Context window bar"            -ForegroundColor (On-Color $opts.showContext)
        Write-Host "    [4] $(On-Off $opts.showCompact)   Compact warning (>80% ctx)"   -ForegroundColor (On-Color $opts.showCompact)
        Write-Host "    [5] $(On-Off $opts.showWeekly)    Weekly usage (>80%)"           -ForegroundColor (On-Color $opts.showWeekly)
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
                $idx = [Array]::IndexOf($BAR_WIDTHS, [int]$opts.barWidth)
                if ($idx -lt 0) { $idx = 0 }
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
        Write-Warn "Could not set execution policy. If the status bar does not work, run: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    }

    $config = Show-CustomizeMenu
    Write-Host ""

    Write-Step "Preparing ~/.claude directory..."
    if (-not (Test-Path $CLAUDE_DIR)) {
        New-Item -ItemType Directory -Path $CLAUDE_DIR -Force | Out-Null
    }
    Write-Ok "Directory: $CLAUDE_DIR"

    Write-Step "Installing statusline script..."

    $localDir = $PSScriptRoot
    if (-not $localDir) {
        $localDir = try { Split-Path -Parent $MyInvocation.PSCommandPath } catch { $null }
    }
    $localPs1 = if ($localDir) { Join-Path $localDir "statusline-wrapper.ps1" } else { $null }

    if ($localPs1 -and (Test-Path $localPs1)) {
        Copy-Item $localPs1 $PS1_DEST -Force
        Write-Ok "Copied from local clone."
    } else {
        try {
            Invoke-WebRequest "$REPO_URL/statusline-wrapper.ps1" -OutFile $PS1_DEST -UseBasicParsing
            Write-Ok "Downloaded from GitHub."
        } catch {
            Write-Fail "Download failed: $_"
        }
    }

    # Unblock file — removes Zone.Identifier mark from downloaded file so
    # RemoteSigned policy does not block execution on fresh installs
    try { Unblock-File -Path $PS1_DEST -ErrorAction Stop; Write-Ok "File unblocked." } catch {}

    # Remove legacy bash script if present from old install
    $legacySh = Join-Path $CLAUDE_DIR "statusline-command.sh"
    if (Test-Path $legacySh) { Remove-Item $legacySh -Force; Write-Ok "Removed legacy statusline-command.sh." }

    Write-Step "Saving configuration..."
    try {
        $config | ConvertTo-Json -Depth 5 | Set-Content $CFG_FILE -Encoding UTF8
        Write-Ok "Config saved."
    } catch {
        Write-Warn "Could not save config: $_"
    }

    Write-Step "Patching Claude Code settings.json..."

    $statusLineValue = [PSCustomObject]@{
        type    = "command"
        command = "powershell -NoProfile -NonInteractive -File `"$PS1_DEST`""
    }

    if (Test-Path $SETTINGS) {
        $backup = "$SETTINGS.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $SETTINGS $backup
        Write-Ok "Settings backed up: $(Split-Path -Leaf $backup)"

        $settings = $null
        try {
            $settings = Get-Content $SETTINGS -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Warn "Could not parse existing settings.json — creating fresh merge."
        }
        if (-not $settings) { $settings = [PSCustomObject]@{} }

        if ($settings.PSObject.Properties.Name -contains "statusLine") {
            $settings.statusLine = $statusLineValue
        } else {
            $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLineValue
        }

        [System.IO.File]::WriteAllBytes($SETTINGS, [System.Text.Encoding]::UTF8.GetBytes(($settings | ConvertTo-Json -Depth 10)))
    } else {
        [System.IO.File]::WriteAllBytes($SETTINGS, [System.Text.Encoding]::UTF8.GetBytes(([PSCustomObject]@{ statusLine = $statusLineValue } | ConvertTo-Json -Depth 10)))
    }

    Write-Ok "settings.json updated."

    Write-Step "Verifying installation..."
    try {
        $result = & powershell -NoProfile -NonInteractive -File $PS1_DEST -Test 2>$null
        if ($result) {
            Write-Host ""
            Write-Host "  Preview:" -ForegroundColor DarkGray
            $result | ForEach-Object { Write-Host "    $_" }
            Write-Host ""
        } else {
            Write-Warn "No preview output — script ran but produced nothing. Try restarting Claude Code."
        }
    } catch {
        Write-Warn "Preview skipped: $_"
    }

    Write-Host "  Done! Restart Claude Code to activate the status bar." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Installed to:  $CLAUDE_DIR" -ForegroundColor DarkGray
    Write-Host "  To reconfigure: re-run this script and choose [1]" -ForegroundColor DarkGray
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
                [System.IO.File]::WriteAllBytes($SETTINGS, [System.Text.Encoding]::UTF8.GetBytes(($settings | ConvertTo-Json -Depth 10)))
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

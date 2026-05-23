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
function Write-Info { param($msg) Write-Host "     $msg" -ForegroundColor DarkGray }
function Write-Sep  { Write-Host "  ---" -ForegroundColor DarkGray }

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

    # ── CLAUDE CODE RUNNING CHECK ────────────────────────────────────────────────
    $claudeProcs = @(Get-Process -Name "claude" -ErrorAction SilentlyContinue) +
                   @(Get-Process -Name "claude-code" -ErrorAction SilentlyContinue) +
                   @(Get-Process -Name "Claude" -ErrorAction SilentlyContinue)
    $claudeProcs = $claudeProcs | Where-Object { $_ -ne $null }
    if ($claudeProcs.Count -gt 0) {
        Write-Host ""
        Write-Host "  WARNING: Claude Code appears to be running!" -ForegroundColor Red
        Write-Host "  It will overwrite settings.json right after we write it." -ForegroundColor Yellow
        Write-Host "  Close Claude Code completely (window + system tray) before continuing." -ForegroundColor Yellow
        Write-Host ""
        $cont = (Read-Host "  Continue anyway? [Y/N]").Trim().ToUpper()
        if ($cont -ne "Y") { Write-Host "  Aborted." -ForegroundColor DarkGray; return }
    }

    # ── EXECUTION POLICY ────────────────────────────────────────────────────────
    Write-Step "Execution policy"
    try {
        $current = Get-ExecutionPolicy -Scope CurrentUser
        if ($current -eq "Restricted" -or $current -eq "Undefined") {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
            Write-Ok "CurrentUser set to RemoteSigned."
        } else {
            Write-Ok "CurrentUser already permissive ($current) — no change."
        }
    } catch {
        Write-Warn "Execution policy error: $_"
    }

    Write-Sep

    # ── CUSTOMIZE ───────────────────────────────────────────────────────────────
    $config = Show-CustomizeMenu
    Write-Host ""

    # ── CLAUDE DIR ──────────────────────────────────────────────────────────────
    Write-Step "Preparing ~/.claude directory"
    try {
        if (-not (Test-Path $CLAUDE_DIR)) {
            New-Item -ItemType Directory -Path $CLAUDE_DIR -Force | Out-Null
            Write-Ok "Created: $CLAUDE_DIR"
        } else {
            Write-Ok "Exists: $CLAUDE_DIR"
        }
    } catch {
        Write-Fail "Could not create ~/.claude: $_"
    }

    Write-Sep

    # ── DOWNLOAD WRAPPER ────────────────────────────────────────────────────────
    Write-Step "Installing statusline-wrapper.ps1"

    $localDir = $PSScriptRoot
    if (-not $localDir) {
        $localDir = try { Split-Path -Parent $MyInvocation.PSCommandPath } catch { $null }
    }
    $localPs1 = if ($localDir) { Join-Path $localDir "statusline-wrapper.ps1" } else { $null }

    if ($localPs1 -and (Test-Path $localPs1)) {
        try {
            Copy-Item $localPs1 $PS1_DEST -Force
            Write-Ok "Copied from local clone."
        } catch {
            Write-Fail "Copy failed: $_"
        }
    } else {
        try {
            $resp = Invoke-WebRequest "$REPO_URL/statusline-wrapper.ps1" -OutFile $PS1_DEST -UseBasicParsing -PassThru
            Write-Ok "Downloaded from GitHub. HTTP $($resp.StatusCode)"
        } catch {
            Write-Fail "Download failed: $_"
        }
    }

    if (-not (Test-Path $PS1_DEST)) {
        Write-Fail "statusline-wrapper.ps1 not found after install step — aborting."
    }

    # Unblock
    try {
        Unblock-File -Path $PS1_DEST -ErrorAction Stop
        Write-Ok "Unblock-File succeeded."
    } catch {
        Write-Warn "Unblock-File failed: $_ — proceeding anyway (-ExecutionPolicy Bypass covers this)."
    }

    # Remove legacy
    $legacySh = Join-Path $CLAUDE_DIR "statusline-command.sh"
    if (Test-Path $legacySh) { Remove-Item $legacySh -Force; Write-Ok "Removed legacy statusline-command.sh." }

    Write-Sep

    # ── CONFIG ──────────────────────────────────────────────────────────────────
    Write-Step "Saving statusline-config.json"
    try {
        $config | ConvertTo-Json -Depth 5 | Set-Content $CFG_FILE -Encoding UTF8
        Write-Ok "Config saved."
    } catch {
        Write-Warn "Could not save config: $_"
    }

    Write-Sep

    # ── SETTINGS.JSON ───────────────────────────────────────────────────────────
    Write-Step "Patching Claude Code settings.json"

    $statusLineValue = [PSCustomObject]@{
        type    = "command"
        command = "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PS1_DEST`""
    }

    if (Test-Path $SETTINGS) {
        $backup = "$SETTINGS.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        try {
            Copy-Item $SETTINGS $backup
            Write-Ok "Backup created: $(Split-Path -Leaf $backup)"
        } catch {
            Write-Warn "Backup failed: $_"
        }

        $settingsObj = $null
        try {
            $settingsObj = [System.IO.File]::ReadAllText($SETTINGS, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        } catch {
            Write-Warn "Could not parse settings.json: $_ -- will create fresh."
        }
        if (-not $settingsObj) { $settingsObj = [PSCustomObject]@{} }

        if ($settingsObj.PSObject.Properties.Name -contains "statusLine") {
            $existingCmd = try { $settingsObj.statusLine.command } catch { "" }
            if ($existingCmd -and $existingCmd -notlike "*statusline-wrapper.ps1*") {
                Write-Host ""
                Write-Warn "statusLine already set by another tool:"
                Write-Host "    $existingCmd" -ForegroundColor DarkGray
                Write-Host ""
                $overwrite = (Read-Host "  Overwrite? [Y/N]").Trim().ToUpper()
                if ($overwrite -ne "Y") {
                    Write-Host ""
                    Write-Host "  Skipped. Edit settings.json manually to switch statusLine." -ForegroundColor Yellow
                    Write-Host ""
                    return
                }
            }
            $settingsObj.statusLine = $statusLineValue
        } else {
            $settingsObj | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLineValue
        }

        try {
            [System.IO.File]::WriteAllBytes($SETTINGS, [System.Text.Encoding]::UTF8.GetBytes(($settingsObj | ConvertTo-Json -Depth 10)))
            Write-Ok "settings.json updated."
        } catch {
            Write-Fail "WriteAllBytes failed: $_"
        }
    } else {
        try {
            [System.IO.File]::WriteAllBytes($SETTINGS, [System.Text.Encoding]::UTF8.GetBytes(([PSCustomObject]@{ statusLine = $statusLineValue } | ConvertTo-Json -Depth 10)))
            Write-Ok "settings.json created."
        } catch {
            Write-Fail "WriteAllBytes failed: $_"
        }
    }

    # Race condition check — did Claude Code overwrite settings.json after our write?
    try {
        $currentContent = [System.IO.File]::ReadAllText($SETTINGS, [System.Text.Encoding]::UTF8)
        if ($currentContent -notlike "*statusline-wrapper.ps1*") {
            Write-Host ""
            Write-Host "  RACE CONDITION DETECTED!" -ForegroundColor Red
            Write-Host "  settings.json no longer contains our statusLine." -ForegroundColor Red
            Write-Host "  Claude Code was running and overwrote our changes." -ForegroundColor Yellow
            Write-Host "  -> Close Claude Code completely, then re-run this script." -ForegroundColor Yellow
            Write-Host ""
        }
    } catch {
        Write-Warn "Could not verify final settings.json: $_"
    }

    Write-Sep

    # ── VERIFY -Test FLAG ────────────────────────────────────────────────────────
    Write-Step "Test 1/2 — wrapper with -Test flag (hardcoded data, no stdin)"
    try {
        $result = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PS1_DEST -Test 2>$null
        if ($result) {
            Write-Ok "-Test output:"
            $result | ForEach-Object { Write-Host "    $_" }
        } else {
            Write-Warn "-Test produced no output."
        }
    } catch {
        Write-Warn "-Test failed: $_"
    }

    Write-Sep

    # ── VERIFY STDIN PIPING ──────────────────────────────────────────────────────
    Write-Step "Test 2/2 — stdin pipe (simulates how Claude Code calls the wrapper)"
    try {
        $resetAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 7200
        $testJson = '{"model":{"display_name":"Claude Sonnet 4.6"},"context_window":{"used_percentage":35,"context_window_size":200000,"current_usage":{"input_tokens":70000}},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":RESETAT},"seven_day":{"used_percentage":20}}}'.Replace('RESETAT', $resetAt)
        $stdinResult = $testJson | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PS1_DEST
        if ($stdinResult) {
            Write-Ok "Stdin pipe output:"
            $stdinResult | ForEach-Object { Write-Host "    $_" }
        } else {
            Write-Warn "Stdin pipe produced no output — bar will not appear in Claude Code!"
            Write-Warn "Check wrapper script manually."
        }
    } catch {
        Write-Warn "Stdin pipe test failed: $_"
    }

    Write-Sep

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
            $settingsObj = [System.IO.File]::ReadAllText($SETTINGS, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($settingsObj.PSObject.Properties.Name -contains "statusLine") {
                $settingsObj.PSObject.Properties.Remove("statusLine")
                [System.IO.File]::WriteAllBytes($SETTINGS, [System.Text.Encoding]::UTF8.GetBytes(($settingsObj | ConvertTo-Json -Depth 10)))
                Write-Ok "Removed statusLine from settings.json."
            } else {
                Write-Warn "statusLine not found in settings.json -- already removed?"
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

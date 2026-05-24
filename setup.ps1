#Requires -Version 5.1

param([string]$Action = "")

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$REPO_URL   = "https://raw.githubusercontent.com/LucieFairePy/Claude-Code-StatusLine/main"
$CLAUDE_DIR = Join-Path $env:USERPROFILE ".claude"
$SETTINGS   = Join-Path $CLAUDE_DIR "settings.json"
$CFG_FILE   = Join-Path $CLAUDE_DIR "statusline-config.json"
$PS1_DEST   = Join-Path $CLAUDE_DIR "statusline-wrapper.ps1"

# ─── CONSOLE HELPERS ──────────────────────────────────────────────────────────

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  !! $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  XX $msg" -ForegroundColor Red; exit 1 }
function Write-Line       { Write-Host ("  " + ("-" * 56)) -ForegroundColor DarkGray }

function Clear-Screen { try { [Console]::Clear() } catch {} }

function Write-Banner($title) {
    $inner = 54
    $pad   = [Math]::Max(0, $inner - $title.Length)
    $lpad  = [Math]::Floor($pad / 2)
    $rpad  = $pad - $lpad
    Write-Host ("  +" + ("-" * $inner) + "+") -ForegroundColor DarkCyan
    Write-Host ("  |" + (" " * $lpad) + $title + (" " * $rpad) + "|") -ForegroundColor Cyan
    Write-Host ("  +" + ("-" * $inner) + "+") -ForegroundColor DarkCyan
}

function Toggle-Label($val) { if ($val) { "[ON ]" } else { "[OFF]" } }
function Toggle-Color($val) { if ($val) { "Green" } else { "DarkGray" } }

# ─── MENU DRAW ────────────────────────────────────────────────────────────────

function Draw-Menu($opts) {
    Clear-Screen
    Write-Host ""
    Write-Banner "CONFIGURE YOUR STATUS BAR"
    Write-Host ""

    Write-Host "  LINE 1  (top row)" -ForegroundColor DarkGray
    Write-Line
    Write-Host ""
    Write-Host ("    [1]  " + (Toggle-Label $opts.showModel)     + "   Model name") -ForegroundColor (Toggle-Color $opts.showModel)
    Write-Host ("    [2]  " + (Toggle-Label $opts.showSession)   + "   Session usage  (5-hour)") -ForegroundColor (Toggle-Color $opts.showSession)
    Write-Host ("    [3]  " + (Toggle-Label $opts.showCountdown) + "   Reset countdown") -ForegroundColor (Toggle-Color $opts.showCountdown)
    Write-Host ""

    Write-Host "  LINE 2  (bottom row)" -ForegroundColor DarkGray
    Write-Line
    Write-Host ""
    Write-Host ("    [4]  " + (Toggle-Label $opts.showContext)   + "   Context window") -ForegroundColor (Toggle-Color $opts.showContext)
    Write-Host ("    [5]  " + (Toggle-Label $opts.showCompact)   + "   Compact warning  (when context > 80%)") -ForegroundColor (Toggle-Color $opts.showCompact)
    Write-Host ("    [6]  " + (Toggle-Label $opts.showWeekly)    + "   Weekly usage") -ForegroundColor (Toggle-Color $opts.showWeekly)

    if ($opts.showWeekly) {
        $tLabel = if ($opts.weeklyThreshold -eq 0) { "Always visible" } else { "Show from $($opts.weeklyThreshold)% usage" }
        Write-Host "    [7]        Visibility : $tLabel" -ForegroundColor Cyan
    } else {
        Write-Host "    [7]        (enable weekly to configure visibility)" -ForegroundColor DarkGray
    }
    Write-Host ""

    Write-Host "  STYLE" -ForegroundColor DarkGray
    Write-Line
    Write-Host ""
    $f = [Math]::Min($opts.barWidth, [Math]::Max(0, [Math]::Round(65 / 100 * $opts.barWidth)))
    $barPrev = ("#" * $f) + ("-" * ($opts.barWidth - $f))
    Write-Host ("    [8]        Bar width  : " + $opts.barWidth + "   [" + $barPrev + "]") -ForegroundColor Cyan
    Write-Host ""

    Write-Line
    Write-Host "    [N]   Preview  then  Continue" -ForegroundColor Yellow
    Write-Host "    [Q]   Cancel" -ForegroundColor DarkGray
    Write-Line
    Write-Host ""
}

# ─── PREVIEW DRAW ─────────────────────────────────────────────────────────────

function Draw-Preview($opts) {
    Clear-Screen
    Write-Host ""
    Write-Banner "PREVIEW"
    Write-Host ""
    Write-Host "  Sample data:  session 40%  |  context 82%  |  weekly 85%" -ForegroundColor DarkGray
    Write-Host ""

    $ESC   = [char]27
    $R     = "${ESC}[0m"
    $BOLD  = "${ESC}[1m"
    $DIM   = "${ESC}[2m"
    $CYN   = "${ESC}[36m"
    $YLW   = "${ESC}[33m"
    $GRN   = "${ESC}[32m"
    $RED   = "${ESC}[31m"
    $SEP_S = "${DIM}|${R}"

    $ROBOT = [char]::ConvertFromUtf32(0x1F916)
    $BOLT  = [char]::ConvertFromUtf32(0x26A1)
    $TIMER = [char]::ConvertFromUtf32(0x23F3)
    $BRAIN = [char]::ConvertFromUtf32(0x1F9E0)
    $XWARN = [char]::ConvertFromUtf32(0x26A0)
    $CAL   = [char]::ConvertFromUtf32(0x1F4C5)

    $w = $opts.barWidth

    # Session 40% used -> 60% left
    $sLeft = 60
    $sF    = [Math]::Min($w, [Math]::Max(0, [Math]::Round($sLeft / 100 * $w)))
    $sBar  = ("#" * $sF) + ("-" * ($w - $sF))
    $sCol  = if ($sLeft -ge 60) { $GRN } elseif ($sLeft -ge 30) { $YLW } else { $RED }

    # Context 82% used -> 18% left
    $cLeft = 18
    $cF    = [Math]::Min($w, [Math]::Max(0, [Math]::Round($cLeft / 100 * $w)))
    $cBar  = ("#" * $cF) + ("-" * ($w - $cF))
    $cCol  = if ($cLeft -ge 60) { $GRN } elseif ($cLeft -ge 30) { $YLW } else { $RED }

    # Weekly 85% used -> 15% left
    $wLeft = 15
    $wF    = [Math]::Min($w, [Math]::Max(0, [Math]::Round($wLeft / 100 * $w)))
    $wBar  = ("#" * $wF) + ("-" * ($w - $wF))
    $wCol  = if ($wLeft -ge 60) { $GRN } elseif ($wLeft -ge 30) { $YLW } else { $RED }

    # Build line 1
    $l1 = @()
    if ($opts.showModel)     { $l1 += "${ROBOT} ${CYN}${BOLD}Claude Sonnet 4.6${R}" }
    if ($opts.showSession)   { $l1 += "${BOLT} ${sCol}${sBar} ${sLeft}%${R}" }
    if ($opts.showCountdown) { $l1 += "${TIMER} ${DIM}reset 2h 0m${R}" }

    # Build line 2
    $l2 = @()
    if ($opts.showContext) { $l2 += "${BRAIN} ${cCol}${cBar} ${cLeft}%${R} ${DIM}(36k)${R}" }
    if ($opts.showCompact) { $l2 += "${XWARN}  ${YLW}${BOLD}compact soon${R}" }
    if ($opts.showWeekly -and 85 -ge $opts.weeklyThreshold) {
        $l2 += "${CAL} ${wCol}${wBar} ${wLeft}%${R}"
    }

    Write-Host "  Your status bar:" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host ("  +" + ("-" * 56) + "+") -ForegroundColor DarkGray

    if ($l1.Count -gt 0) {
        $line1str = "  |  " + ($l1 -join "  ${SEP_S}  ")
        [Console]::Write($line1str)
        [Console]::WriteLine()
    }
    if ($l2.Count -gt 0) {
        $line2str = "  |  " + ($l2 -join "  ${SEP_S}  ")
        [Console]::Write($line2str)
        [Console]::WriteLine()
    }
    if ($l1.Count -eq 0 -and $l2.Count -eq 0) {
        Write-Host "  |  (nothing to display -- all items are OFF)" -ForegroundColor DarkGray
    }

    Write-Host ("  +" + ("-" * 56) + "+") -ForegroundColor DarkGray
    Write-Host ""

    if ($opts.showWeekly -and 85 -lt $opts.weeklyThreshold) {
        Write-Host "  Note: Weekly bar hidden above (85% < threshold $($opts.weeklyThreshold)%)" -ForegroundColor DarkGray
        Write-Host "        It will appear once weekly usage reaches $($opts.weeklyThreshold)%." -ForegroundColor DarkGray
        Write-Host ""
    }
}

# ─── CUSTOMIZATION MENU ───────────────────────────────────────────────────────

function Show-CustomizeMenu {
    $BAR_WIDTHS        = @(6, 8, 10, 12)
    $WEEKLY_THRESHOLDS = @(0, 50, 60, 70, 80, 90)

    $opts = [PSCustomObject]@{
        showModel       = $true
        showSession     = $true
        showCountdown   = $true
        showContext     = $true
        showCompact     = $true
        showWeekly      = $true
        weeklyThreshold = 80
        barWidth        = 8
    }

    if (Test-Path $CFG_FILE) {
        try {
            $existing = Get-Content $CFG_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in @('showModel','showSession','showCountdown','showContext','showCompact','showWeekly','weeklyThreshold','barWidth')) {
                if ($existing.PSObject.Properties.Name -contains $p) { $opts.$p = $existing.$p }
            }
        } catch {}
    }

    while ($true) {
        Draw-Menu $opts
        $c = (Read-Host "  >").Trim().ToUpper()
        switch ($c) {
            "1" { $opts.showModel     = -not $opts.showModel }
            "2" { $opts.showSession   = -not $opts.showSession }
            "3" { $opts.showCountdown = -not $opts.showCountdown }
            "4" { $opts.showContext   = -not $opts.showContext }
            "5" { $opts.showCompact   = -not $opts.showCompact }
            "6" { $opts.showWeekly    = -not $opts.showWeekly }
            "7" {
                if ($opts.showWeekly) {
                    $idx = [Array]::IndexOf($WEEKLY_THRESHOLDS, [int]$opts.weeklyThreshold)
                    if ($idx -lt 0) { $idx = 0 }
                    $opts.weeklyThreshold = $WEEKLY_THRESHOLDS[($idx + 1) % $WEEKLY_THRESHOLDS.Length]
                }
            }
            "8" {
                $idx = [Array]::IndexOf($BAR_WIDTHS, [int]$opts.barWidth)
                if ($idx -lt 0) { $idx = 0 }
                $opts.barWidth = $BAR_WIDTHS[($idx + 1) % $BAR_WIDTHS.Length]
            }
            "N" {
                Draw-Preview $opts
                $confirm = (Read-Host "  Apply this configuration?  [Y = confirm / any key = go back]").Trim().ToUpper()
                if ($confirm -eq "Y") { return $opts }
            }
            "Q" { return $null }
        }
    }
}

# ─── INSTALL ──────────────────────────────────────────────────────────────────

function Invoke-Install {

    # ── CLAUDE CODE RUNNING CHECK ────────────────────────────────────────────
    $claudeProcs = @(Get-Process -Name "claude"      -ErrorAction SilentlyContinue) +
                   @(Get-Process -Name "claude-code"  -ErrorAction SilentlyContinue) +
                   @(Get-Process -Name "Claude"       -ErrorAction SilentlyContinue)
    $claudeProcs = $claudeProcs | Where-Object { $_ -ne $null }
    if ($claudeProcs.Count -gt 0) {
        Clear-Screen
        Write-Host ""
        Write-Banner "WARNING"
        Write-Host ""
        Write-Host "  Claude Code appears to be running!" -ForegroundColor Red
        Write-Host "  It will overwrite settings.json right after we write it." -ForegroundColor Yellow
        Write-Host "  Close Claude Code completely (window + system tray) first." -ForegroundColor Yellow
        Write-Host ""
        $cont = (Read-Host "  Continue anyway? [Y/N]").Trim().ToUpper()
        if ($cont -ne "Y") {
            Write-Host ""
            Write-Host "  Aborted. Close Claude Code, then re-run." -ForegroundColor DarkGray
            Write-Host ""
            return
        }
    }

    # ── CUSTOMIZE ────────────────────────────────────────────────────────────
    $config = Show-CustomizeMenu
    if (-not $config) {
        Clear-Screen
        Write-Host ""
        Write-Banner "CANCELLED"
        Write-Host ""
        Write-Host "  Installation cancelled." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # ── START INSTALL ────────────────────────────────────────────────────────
    Clear-Screen
    Write-Host ""
    Write-Banner "INSTALLING"
    Write-Host ""

    # ── EXECUTION POLICY ─────────────────────────────────────────────────────
    Write-Step "Execution policy"
    try {
        $current = Get-ExecutionPolicy -Scope CurrentUser
        if ($current -eq "Restricted" -or $current -eq "Undefined") {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
            Write-Ok "Set to RemoteSigned."
        } else {
            Write-Ok "Already permissive ($current) -- no change."
        }
    } catch {
        Write-Warn "Execution policy error: $_"
    }

    Write-Line

    # ── CLAUDE DIR ───────────────────────────────────────────────────────────
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

    Write-Line

    # ── DOWNLOAD WRAPPER ─────────────────────────────────────────────────────
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
        Write-Fail "statusline-wrapper.ps1 not found after install -- aborting."
    }

    try {
        Unblock-File -Path $PS1_DEST -ErrorAction Stop
        Write-Ok "Unblock-File succeeded."
    } catch {
        Write-Warn "Unblock-File failed -- proceeding anyway (-ExecutionPolicy Bypass covers this)."
    }

    $legacySh = Join-Path $CLAUDE_DIR "statusline-command.sh"
    if (Test-Path $legacySh) { Remove-Item $legacySh -Force; Write-Ok "Removed legacy statusline-command.sh." }

    Write-Line

    # ── SAVE CONFIG ──────────────────────────────────────────────────────────
    Write-Step "Saving statusline-config.json"
    try {
        $config | ConvertTo-Json -Depth 5 | Set-Content $CFG_FILE -Encoding UTF8
        Write-Ok "Config saved."
    } catch {
        Write-Warn "Could not save config: $_"
    }

    Write-Line

    # ── PATCH SETTINGS.JSON ──────────────────────────────────────────────────
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
            Write-Warn "Could not parse settings.json -- will create fresh."
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

    Write-Line

    # ── VERIFY: -Test FLAG ───────────────────────────────────────────────────
    Write-Step "Test 1/2 -- wrapper with -Test flag"
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

    Write-Line

    # ── VERIFY: STDIN PIPE ───────────────────────────────────────────────────
    Write-Step "Test 2/2 -- stdin pipe (simulates Claude Code)"
    try {
        $resetAt    = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 7200
        $testJson   = '{"model":{"display_name":"Claude Sonnet 4.6"},"context_window":{"used_percentage":35,"context_window_size":200000,"current_usage":{"input_tokens":70000}},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":RESETAT},"seven_day":{"used_percentage":20}}}'.Replace('RESETAT', $resetAt)
        $stdinResult = $testJson | & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PS1_DEST
        if ($stdinResult) {
            Write-Ok "Stdin pipe output:"
            $stdinResult | ForEach-Object { Write-Host "    $_" }
        } else {
            Write-Warn "Stdin pipe produced no output -- bar will not appear in Claude Code!"
        }
    } catch {
        Write-Warn "Stdin pipe test failed: $_"
    }

    Write-Line

    Write-Host ""
    Write-Banner "ALL DONE"
    Write-Host ""
    Write-Host "  Restart Claude Code to activate the status bar." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Installed to  : $CLAUDE_DIR" -ForegroundColor DarkGray
    Write-Host "  Reconfigure   : re-run this script and choose [1]" -ForegroundColor DarkGray
    Write-Host ""
}

# ─── UNINSTALL ────────────────────────────────────────────────────────────────

function Invoke-Uninstall {
    Clear-Screen
    Write-Host ""
    Write-Banner "UNINSTALLING"
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
        if (Test-Path $path) { Remove-Item $path -Force; Write-Ok "Deleted: $f" }
    }

    Write-Host ""
    Write-Banner "ALL DONE"
    Write-Host ""
    Write-Host "  Restart Claude Code to complete removal." -ForegroundColor Green
    Write-Host ""
}

# ─── MAIN MENU ────────────────────────────────────────────────────────────────

if ($Action -eq "") {
    Clear-Screen
    Write-Host ""
    Write-Banner "CLAUDE CODE -- STATUS BAR"
    Write-Host ""
    Write-Host "    [1]  Install       Set up the status bar" -ForegroundColor Cyan
    Write-Host "    [2]  Uninstall     Remove the status bar" -ForegroundColor Cyan
    Write-Host "    [Q]  Quit" -ForegroundColor DarkGray
    Write-Host ""
    Write-Line
    Write-Host ""
    $choice = (Read-Host "  >").Trim().ToUpper()
    switch ($choice) {
        "1"     { $Action = "install" }
        "2"     { $Action = "uninstall" }
        "Q"     { exit 0 }
        default { Write-Host "  Invalid choice." -ForegroundColor Red; exit 1 }
    }
}

# ─── DISPATCH ─────────────────────────────────────────────────────────────────

switch ($Action.ToLower()) {
    "install"   { Invoke-Install }
    "uninstall" { Invoke-Uninstall }
    default     { Write-Host "  Unknown action: $Action" -ForegroundColor Red; exit 1 }
}

#Requires -Version 5.1

param([string]$Action = "")

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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

# ─── NODE.JS VERSION CHECK & INSTALL ─────────────────────────────────────────

$MIN_NODE = 18

function Get-NodeMajor {
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $cmd) { return -1 }
    try {
        $v = & node --version 2>$null
        if ($v -match 'v(\d+)\.') { return [int]$matches[1] }
    } catch {}
    return -1
}

function Refresh-Path {
    $machine = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$machine;$user"
}

function Ensure-Node {
    $ver = Get-NodeMajor

    if ($ver -ge $MIN_NODE) { return $true }

    Clear-Screen
    Write-Host ""
    Write-Banner "NODE.JS REQUIRED"
    Write-Host ""

    if ($ver -ge 0) {
        Write-Warn "Node.js v$ver found — v$MIN_NODE+ required."
    } else {
        Write-Warn "Node.js not found."
    }
    Write-Host ""
    Write-Host "  The interactive setup menu requires Node.js $MIN_NODE+." -ForegroundColor DarkGray
    Write-Host "  Attempting automatic installation..." -ForegroundColor DarkGray
    Write-Host ""

    # ── Try winget (Windows 10 1709+ built-in) ───────────────────────────────
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Step "Installing via winget (OpenJS.NodeJS.LTS)..."
        $r = & winget install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements 2>&1
        Refresh-Path
        $ver = Get-NodeMajor
        if ($ver -ge $MIN_NODE) { Write-Ok "Node.js v$ver installed via winget."; return $true }
        Write-Warn "winget install did not produce a usable node."
    }

    # ── Try Chocolatey ──────────────────────────────────────────────────────
    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if ($choco) {
        Write-Step "Installing via Chocolatey (nodejs-lts)..."
        & choco install nodejs-lts -y 2>&1 | Out-Null
        Refresh-Path
        $ver = Get-NodeMajor
        if ($ver -ge $MIN_NODE) { Write-Ok "Node.js v$ver installed via Chocolatey."; return $true }
        Write-Warn "Chocolatey install did not produce a usable node."
    }

    # ── Manual fallback ─────────────────────────────────────────────────────
    Write-Host ""
    Write-Host ("  " + ("-" * 56)) -ForegroundColor DarkGray
    Write-Host "  Auto-install failed. Please install Node.js manually:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    https://nodejs.org/en/download  (choose LTS)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  After installing, re-run this script." -ForegroundColor DarkGray
    Write-Host ("  " + ("-" * 56)) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Falling back to the basic PowerShell menu instead." -ForegroundColor Yellow
    Write-Host ""
    return $false
}

# ─── PS TOGGLE MENU (fallback) ────────────────────────────────────────────────

function Toggle-Label($val) { if ($val) { "[ON ]" } else { "[OFF]" } }
function Toggle-Color($val) { if ($val) { "Green" } else { "DarkGray" } }

function Draw-Menu($opts) {
    Clear-Screen
    Write-Host ""
    Write-Banner "CONFIGURE YOUR STATUS BAR"
    Write-Host ""
    Write-Host "  LINE 1  (top row)" -ForegroundColor DarkGray
    Write-Line
    Write-Host ""
    Write-Host ("    [1]  " + (Toggle-Label $opts.showModel)     + "   Model name")          -ForegroundColor (Toggle-Color $opts.showModel)
    Write-Host ("    [2]  " + (Toggle-Label $opts.showSession)   + "   Session usage (5h)")   -ForegroundColor (Toggle-Color $opts.showSession)
    Write-Host ("    [3]  " + (Toggle-Label $opts.showCountdown) + "   Reset countdown")      -ForegroundColor (Toggle-Color $opts.showCountdown)
    Write-Host ""
    Write-Host "  LINE 2  (bottom row)" -ForegroundColor DarkGray
    Write-Line
    Write-Host ""
    Write-Host ("    [4]  " + (Toggle-Label $opts.showContext)   + "   Context window")       -ForegroundColor (Toggle-Color $opts.showContext)
    Write-Host ("    [5]  " + (Toggle-Label $opts.showCompact)   + "   Compact warning")      -ForegroundColor (Toggle-Color $opts.showCompact)
    if ($opts.showCompact) {
        $cLabel = if ($opts.compactThreshold -eq 0) { "Always visible" } else { "From $($opts.compactThreshold)% used" }
        Write-Host "    [8]        Visibility : $cLabel" -ForegroundColor Cyan
    } else {
        Write-Host "    [8]        (enable compact to configure)" -ForegroundColor DarkGray
    }
    Write-Host ("    [6]  " + (Toggle-Label $opts.showWeekly)    + "   Weekly usage")         -ForegroundColor (Toggle-Color $opts.showWeekly)
    if ($opts.showWeekly) {
        $tLabel = if ($opts.weeklyThreshold -eq 0) { "Always visible" } else { "From $($opts.weeklyThreshold)% usage" }
        Write-Host "    [7]        Visibility : $tLabel" -ForegroundColor Cyan
    } else {
        Write-Host "    [7]        (enable weekly to configure)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  STYLE" -ForegroundColor DarkGray
    Write-Line
    Write-Host ""
    $f = [Math]::Min($opts.barWidth, [Math]::Max(0, [Math]::Round(65 / 100 * $opts.barWidth)))
    $barPrev = ("#" * $f) + ("-" * ($opts.barWidth - $f))
    Write-Host ("    [9]        Bar width  : " + $opts.barWidth + "   [" + $barPrev + "]") -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  LAYOUT" -ForegroundColor DarkGray
    Write-Line
    Write-Host ""
    $layoutDesc = "default (2 lines)"
    if ($opts.layout -and $opts.layout.Count -gt 0) {
        $lineParts = @()
        foreach ($ln in $opts.layout) {
            $lArr = if ($ln -is [array]) { $ln } else { @($ln) }
            $lineParts += "[" + ($lArr -join ",") + "]"
        }
        $layoutDesc = "$($opts.layout.Count) line(s) -- " + ($lineParts -join "  ")
    }
    Write-Host "    [L]        Layout     : $layoutDesc" -ForegroundColor Cyan
    Write-Host ""
    Write-Line
    Write-Host "    [N]   Preview and continue" -ForegroundColor Yellow
    Write-Host "    [Q]   Cancel"               -ForegroundColor DarkGray
    Write-Line
    Write-Host ""
}

function Draw-Preview($opts) {
    Clear-Screen
    Write-Host ""
    Write-Banner "PREVIEW"
    Write-Host ""
    Write-Host "  Sample: session 40% | context 82% | weekly 85%" -ForegroundColor DarkGray
    Write-Host ""

    $ESC   = [char]27; $R = "${ESC}[0m"; $BOLD = "${ESC}[1m"; $DIM = "${ESC}[2m"
    $CYN = "${ESC}[36m"; $YLW = "${ESC}[33m"; $GRN = "${ESC}[32m"; $RED = "${ESC}[31m"
    $SEP_S = "${DIM}|${R}"
    $ROBOT = [char]::ConvertFromUtf32(0x1F916); $BOLT  = [char]::ConvertFromUtf32(0x26A1)
    $TIMER = [char]::ConvertFromUtf32(0x23F3);  $BRAIN = [char]::ConvertFromUtf32(0x1F9E0)
    $XWARN = [char]::ConvertFromUtf32(0x26A0);  $CAL   = [char]::ConvertFromUtf32(0x1F4C5)
    $w = $opts.barWidth

    function PBar($pct, $bw) { $f = [Math]::Min($bw, [Math]::Max(0, [Math]::Round($pct / 100 * $bw))); ("#" * $f) + ("-" * ($bw - $f)) }
    function PCol($pct) { if ($pct -ge 60) { $GRN } elseif ($pct -ge 30) { $YLW } else { $RED } }

    $compactSeg = $null
    if ($opts.showCompact -and 82 -ge $opts.compactThreshold) { $compactSeg = "${XWARN}  ${YLW}${BOLD}compact soon${R}" }
    $weeklySeg = $null
    if ($opts.showWeekly -and 85 -ge $opts.weeklyThreshold)   { $weeklySeg  = "${CAL} $(PCol 15)$(PBar 15 $w) 15%${R}" }

    $SEGS = @{
        'showModel'     = "${ROBOT} ${CYN}${BOLD}Claude Sonnet 4.6${R}"
        'showSession'   = "${BOLT} $(PCol 60)$(PBar 60 $w) 60%${R}"
        'showCountdown' = "${TIMER} ${DIM}reset 2h 0m${R}"
        'showContext'   = "${BRAIN} $(PCol 18)$(PBar 18 $w) 18%${R} ${DIM}(36k)${R}"
        'showCompact'   = $compactSeg
        'showWeekly'    = $weeklySeg
    }

    $layout = $opts.layout
    if (-not $layout -or ($layout -is [array] -and $layout.Count -eq 0)) {
        $layout = @(
            @('showModel', 'showSession', 'showCountdown'),
            @('showContext', 'showCompact', 'showWeekly')
        )
    }

    $anyDisplayed = $false
    Write-Host ("  +" + ("-" * 58) + "+") -ForegroundColor DarkGray
    foreach ($line in $layout) {
        $lineArr = if ($line -is [array]) { $line } else { @($line) }
        $rowSegs = @($lineArr | Where-Object { $opts.$_ -and $SEGS[$_] } | ForEach-Object { $SEGS[$_] })
        if ($rowSegs.Count -gt 0) {
            [Console]::Write("  |  " + ($rowSegs -join "  ${SEP_S}  ") + "`n")
            $anyDisplayed = $true
        }
    }
    if (-not $anyDisplayed) { Write-Host "  |  (nothing to display — all OFF)" -ForegroundColor DarkGray }
    Write-Host ("  +" + ("-" * 58) + "+") -ForegroundColor DarkGray
    Write-Host ""
}

# ─── LAYOUT MENU (PS fallback) ────────────────────────────────────────────────

function Show-LayoutMenu($opts) {
    $LABELS = @{
        'showModel'     = 'Model'
        'showSession'   = 'Session'
        'showCountdown' = 'Countdown'
        'showContext'   = 'Context'
        'showCompact'   = 'Compact'
        'showWeekly'    = 'Weekly'
    }
    $ALL_KEYS = @('showModel','showSession','showCountdown','showContext','showCompact','showWeekly')
    $enabled  = @($ALL_KEYS | Where-Object { $opts.$_ })

    if ($enabled.Count -eq 0) {
        Write-Host "  No features enabled." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        return
    }

    # ── Choose number of lines ──────────────────────────────────────────────
    $maxL = [Math]::Min(3, $enabled.Count)
    Clear-Screen; Write-Host ""; Write-Banner "LAYOUT  —  Number of lines"; Write-Host ""
    Write-Host "  Enabled features: $($enabled.Count)" -ForegroundColor DarkGray
    Write-Host ""
    for ($n = 1; $n -le $maxL; $n++) {
        $suffix = if ($n -gt 1) { "s" } else { "" }
        Write-Host "  [$n]  $n line$suffix" -ForegroundColor Cyan
    }
    Write-Host "  [Q]  Cancel" -ForegroundColor DarkGray
    Write-Host ""

    $c = (Read-Host "  >").Trim().ToUpper()
    if ($c -eq "Q") { return }
    $numLines = 0
    if (-not ([int]::TryParse($c, [ref]$numLines) -and $numLines -ge 1 -and $numLines -le $maxL)) { return }

    # ── Build layout line by line ───────────────────────────────────────────
    $layout    = @()
    $remaining = [System.Collections.ArrayList]@($enabled)

    for ($i = 0; $i -lt $numLines; $i++) {
        if ($remaining.Count -eq 0) { break }
        $isLast = ($i -eq $numLines - 1)

        if ($isLast) {
            # Last line gets remaining features — let user order them
            if ($remaining.Count -le 1) {
                $layout += , @($remaining)
            } else {
                $ordered   = [System.Collections.ArrayList]@()
                $toOrder   = [System.Collections.ArrayList]@($remaining)
                while ($toOrder.Count -gt 0) {
                    if ($toOrder.Count -eq 1) { [void]$ordered.Add($toOrder[0]); break }
                    Clear-Screen; Write-Host ""; Write-Banner "LINE $($i+1) of $numLines  —  order"; Write-Host ""
                    if ($ordered.Count -gt 0) {
                        Write-Host ("  So far: " + (($ordered | ForEach-Object { $LABELS[$_] }) -join " → ")) -ForegroundColor Green
                        Write-Host ""
                    }
                    Write-Host "  Position $($ordered.Count + 1) — pick next:" -ForegroundColor DarkGray
                    $toArr = @($toOrder)
                    for ($j = 0; $j -lt $toArr.Count; $j++) {
                        Write-Host "  [$($j+1)]  $($LABELS[$toArr[$j]])" -ForegroundColor Cyan
                    }
                    Write-Host "  [D]  Keep remaining in current order" -ForegroundColor Yellow
                    Write-Host ""
                    $p = (Read-Host "  >").Trim().ToUpper()
                    if ($p -eq "D") { foreach ($k in $toArr) { [void]$ordered.Add($k) }; break }
                    $idx = 0
                    if ([int]::TryParse($p, [ref]$idx) -and $idx -ge 1 -and $idx -le $toArr.Count) {
                        [void]$ordered.Add($toArr[$idx - 1])
                        [void]$toOrder.Remove($toArr[$idx - 1])
                    }
                }
                $layout += , @($ordered)
            }
            break
        }

        # Non-last line: pick features one by one in desired order
        $lineFeats = [System.Collections.ArrayList]@()

        while ($true) {
            $avail = @($remaining | Where-Object { -not $lineFeats.Contains($_) })
            if ($avail.Count -eq 0) { break }

            Clear-Screen; Write-Host ""; Write-Banner "LINE $($i+1) of $numLines"; Write-Host ""

            if ($lineFeats.Count -gt 0) {
                Write-Host ("  Current: " + (($lineFeats | ForEach-Object { $LABELS[$_] }) -join " → ")) -ForegroundColor Green
                Write-Host ""
            }

            Write-Host "  Pick features in display order:" -ForegroundColor DarkGray
            for ($j = 0; $j -lt $avail.Count; $j++) {
                Write-Host "  [$($j+1)]  $($LABELS[$avail[$j]])" -ForegroundColor Cyan
            }
            Write-Host ""
            if ($lineFeats.Count -ge 1) {
                Write-Host "  [D]  Done — confirm line $($i+1)" -ForegroundColor Yellow
            }
            Write-Host "  [Q]  Cancel layout" -ForegroundColor DarkGray
            Write-Host ""

            $p = (Read-Host "  >").Trim().ToUpper()
            if ($p -eq "Q") { return }
            if ($p -eq "D" -and $lineFeats.Count -ge 1) { break }

            $idx = 0
            if ([int]::TryParse($p, [ref]$idx) -and $idx -ge 1 -and $idx -le $avail.Count) {
                [void]$lineFeats.Add($avail[$idx - 1])
            }
        }

        if ($lineFeats.Count -gt 0) {
            $layout += , @($lineFeats)
            foreach ($k in @($lineFeats)) { [void]$remaining.Remove($k) }
        }
    }

    if ($layout.Count -gt 0) { $opts.layout = $layout }
}

function Build-DefaultLayout($opts) {
    $allKeys = @('showModel','showSession','showCountdown','showContext','showCompact','showWeekly')
    $enabled = @($allKeys | Where-Object { $opts.$_ })
    if ($enabled.Count -eq 0) { return @() }
    if ($enabled.Count -le 3) { return @(, @($enabled)) }
    $half = [Math]::Ceiling($enabled.Count / 2)
    return @(, @($enabled[0..($half-1)]), @($enabled[$half..($enabled.Count-1)]))
}

function Show-CustomizeMenu {
    $BAR_WIDTHS          = @(6, 8, 10, 12)
    $WEEKLY_THRESHOLDS   = @(0, 50, 60, 70, 80, 90)
    $COMPACT_THRESHOLDS  = @(0, 50, 60, 70, 80, 90)

    $opts = [PSCustomObject]@{
        showModel = $true; showSession = $true; showCountdown = $true
        showContext = $true; showCompact = $true; showWeekly = $true
        weeklyThreshold = 80; compactThreshold = 80; barWidth = 8
        layout = $null
    }

    if (Test-Path $CFG_FILE) {
        try {
            $ex = Get-Content $CFG_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in @('showModel','showSession','showCountdown','showContext','showCompact','showWeekly','weeklyThreshold','compactThreshold','barWidth')) {
                if ($ex.PSObject.Properties.Name -contains $p) { $opts.$p = $ex.$p }
            }
            # Load layout: convert JSON arrays back to PS arrays
            if ($ex.PSObject.Properties.Name -contains 'layout' -and $ex.layout) {
                $opts.layout = @($ex.layout | ForEach-Object { , @($_ | ForEach-Object { "$_" }) })
            }
        } catch {}
    }

    # Build default layout if none loaded
    if (-not $opts.layout -or $opts.layout.Count -eq 0) {
        $opts.layout = Build-DefaultLayout $opts
    }

    while ($true) {
        Draw-Menu $opts
        $c = (Read-Host "  >").Trim().ToUpper()
        switch ($c) {
            "1" { $opts.showModel     = -not $opts.showModel;     $opts.layout = Build-DefaultLayout $opts }
            "2" { $opts.showSession   = -not $opts.showSession;   $opts.layout = Build-DefaultLayout $opts }
            "3" { $opts.showCountdown = -not $opts.showCountdown; $opts.layout = Build-DefaultLayout $opts }
            "4" { $opts.showContext   = -not $opts.showContext;    $opts.layout = Build-DefaultLayout $opts }
            "5" { $opts.showCompact   = -not $opts.showCompact;   $opts.layout = Build-DefaultLayout $opts }
            "6" { $opts.showWeekly    = -not $opts.showWeekly;    $opts.layout = Build-DefaultLayout $opts }
            "7" {
                if ($opts.showWeekly) {
                    $idx = [Array]::IndexOf($WEEKLY_THRESHOLDS, [int]$opts.weeklyThreshold)
                    if ($idx -lt 0) { $idx = 0 }
                    $opts.weeklyThreshold = $WEEKLY_THRESHOLDS[($idx + 1) % $WEEKLY_THRESHOLDS.Length]
                }
            }
            "8" {
                if ($opts.showCompact) {
                    $idx = [Array]::IndexOf($COMPACT_THRESHOLDS, [int]$opts.compactThreshold)
                    if ($idx -lt 0) { $idx = 0 }
                    $opts.compactThreshold = $COMPACT_THRESHOLDS[($idx + 1) % $COMPACT_THRESHOLDS.Length]
                }
            }
            "9" {
                $idx = [Array]::IndexOf($BAR_WIDTHS, [int]$opts.barWidth)
                if ($idx -lt 0) { $idx = 0 }
                $opts.barWidth = $BAR_WIDTHS[($idx + 1) % $BAR_WIDTHS.Length]
            }
            "L" { Show-LayoutMenu $opts }
            "N" {
                Draw-Preview $opts
                $confirm = (Read-Host "  Apply? [Y / any key = back]").Trim().ToUpper()
                if ($confirm -eq "Y") { return $opts }
            }
            "Q" { return $null }
        }
    }
}

# ─── INSTALL (PS fallback) ────────────────────────────────────────────────────

function Invoke-Install {
    $claudeProcs = @(Get-Process -Name "claude","claude-code","Claude" -ErrorAction SilentlyContinue) | Where-Object { $_ }
    if ($claudeProcs.Count -gt 0) {
        Clear-Screen; Write-Host ""; Write-Banner "WARNING"; Write-Host ""
        Write-Host "  Claude Code appears to be running!" -ForegroundColor Red
        Write-Host "  Close it completely before continuing." -ForegroundColor Yellow
        Write-Host ""
        $cont = (Read-Host "  Continue anyway? [Y/N]").Trim().ToUpper()
        if ($cont -ne "Y") { Write-Host "  Aborted." -ForegroundColor DarkGray; return }
    }

    $config = Show-CustomizeMenu
    if (-not $config) {
        Clear-Screen; Write-Host ""; Write-Banner "CANCELLED"; Write-Host ""
        Write-Host "  Installation cancelled." -ForegroundColor DarkGray; Write-Host ""; return
    }

    Clear-Screen; Write-Host ""; Write-Banner "INSTALLING"; Write-Host ""

    Write-Step "Execution policy"
    try {
        $cur = Get-ExecutionPolicy -Scope CurrentUser
        if ($cur -eq "Restricted" -or $cur -eq "Undefined") {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
            Write-Ok "Set to RemoteSigned."
        } else { Write-Ok "Already permissive ($cur)." }
    } catch { Write-Warn "Execution policy: $_" }
    Write-Line

    Write-Step "Preparing ~/.claude"
    if (-not (Test-Path $CLAUDE_DIR)) { New-Item -ItemType Directory -Path $CLAUDE_DIR -Force | Out-Null }
    Write-Ok "Ready: $CLAUDE_DIR"
    Write-Line

    Write-Step "Installing statusline-wrapper.ps1"
    $localPs1 = if ($PSScriptRoot -and $PSScriptRoot -ne "") { Join-Path $PSScriptRoot "statusline-wrapper.ps1" } else { "" }
    if ($localPs1 -ne "" -and (Test-Path $localPs1)) {
        Copy-Item $localPs1 $PS1_DEST -Force; Write-Ok "Copied from local clone."
    } else {
        $url = "https://raw.githubusercontent.com/LucieFairePy/Claude-Code-StatusLine/main/statusline-wrapper.ps1"
        try {
            (New-Object System.Net.WebClient).DownloadFile($url, $PS1_DEST)
            Write-Ok "Downloaded."
        } catch {
            Write-Fail "Download failed: $_"
        }
    }
    try { Unblock-File $PS1_DEST -ErrorAction Stop; Write-Ok "Unblocked." } catch { Write-Warn "Unblock failed — proceeding." }
    Write-Line

    Write-Step "Saving config"
    $config | ConvertTo-Json -Depth 10 | Set-Content $CFG_FILE -Encoding UTF8
    Write-Ok "Config saved."
    Write-Line

    Write-Step "Patching settings.json"
    $cmdValue = [PSCustomObject]@{
        type    = "command"
        command = "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PS1_DEST`""
    }
    $settingsObj = [PSCustomObject]@{}
    if (Test-Path $SETTINGS) {
        $bk = "$SETTINGS.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $SETTINGS $bk; Write-Ok "Backup: $(Split-Path -Leaf $bk)"
        try { $settingsObj = [System.IO.File]::ReadAllText($SETTINGS, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch {}
    }
    if ($settingsObj.PSObject.Properties.Name -contains "statusLine") {
        $settingsObj.statusLine = $cmdValue
    } else {
        $settingsObj | Add-Member -NotePropertyName statusLine -NotePropertyValue $cmdValue
    }
    [System.IO.File]::WriteAllBytes($SETTINGS, [System.Text.Encoding]::UTF8.GetBytes(($settingsObj | ConvertTo-Json -Depth 10)))
    Write-Ok "settings.json updated."
    Write-Line

    Write-Step "Test"
    $r = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PS1_DEST -Test 2>$null
    if ($r) { Write-Ok "Output:"; $r | ForEach-Object { Write-Host "    $_" } }
    else    { Write-Warn "No output — check wrapper manually." }
    Write-Line

    Write-Host ""; Write-Banner "ALL DONE"; Write-Host ""
    Write-Host "  Restart Claude Code to activate." -ForegroundColor Green
    Write-Host ""
}

# ─── UNINSTALL ────────────────────────────────────────────────────────────────

function Invoke-Uninstall {
    Clear-Screen; Write-Host ""; Write-Banner "UNINSTALLING"; Write-Host ""
    if (Test-Path $SETTINGS) {
        $bk = "$SETTINGS.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $SETTINGS $bk; Write-Ok "Backup: $(Split-Path -Leaf $bk)"
        try {
            $s = [System.IO.File]::ReadAllText($SETTINGS, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            $s.PSObject.Properties.Remove("statusLine")
            [System.IO.File]::WriteAllBytes($SETTINGS, [System.Text.Encoding]::UTF8.GetBytes(($s | ConvertTo-Json -Depth 10)))
            Write-Ok "Removed statusLine."
        } catch { Write-Warn "Could not patch settings.json." }
    }
    foreach ($f in @("statusline-wrapper.ps1","statusline-command.sh","statusline-config.json")) {
        $p = Join-Path $CLAUDE_DIR $f
        if (Test-Path $p) { Remove-Item $p -Force; Write-Ok "Deleted: $f" }
    }
    Write-Host ""; Write-Banner "ALL DONE"; Write-Host ""
    Write-Host "  Restart Claude Code to complete removal." -ForegroundColor Green; Write-Host ""
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────

$setupJs    = if ($PSScriptRoot) { Join-Path $PSScriptRoot "setup.js" } else { "" }
$nodeReady  = ($setupJs -ne "" -and (Test-Path $setupJs)) -and (Ensure-Node)

if ($Action -eq "") {
    if ($nodeReady) {
        & node $setupJs
        exit $LASTEXITCODE
    }

    # Fallback: PowerShell menu
    Clear-Screen; Write-Host ""; Write-Banner "CLAUDE CODE -- STATUS BAR"; Write-Host ""
    Write-Host "    [1]  Install       Set up the status bar" -ForegroundColor Cyan
    Write-Host "    [2]  Uninstall     Remove the status bar" -ForegroundColor Cyan
    Write-Host "    [Q]  Quit"         -ForegroundColor DarkGray
    Write-Host ""; Write-Line; Write-Host ""
    $choice = (Read-Host "  >").Trim().ToUpper()
    switch ($choice) {
        "1"     { $Action = "install" }
        "2"     { $Action = "uninstall" }
        "Q"     { exit 0 }
        default { Write-Host "  Invalid choice." -ForegroundColor Red; exit 1 }
    }
}

switch ($Action.ToLower()) {
    "install"   {
        if ($nodeReady -and $setupJs) { & node $setupJs install;   exit $LASTEXITCODE }
        Invoke-Install
    }
    "uninstall" {
        if ($nodeReady -and $setupJs) { & node $setupJs uninstall; exit $LASTEXITCODE }
        Invoke-Uninstall
    }
    default { Write-Host "  Unknown action: $Action" -ForegroundColor Red; exit 1 }
}

#Requires -Version 5.1
param([switch]$Test)

$ErrorActionPreference = "SilentlyContinue"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8

$ESC    = [char]27
$RESET  = "${ESC}[0m"
$BOLD   = "${ESC}[1m"
$DIM    = "${ESC}[2m"
$CYAN   = "${ESC}[36m"
$YELLOW = "${ESC}[33m"
$GREEN  = "${ESC}[32m"
$RED    = "${ESC}[31m"
$SEP    = "${DIM}|${RESET}"

$E_ROBOT = [char]::ConvertFromUtf32(0x1F916)  # 🤖
$E_BOLT  = [char]::ConvertFromUtf32(0x26A1)   # ⚡
$E_TIMER = [char]::ConvertFromUtf32(0x23F3)   # ⏳
$E_BRAIN = [char]::ConvertFromUtf32(0x1F9E0)  # 🧠
$E_WARN  = [char]::ConvertFromUtf32(0x26A0)   # ⚠
$E_CAL   = [char]::ConvertFromUtf32(0x1F4C5)  # 📅

# ── Config ────────────────────────────────────────────────────────────────────

$configPath = Join-Path $PSScriptRoot "statusline-config.json"
$cfg = $null
if (Test-Path $configPath) {
    try { $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

function Cfg-Bool($key, $default) {
    if ($cfg -and ($cfg.PSObject.Properties.Name -contains $key)) { return [bool]$cfg.$key }
    $default
}
function Cfg-Int($key, $default) {
    if ($cfg -and ($cfg.PSObject.Properties.Name -contains $key)) { return [int]$cfg.$key }
    $default
}

$showModel       = Cfg-Bool 'showModel'       $true
$showSession     = Cfg-Bool 'showSession'     $true
$showCountdown   = Cfg-Bool 'showCountdown'   $true
$showContext     = Cfg-Bool 'showContext'     $true
$showCompact     = Cfg-Bool 'showCompact'     $true
$showWeekly      = Cfg-Bool 'showWeekly'      $true
$weeklyThreshold = Cfg-Int  'weeklyThreshold' 80
$barWidth        = Cfg-Int  'barWidth'        8

# ── Read JSON ─────────────────────────────────────────────────────────────────

$raw = ""

if ($Test) {
    $resetAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 7200
    $raw = "{`"model`":{`"display_name`":`"Claude Sonnet 4.6`"},`"context_window`":{`"used_percentage`":35,`"context_window_size`":200000,`"current_usage`":{`"input_tokens`":70000}},`"rate_limits`":{`"five_hour`":{`"used_percentage`":40,`"resets_at`":$resetAt},`"seven_day`":{`"used_percentage`":20}}}"
} else {
    try {
        $lines = @($input)
        if ($lines.Count -gt 0) { $raw = $lines -join "" }
    } catch {}
    if (-not $raw -and [Console]::IsInputRedirected) {
        try { $raw = [Console]::In.ReadToEnd() } catch {}
    }
}

$raw = $raw.Trim()
if (-not $raw) {
    [Console]::WriteLine("  [StatusLine: no data received -- check stdin piping]")
    exit 0
}

$data = $null
try { $data = $raw | ConvertFrom-Json } catch { exit 0 }
if (-not $data) { exit 0 }

# ── Helpers ───────────────────────────────────────────────────────────────────

function Make-Bar([double]$pct, [int]$w) {
    $filled = [Math]::Min($w, [Math]::Max(0, [Math]::Round($pct / 100 * $w)))
    ("#" * $filled) + ("-" * ($w - $filled))
}

function Get-Color([double]$pct) {
    if ($pct -ge 60) { return $GREEN }
    if ($pct -ge 30) { return $YELLOW }
    $RED
}

function Safe-Double($val) {
    try { $d = [double]$val; if ([double]::IsNaN($d)) { return $null }; return $d } catch { $null }
}
function Safe-Long($val)   { try { return [long]$val }   catch { $null } }
function Safe-String($val) {
    try { $s = [string]$val; if ($s -eq "" -or $s -eq "null") { return $null }; return $s } catch { $null }
}

# ── Parse fields ──────────────────────────────────────────────────────────────

$model      = Safe-String $data.model.display_name
$ctxUsed    = Safe-Double $data.context_window.used_percentage
$ctxSize    = Safe-Long   $data.context_window.context_window_size
$ctxInput   = Safe-Long   $data.context_window.current_usage.input_tokens
$fivePct    = Safe-Double $data.rate_limits.five_hour.used_percentage
$fiveResets = Safe-Long   $data.rate_limits.five_hour.resets_at
$weekPct    = Safe-Double $data.rate_limits.seven_day.used_percentage

if (-not $model) { $model = "Claude" }

# ── Countdown ─────────────────────────────────────────────────────────────────

$countdown = ""
if ($fiveResets -and $fiveResets -gt 0) {
    try {
        $diff = $fiveResets - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if ($diff -le 0) {
            $countdown = "now!"
        } else {
            $h = [Math]::Floor($diff / 3600)
            $m = [Math]::Floor(($diff % 3600) / 60)
            $countdown = if ($h -gt 0) { "${h}h ${m}m" } else { "${m}m" }
        }
    } catch {}
}

# ── Line 1: model + session + countdown ───────────────────────────────────────

$l1 = @()

if ($showModel) {
    $l1 += "${E_ROBOT} ${CYAN}${BOLD}${model}${RESET}"
}

if ($showSession) {
    if ($null -ne $fivePct) {
        $left = [Math]::Round(100 - $fivePct)
        $l1 += "${E_BOLT} $(Get-Color $left)$(Make-Bar $left $barWidth) ${left}%${RESET}"
    } else {
        $l1 += "${E_BOLT} ${DIM}$('-' * $barWidth)${RESET}"
    }
}

if ($showCountdown -and $countdown) {
    if ($countdown -eq "now!") {
        $l1 += "${E_TIMER} ${RED}${BOLD}reset now!${RESET}"
    } else {
        $l1 += "${E_TIMER} ${DIM}reset ${countdown}${RESET}"
    }
}

$line1 = if ($l1.Count -gt 0) { "  " + ($l1 -join "  ${SEP}  ") } else { "" }

# ── Line 2: context + warnings ────────────────────────────────────────────────

$l2 = @()

if ($showContext) {
    if ($null -ne $ctxUsed) {
        $left = [Math]::Round(100 - $ctxUsed)
        $rem  = ""
        if ($null -ne $ctxSize -and $null -ne $ctxInput) {
            $r   = [Math]::Max(0, $ctxSize - $ctxInput)
            $rem = if ($r -ge 1000) { " ${DIM}($([Math]::Round($r / 1000))k)${RESET}" } else { " ${DIM}(${r})${RESET}" }
        }
        $l2 += "${E_BRAIN} $(Get-Color $left)$(Make-Bar $left $barWidth) ${left}%${RESET}${rem}"
    } else {
        $l2 += "${E_BRAIN} ${DIM}$('-' * $barWidth)${RESET}"
    }
}

if ($showCompact -and $null -ne $ctxUsed -and $ctxUsed -ge 80) {
    $l2 += "${E_WARN}  ${YELLOW}${BOLD}compact soon${RESET}"
}

if ($showWeekly -and $null -ne $weekPct -and [Math]::Round($weekPct) -ge $weeklyThreshold) {
    $left = [Math]::Round(100 - $weekPct)
    $l2 += "${E_CAL} $(Get-Color $left)$(Make-Bar $left $barWidth) ${left}%${RESET}"
}

$line2 = if ($l2.Count -gt 0) { "  " + ($l2 -join "  ${SEP}  ") } else { "" }

# ── Output ────────────────────────────────────────────────────────────────────

if ($line1) { [Console]::WriteLine($line1) }
if ($line2) { [Console]::WriteLine($line2) }

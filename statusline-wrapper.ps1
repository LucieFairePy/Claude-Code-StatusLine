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

$E_ROBOT = [char]::ConvertFromUtf32(0x1F916)
$E_BOLT  = [char]::ConvertFromUtf32(0x26A1)
$E_TIMER = [char]::ConvertFromUtf32(0x23F3)
$E_BRAIN = [char]::ConvertFromUtf32(0x1F9E0)
$E_WARN  = [char]::ConvertFromUtf32(0x26A0)
$E_CAL   = [char]::ConvertFromUtf32(0x1F4C5)

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

$showModel        = Cfg-Bool 'showModel'        $true
$showSession      = Cfg-Bool 'showSession'      $true
$showCountdown    = Cfg-Bool 'showCountdown'    $true
$showContext      = Cfg-Bool 'showContext'      $true
$showCompact      = Cfg-Bool 'showCompact'      $true
$showWeekly       = Cfg-Bool 'showWeekly'       $true
$weeklyThreshold  = Cfg-Int  'weeklyThreshold'  80
$compactThreshold = Cfg-Int  'compactThreshold' 80
$barWidth         = Cfg-Int  'barWidth'         8

# Layout: array of arrays of feature keys, defines lines and order
# Default: line1 = model+session+countdown, line2 = context+compact+weekly
$layout = $null
if ($cfg -and $cfg.PSObject.Properties.Name -contains 'layout') {
    try {
        $rawLayout = $cfg.layout
        if ($rawLayout -and $rawLayout.Count -gt 0) {
            $tmp = [System.Collections.ArrayList]::new()
            foreach ($row in $rawLayout) { [void]$tmp.Add(@($row | ForEach-Object { [string]$_ })) }
            $layout = $tmp.ToArray()
        }
    } catch {}
}
if (-not $layout) {
    $layout = @(
        @('showModel','showSession','showCountdown'),
        @('showContext','showCompact','showWeekly')
    )
}

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

# ── Context remaining — precise format ────────────────────────────────────────

$ctxRem = ""
if ($null -ne $ctxSize -and $null -ne $ctxUsed) {
    $r = [Math]::Max(0, [long]($ctxSize * (100 - $ctxUsed) / 100))
    if ($r -ge 10000) {
        $ctxRem = " ${DIM}($([Math]::Round($r / 1000))k)${RESET}"
    } elseif ($r -ge 1000) {
        $rk = [Math]::Round($r / 100) / 10
        $ctxRem = " ${DIM}($($rk.ToString('F1'))k)${RESET}"
    } else {
        $ctxRem = " ${DIM}(${r})${RESET}"
    }
} elseif ($null -ne $ctxSize -and $null -ne $ctxInput) {
    $r = [Math]::Max(0, $ctxSize - $ctxInput)
    if ($r -ge 10000) {
        $ctxRem = " ${DIM}($([Math]::Round($r / 1000))k)${RESET}"
    } elseif ($r -ge 1000) {
        $rk = [Math]::Round($r / 100) / 10
        $ctxRem = " ${DIM}($($rk.ToString('F1'))k)${RESET}"
    } else {
        $ctxRem = " ${DIM}(${r})${RESET}"
    }
}

# ── Segment builder ───────────────────────────────────────────────────────────

function Build-Segment($key) {
    switch ($key) {
        'showModel' {
            if (-not $showModel) { return $null }
            return "${E_ROBOT} ${CYAN}${BOLD}${model}${RESET}"
        }
        'showSession' {
            if (-not $showSession) { return $null }
            if ($null -ne $fivePct) {
                $left = [Math]::Round(100 - $fivePct)
                return "${E_BOLT} $(Get-Color $left)$(Make-Bar $left $barWidth) ${left}%${RESET}"
            }
            return "${E_BOLT} ${DIM}$('-' * $barWidth)${RESET}"
        }
        'showCountdown' {
            if (-not $showCountdown -or -not $countdown) { return $null }
            if ($countdown -eq "now!") { return "${E_TIMER} ${RED}${BOLD}reset now!${RESET}" }
            return "${E_TIMER} ${DIM}reset ${countdown}${RESET}"
        }
        'showContext' {
            if (-not $showContext) { return $null }
            if ($null -ne $ctxUsed) {
                $left = [Math]::Round(100 - $ctxUsed)
                return "${E_BRAIN} $(Get-Color $left)$(Make-Bar $left $barWidth) ${left}%${RESET}${ctxRem}"
            }
            return "${E_BRAIN} ${DIM}$('-' * $barWidth)${RESET}"
        }
        'showCompact' {
            if (-not $showCompact) { return $null }
            if ($null -ne $ctxUsed -and $ctxUsed -ge $compactThreshold) {
                return "${E_WARN}  ${YELLOW}${BOLD}compact soon${RESET}"
            }
            return $null
        }
        'showWeekly' {
            if (-not $showWeekly) { return $null }
            if ($null -ne $weekPct -and [Math]::Round($weekPct) -ge $weeklyThreshold) {
                $left = [Math]::Round(100 - $weekPct)
                return "${E_CAL} $(Get-Color $left)$(Make-Bar $left $barWidth) ${left}%${RESET}"
            }
            return $null
        }
    }
    return $null
}

# ── Build and output lines ────────────────────────────────────────────────────

foreach ($lineKeys in $layout) {
    $parts = @()
    foreach ($key in $lineKeys) {
        $seg = Build-Segment $key
        if ($seg) { $parts += $seg }
    }
    if ($parts.Count -gt 0) {
        [Console]::WriteLine("  " + ($parts -join "  ${SEP}  "))
    }
}

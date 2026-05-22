#Requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ESC    = [char]27
$RESET  = "${ESC}[0m"
$BOLD   = "${ESC}[1m"
$DIM    = "${ESC}[2m"
$CYAN   = "${ESC}[36m"
$YELLOW = "${ESC}[33m"
$GREEN  = "${ESC}[32m"
$RED    = "${ESC}[31m"
$SEP    = "${DIM}|${RESET}"

# Load config
$configPath = Join-Path $PSScriptRoot "statusline-config.json"
$cfg = $null
if (Test-Path $configPath) {
    try { $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

function Cfg-Bool($key, $default) {
    if ($cfg -and ($cfg.PSObject.Properties.Name -contains $key)) { return [bool]$cfg.$key }
    return $default
}
function Cfg-Int($key, $default) {
    if ($cfg -and ($cfg.PSObject.Properties.Name -contains $key)) { return [int]$cfg.$key }
    return $default
}

$showSession   = Cfg-Bool 'showSession'   $true
$showCountdown = Cfg-Bool 'showCountdown' $true
$showContext   = Cfg-Bool 'showContext'   $true
$showCompact   = Cfg-Bool 'showCompact'   $true
$showWeekly    = Cfg-Bool 'showWeekly'    $true
$barWidth      = Cfg-Int  'barWidth'      8

# Read stdin
$raw = ""
try { $raw = [Console]::In.ReadToEnd() } catch {}
if (-not $raw -or $raw.Trim() -eq "") { exit 0 }

$data = $null
try { $data = $raw | ConvertFrom-Json } catch { exit 0 }
if (-not $data) { exit 0 }

function Make-Bar([double]$pct, [int]$w) {
    $filled = [Math]::Min($w, [Math]::Max(0, [Math]::Round($pct / 100 * $w)))
    ("#" * $filled) + ("-" * ($w - $filled))
}

function Get-Color([double]$pct) {
    if ($pct -ge 60) { return $GREEN }
    if ($pct -ge 30) { return $YELLOW }
    return $RED
}

$model      = try { $data.model.display_name }                                    catch { $null }
$ctxUsed    = try { [double]$data.context_window.used_percentage }                catch { $null }
$ctxSize    = try { [long]$data.context_window.context_window_size }              catch { $null }
$ctxInput   = try { [long]$data.context_window.current_usage.input_tokens }       catch { $null }
$fivePct    = try { [double]$data.rate_limits.five_hour.used_percentage }         catch { $null }
$fiveResets = try { [long]$data.rate_limits.five_hour.resets_at }                 catch { $null }
$weekPct    = try { [double]$data.rate_limits.seven_day.used_percentage }         catch { $null }

if (-not $model) { $model = "Claude" }

$countdown = ""
if ($fiveResets) {
    $diff = $fiveResets - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($diff -le 0) {
        $countdown = "now!"
    } else {
        $h = [Math]::Floor($diff / 3600)
        $m = [Math]::Floor(($diff % 3600) / 60)
        $countdown = if ($h -gt 0) { "${h}h ${m}m" } else { "${m}m" }
    }
}

# ── Line 1 ──────────────────────────────────────────────────────────────────

$line1 = "  🤖 ${CYAN}${BOLD}${model}${RESET}"

if ($showSession) {
    if ($null -ne $fivePct) {
        $left = [Math]::Round(100 - $fivePct)
        $line1 += "  ${SEP}  ⚡ $(Get-Color $left)$(Make-Bar $left $barWidth) ${left}%${RESET}"
    } else {
        $line1 += "  ${SEP}  ⚡ ${DIM}$('-' * $barWidth)${RESET}"
    }
}

if ($showCountdown -and $countdown) {
    if ($countdown -eq "now!") {
        $line1 += "  ${SEP}  ⏳ ${RED}${BOLD}reset now!${RESET}"
    } else {
        $line1 += "  ${SEP}  ⏳ ${DIM}reset ${countdown}${RESET}"
    }
}

# ── Line 2 ──────────────────────────────────────────────────────────────────

$line2 = ""

if ($showContext) {
    if ($null -ne $ctxUsed) {
        $left = [Math]::Round(100 - $ctxUsed)
        $rem  = ""
        if ($null -ne $ctxSize -and $null -ne $ctxInput) {
            $r   = [Math]::Max(0, $ctxSize - $ctxInput)
            $rem = if ($r -ge 1000) { " ${DIM}($([Math]::Round($r / 1000))k)${RESET}" } else { " ${DIM}(${r})${RESET}" }
        }
        $line2 = "  🧠 $(Get-Color $left)$(Make-Bar $left $barWidth) ${left}%${RESET}${rem}"
    } else {
        $line2 = "  🧠 ${DIM}$('-' * $barWidth)${RESET}"
    }
}

if ($showCompact -and $null -ne $ctxUsed -and $ctxUsed -ge 80) {
    $line2 += "  ${SEP}  ${YELLOW}${BOLD}⚠️  compact soon${RESET}"
}

if ($showWeekly -and $null -ne $weekPct -and [Math]::Round($weekPct) -ge 80) {
    $left   = [Math]::Round(100 - $weekPct)
    $line2 += "  ${SEP}  ${RED}${BOLD}📅 $(Get-Color $left)$(Make-Bar $left $barWidth) ${left}%${RESET}"
}

[Console]::WriteLine($line1)
if ($line2) { [Console]::WriteLine($line2) }

#Requires -Version 5.1

$ErrorActionPreference = "Stop"

$CLAUDE_DIR = Join-Path $env:USERPROFILE ".claude"
$SETTINGS   = Join-Path $CLAUDE_DIR "settings.json"

function Write-Ok   { param($msg) Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  !! $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  Claude Code Statusline -- Uninstaller" -ForegroundColor Magenta
Write-Host "  =======================================" -ForegroundColor Magenta
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

foreach ($f in @("statusline-command.sh", "statusline-wrapper.ps1")) {
    $path = Join-Path $CLAUDE_DIR $f
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-Ok "Deleted: $f"
    }
}

Write-Host ""
Write-Host "  Done. Restart Claude Code to complete removal." -ForegroundColor Green
Write-Host ""

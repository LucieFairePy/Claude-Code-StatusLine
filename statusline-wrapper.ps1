# Locate Git Bash (supports standard install paths)
$gitBash = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $gitBash) {
    $found = Get-Command bash -ErrorAction SilentlyContinue
    if ($found) { $gitBash = $found.Source }
}

if (-not $gitBash) { exit 1 }

$bashScript = Join-Path $PSScriptRoot "statusline-command.sh"
$input | & $gitBash $bashScript

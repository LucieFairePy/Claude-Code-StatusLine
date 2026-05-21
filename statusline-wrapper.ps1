$gitBash = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $gitBash) {
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { $gitBash = $cmd.Source }
}

if (-not $gitBash) { exit 1 }

$input | & $gitBash (Join-Path $PSScriptRoot "statusline-command.sh")

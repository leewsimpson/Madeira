# Windows hosts: set SDKROOT so tests/host/check-*.py can compile production
# Swift with the swift.org toolchain. Dot-source it once per shell:
#   . tools/host/env.ps1
#   python tests/host/check-duo-display.py
# macOS and Linux hosts need nothing; this file is a no-op there.
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    $platforms = Join-Path $env:LOCALAPPDATA 'Programs/Swift/Platforms'
    $sdk = Get-ChildItem $platforms -Directory -ErrorAction SilentlyContinue |
        Sort-Object { [version]($_.Name -replace '[^0-9.].*$', '') } -Descending |
        ForEach-Object { Join-Path $_.FullName 'Windows.platform/Developer/SDKs/Windows.sdk' } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($sdk) { $env:SDKROOT = $sdk; Write-Host "SDKROOT=$sdk" }
    else { Write-Warning "No Windows.sdk under $platforms; install Swift from swift.org" }
}

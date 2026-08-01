<#
Compiles and runs the race-simulator validation harness on Windows.

The simulator is pure Foundation, so it builds and runs anywhere Swift does.
Everything else in RaceMe needs a Mac; this doesn't — which means the part the
product most depends on can be measured rather than assumed.

Requires:
  winget install Swift.Toolchain
  Visual Studio 2022 with the C++ workload (Swift on Windows links with MSVC)

Usage:  pwsh -File Scripts/validate.ps1
#>

$ErrorActionPreference = 'Stop'

$swiftRoot = Join-Path $env:LOCALAPPDATA 'Programs\Swift'
if (-not (Test-Path $swiftRoot)) {
    Write-Error "No Swift toolchain found. Install it with:  winget install Swift.Toolchain"
}

function Latest($dir) {
    Get-ChildItem $dir -Directory | Sort-Object Name | Select-Object -Last 1 -ExpandProperty Name
}

$toolchain = Latest (Join-Path $swiftRoot 'Toolchains')
$runtime   = Latest (Join-Path $swiftRoot 'Runtimes')
$platform  = Latest (Join-Path $swiftRoot 'Platforms')

$sdk = Join-Path $swiftRoot "Platforms\$platform\Windows.platform\Developer\SDKs\Windows.sdk"
if (-not (Test-Path $sdk)) { Write-Error "Swift Windows SDK not found at $sdk" }

# Swift on Windows links through MSVC, so the compiler has to run inside a
# Visual Studio developer environment or it can't find link.exe.
$vcvars = @(
    'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat'
    'C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat'
    'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat'
    'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $vcvars) {
    Write-Error "vcvars64.bat not found. Install Visual Studio 2022 with the 'Desktop development with C++' workload."
}

$repo = Split-Path $PSScriptRoot -Parent
Push-Location $repo
try {
    $sources = @(
        'RaceMe\Simulation\Rng.swift'
        'RaceMe\Model\Archetype.swift'
        'RaceMe\Simulation\PaceSpread.swift'
        'RaceMe\Simulation\GhostRunner.swift'
        'Validation\main.swift'
    ) -join ' '

    $cmd = @"
call "$vcvars" >nul 2>&1
set "SDKROOT=$sdk"
set "PATH=$swiftRoot\Toolchains\$toolchain\usr\bin;$swiftRoot\Runtimes\$runtime\usr\bin;%PATH%"
swiftc -O -sdk "%SDKROOT%" $sources -o validate.exe
if errorlevel 1 exit /b 1
".\validate.exe"
exit /b %ERRORLEVEL%
"@

    $tmp = Join-Path $env:TEMP "raceme_validate_$PID.bat"
    Set-Content -Path $tmp -Value $cmd -Encoding ASCII
    Write-Host "Building and running the simulator validation..." -ForegroundColor Cyan
    Write-Host ""
    & cmd /c $tmp
    $code = $LASTEXITCODE
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    exit $code
}
finally {
    Pop-Location
}

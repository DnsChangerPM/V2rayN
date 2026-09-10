#Requires -Version 5.1
<#
.SYNOPSIS
    Generates the Windows runner for the Flutter app and applies Radin's
    customizations (icon, product information).

.DESCRIPTION
    `flutter create` is the only supported way to produce the CMake based
    Windows runner, so the folder is generated during CI instead of being
    committed. This script:
      1. backs up pubspec.yaml (flutter create rewrites it),
      2. runs `flutter create --platforms=windows`,
      3. restores pubspec.yaml,
      4. copies the application icon over the generated placeholder,
      5. patches the generated Runner.rc with the real version numbers
         (best effort: never fails the build).

    All output goes through Write-Output so that CI can capture it.
#>
[CmdletBinding()]
param(
    [string] $ProjectName = 'radin',
    [string] $Organization = 'com.radin',
    [string] $Version = '0.0.0',
    [string] $ProductName = 'Radin',
    [string] $CompanyName = 'Radin',
    [string] $Root = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

Write-Output "==> Generating the Windows runner for $ProductName $Version"
Write-Output "    root      : $Root"
Write-Output "    flutter   : $((Get-Command flutter -ErrorAction SilentlyContinue).Source)"
Write-Output "    flutter -version:"; & flutter --version 2>&1 | ForEach-Object { Write-Output "      $_" }

$pubspec = Join-Path $Root 'pubspec.yaml'
$backup = Join-Path $Root 'pubspec.yaml.radin.bak'

if (Test-Path $pubspec) {
    Copy-Item -Path $pubspec -Destination $backup -Force
}

try {
    Write-Output '==> flutter create --platforms=windows'
    $output = & flutter create --platforms=windows --project-name $ProjectName --org $Organization --no-pub $Root 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Output "    $_" }
    Write-Output "    exit code: $code"

    $mainCpp = Join-Path $Root 'windows/runner/main.cpp'
    if (-not (Test-Path $mainCpp)) {
        Write-Output '    windows content after create:'
        if (Test-Path (Join-Path $Root 'windows')) {
            Get-ChildItem -Path (Join-Path $Root 'windows') -Recurse -Depth 2 |
                ForEach-Object { Write-Output "      $($_.FullName)" }
        }
        else {
            Write-Output '      (no windows folder at all)'
        }
        throw "flutter create did not produce windows/runner/main.cpp (exit $code)"
    }

    if (Test-Path $backup) {
        Copy-Item -Path $backup -Destination $pubspec -Force
    }
}
finally {
    if (Test-Path $backup) {
        Remove-Item -Path $backup -Force
    }
}

# --- application icon -------------------------------------------------------
$iconSource = Join-Path $Root 'windows_custom/runner/resources/app_icon.ico'
$iconTarget = Join-Path $Root 'windows/runner/resources/app_icon.ico'
if (Test-Path $iconSource) {
    New-Item -ItemType Directory -Force -Path (Split-Path $iconTarget) | Out-Null
    Copy-Item -Path $iconSource -Destination $iconTarget -Force
    Write-Output "==> Icon installed: $iconTarget"
}
else {
    Write-Output "==> WARNING: icon not found at $iconSource (keeping the Flutter default)"
}

# --- version resource (best effort) -----------------------------------------
$rc = Join-Path $Root 'windows/runner/Runner.rc'
if (Test-Path $rc) {
    try {
        $versionMatch = [regex]::Match($Version, '^(\d+)\.(\d+)\.(\d+)')
        if ($versionMatch.Success) {
            $major = $versionMatch.Groups[1].Value
            $minor = $versionMatch.Groups[2].Value
            $patch = $versionMatch.Groups[3].Value
            $content = Get-Content -Path $rc -Raw -Encoding UTF8
            $content = $content -replace 'FILEVERSION\s+[0-9,\s]+', "FILEVERSION $major,$minor,$patch,0"
            $content = $content -replace 'PRODUCTVERSION\s+[0-9,\s]+', "PRODUCTVERSION $major,$minor,$patch,0"
            $content = $content -replace 'VALUE "FileVersion",\s*"[^"]*"', "VALUE `"FileVersion`", `"$Version`""
            $content = $content -replace 'VALUE "ProductVersion",\s*"[^"]*"', "VALUE `"ProductVersion`", `"$Version`""
            $content = $content -replace 'VALUE "ProductName",\s*"[^"]*"', "VALUE `"ProductName`", `"$ProductName`""
            $content = $content -replace 'VALUE "CompanyName",\s*"[^"]*"', "VALUE `"CompanyName`", `"$CompanyName`""
            Set-Content -Path $rc -Value $content -Encoding UTF8
            Write-Output '==> Runner.rc version resource updated.'
        }
    }
    catch {
        Write-Output "==> WARNING: could not patch Runner.rc: $($_.Exception.Message)"
    }
}

Write-Output '==> Windows runner ready.'

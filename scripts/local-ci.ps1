[CmdletBinding()]
param(
    [string]$RepoPath = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $RepoPath 'pubspec.yaml'))) {
    throw "RepoPath is not a Flutter checkout: $RepoPath"
}

Push-Location $RepoPath
try {
    $pubspec = Get-Content -LiteralPath (Join-Path $RepoPath 'pubspec.yaml') -Raw
    if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
        throw 'Unable to determine pubspec version.'
    }
    $version = $Matches[1]

    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE" }

    flutter gen-l10n
    if ($LASTEXITCODE -ne 0) { throw "flutter gen-l10n failed with exit code $LASTEXITCODE" }

    dart run build_runner build
    if ($LASTEXITCODE -ne 0) { throw "dart run build_runner build failed with exit code $LASTEXITCODE" }

    dart run tool/verify_arb_descriptions.dart
    if ($LASTEXITCODE -ne 0) { throw "ARB descriptions failed with exit code $LASTEXITCODE" }

    dart run tool/validate_arb_locales.dart
    if ($LASTEXITCODE -ne 0) { throw "ARB locales failed with exit code $LASTEXITCODE" }

    dart run tool/validate_release_notes.dart --version $version
    if ($LASTEXITCODE -ne 0) { throw "release notes validation failed with exit code $LASTEXITCODE" }

    flutter analyze --no-fatal-warnings --no-fatal-infos
    if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed with exit code $LASTEXITCODE" }

    Write-Host '=== THOXWARROOM LOCAL CI GREEN ==='
}
finally {
    Pop-Location
}

[CmdletBinding()]
param(
    [string]$RepoPath = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
$Runner = Join-Path $RepoPath 'scripts\ci_unsigned.sh'
if (-not (Test-Path -LiteralPath $Runner)) {
    throw "Unsigned CI runner is missing: $Runner"
}

$gitBash = Join-Path 'C:\Program Files\Git\bin' 'bash.exe'
if (-not (Test-Path -LiteralPath $gitBash)) {
    $gitBash = (Get-Command bash -ErrorAction Stop).Source
}

ssh -o BatchMode=yes -o ConnectTimeout=5 knightdev@100.64.44.121 'cd /Users/knightdev/Projects/thoxwarroom-local-ci-20260830 && git pull --ff-only && bash scripts/ci_unsigned.sh'
if ($LASTEXITCODE -ne 0) {
    throw "scripts/ci_unsigned.sh failed with exit code $LASTEXITCODE"
}

Write-Host '=== THOXWARROOM LOCAL CI GREEN ==='

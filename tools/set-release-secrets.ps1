# Uploads the four MUSIX_* GitHub Actions secrets that .github/workflows/release.yml
# needs to sign a release APK.
#
# This file contains no secrets. It reads them from the two gitignored artifacts
# a developer already has locally:
#
#   keystore.b64            base64 of the release .jks  (repo root)
#   android/key.properties  storePassword / keyAlias / keyPassword
#
# Both are produced by the signing setup; see CONTRIBUTING.md -> Release signing.
#
# Usage (from anywhere in the repo):
#
#   pwsh tools/set-release-secrets.ps1
#   pwsh tools/set-release-secrets.ps1 -Repo owner/fork
#
# Requires the GitHub CLI (`gh`) to be installed and authenticated once with
# `gh auth login`.

[CmdletBinding()]
param(
    [string]$Repo = 'khisa318/music_app',
    [string]$KeystoreBase64Path,
    [string]$KeyPropertiesPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $KeystoreBase64Path) { $KeystoreBase64Path = Join-Path $repoRoot 'keystore.b64' }
if (-not $KeyPropertiesPath)  { $KeyPropertiesPath  = Join-Path $repoRoot 'android\key.properties' }

foreach ($path in @($KeystoreBase64Path, $KeyPropertiesPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required file: $path"
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI (gh) is not installed. See https://cli.github.com'
}

gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    throw "gh is not authenticated. Run 'gh auth login' first."
}

# key.properties is a flat key=value file with '#' comments.
$props = @{}
foreach ($line in Get-Content -LiteralPath $KeyPropertiesPath) {
    $trimmed = $line.Trim()
    if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

    $separator = $trimmed.IndexOf('=')
    if ($separator -lt 1) { continue }

    $key = $trimmed.Substring(0, $separator).Trim()
    $value = $trimmed.Substring($separator + 1).Trim()
    $props[$key] = $value
}

foreach ($required in @('storePassword', 'keyAlias', 'keyPassword')) {
    if ([string]::IsNullOrWhiteSpace($props[$required])) {
        throw "android/key.properties is missing '$required'"
    }
}

# Thumbprint the keystore so the operator can compare it against the SHA-256 the
# release workflow prints - a cheap guard against uploading the wrong key.
#
# -Raw and .Trim() matter: a trailing newline breaks the basic Base64 decoder
# android/app/build.gradle.kts uses, so the very whitespace that piping to a
# native command tends to add is what this removes.
$base64 = (Get-Content -LiteralPath $KeystoreBase64Path -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($base64)) {
    throw "keystore.b64 is empty"
}

$secrets = [ordered]@{
    MUSIX_KEYSTORE_BASE64   = $base64
    MUSIX_KEYSTORE_PASSWORD = $props['storePassword']
    MUSIX_KEY_ALIAS         = $props['keyAlias']
    MUSIX_KEY_PASSWORD      = $props['keyPassword']
}

Write-Host "Uploading signing secrets to $Repo" -ForegroundColor Cyan

foreach ($name in $secrets.Keys) {
    gh secret set $name --repo $Repo --body $secrets[$name]
    if ($LASTEXITCODE -ne 0) { throw "Failed to set $name" }
    Write-Host "  set $name" -ForegroundColor Green
}

Write-Host ''
Write-Host "Done. Trigger a signed release with:" -ForegroundColor Cyan
Write-Host "  gh workflow run release.yml --repo $Repo -f tag=v1.0.4"

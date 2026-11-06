<#
.SYNOPSIS
    Points the documentation's download links and version markers at a Keysharp release.

.DESCRIPTION
    Every Keysharp release asset embeds its version (keysharp-0.0.0.16-win-x64.msi), so a direct
    download link written into the docs goes stale the moment a new release appears. This script
    rewrites those links, and the <!--ksver--> markers that display the version, in one pass.

    It is normally run by .github/workflows/update-version.yml, which discovers the current release
    and commits the result. Run it by hand to correct the docs without waiting for that.

    Only the Keysharp version is touched. The AutoHotkey compatibility target is unrelated, is
    maintained by hand, and is stated in the front page's lead paragraph and in the notice banner
    that static/content.js adds to every page.

.PARAMETER Version
    The release version, with or without a leading "v" (0.0.0.17 or v0.0.0.17).

.PARAMETER Check
    Report what would change and exit non-zero if anything would, without writing. Used by
    Test-Docs.ps1 to catch links and markers that have drifted apart.

.EXAMPLE
    ./scripts/Set-KeysharpVersion.ps1 0.0.0.17

.EXAMPLE
    ./scripts/Set-KeysharpVersion.ps1 -Check 0.0.0.17
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $Version,

    [switch] $Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$version = $Version.TrimStart('v', 'V')

if ($version -notmatch '^\d+(\.\d+){1,3}$') {
    throw "Version '$Version' is not a dotted numeric version such as 0.0.0.17."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$docsRoot = Join-Path $repoRoot 'docs'

# Both forms of the version appear in a release URL and have to move together:
#   .../releases/download/v0.0.0.16/keysharp-0.0.0.16-win-x64.msi
#   .../releases/download/v0.0.0.17/keysharp_0.0.0.17_amd64.deb
$patterns = @(
    @{ Name = 'release tag';      Find = '(?<=/releases/download/v)\d+(?:\.\d+){1,3}(?=/)' }
    # No leading slash is required, so filenames shown in tooltips are rewritten alongside the URLs.
    @{ Name = 'asset filename';   Find = '(?<=keysharp-)\d+(?:\.\d+){1,3}(?=-(?:win|linux|osx)-(?:x64|arm64)\.)' }
    @{ Name = 'Debian filename';  Find = '(?<=keysharp_)\d+(?:\.\d+){1,3}(?=_(?:amd64|arm64)\.deb)' }
    @{ Name = 'version marker';   Find = '(?<=<!--ksver-->)[^<]*(?=<!--/ksver-->)' }
)

$changed = [System.Collections.Generic.List[string]]::new()

foreach ($file in Get-ChildItem -Path $docsRoot -Filter '*.htm' -Recurse -File) {
    # Read and write bytes so the file's existing encoding, byte order mark and line endings survive
    # untouched; a text-mode round trip rewrites all three and buries the real change in the diff.
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, $(if ($hasBom) { 3 } else { 0 }), $bytes.Length - $(if ($hasBom) { 3 } else { 0 }))

    $updated = $text
    $hits = @()

    foreach ($pattern in $patterns) {
        $found = [regex]::Matches($updated, $pattern.Find)
        $stale = @($found | Where-Object { $_.Value -ne $version })
        if ($stale.Count -gt 0) { $hits += "$($stale.Count) $($pattern.Name)" }
        $updated = [regex]::Replace($updated, $pattern.Find, $version)
    }

    if ($updated -eq $text) { continue }

    $relative = $file.FullName.Substring($repoRoot.Length + 1)
    $changed.Add("$relative  ($($hits -join ', '))")

    if (-not $Check) {
        $payload = [System.Text.Encoding]::UTF8.GetBytes($updated)
        if ($hasBom) { $payload = [byte[]]@(0xEF, 0xBB, 0xBF) + $payload }
        [System.IO.File]::WriteAllBytes($file.FullName, $payload)
    }
}

if ($changed.Count -eq 0) {
    Write-Host "Documentation already targets Keysharp $version."
    exit 0
}

if ($Check) {
    Write-Host "Documentation does not target Keysharp ${version}:"
    $changed | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Run ./scripts/Set-KeysharpVersion.ps1 to correct it.'
    exit 1
}

Write-Host "Updated $($changed.Count) file(s) to Keysharp ${version}:"
$changed | ForEach-Object { Write-Host "  $_" }

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$docsRoot = Join-Path $repoRoot 'docs'
$errors = [Collections.Generic.List[string]]::new()

function Add-ValidationError {
    param([string]$Message)
    $errors.Add($Message)
}

$requiredFiles = @(
    'index.html',
    '404.html',
    'NOTICE.md',
    'docs/index.htm',
    'docs/Keysharp.htm',
    'docs/howto/Install.htm',
    'docs/Program.htm',
    'docs/static/keysharp_logo.png'
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath))) {
        Add-ValidationError "Required file is missing: $relativePath"
    }
}

$projectText = [IO.File]::ReadAllText((Join-Path $repoRoot 'Project.hhp'))
foreach ($relativePath in @(
        'docs\lib\ClipCursor.htm',
        'docs\lib\Highlight.htm')) {
    if (-not $projectText.Contains($relativePath)) {
        Add-ValidationError "CHM project is missing: $relativePath"
    }
}

$htmlFiles = Get-ChildItem -LiteralPath $docsRoot -Recurse -File |
    Where-Object { $_.Extension -in '.htm', '.html' }

foreach ($file in $htmlFiles) {
    $relativeFile = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/').Replace('\', '/')
    $html = [IO.File]::ReadAllText($file.FullName)

    if ($file.Name -notin 'AutoHotkeyChangeLog.htm', 'AutoHotkeyLicense.htm' -and
        $html -match '<title>[^<]*\|\s*AutoHotkey v2</title>') {
        Add-ValidationError "Inherited title suffix remains in $relativeFile"
    }

    $linkableHtml = [Text.RegularExpressions.Regex]::Replace(
        $html,
        '(?is)<(?:pre|code)\b.*?</(?:pre|code)>',
        ''
    )
    $attributeMatches = [Text.RegularExpressions.Regex]::Matches(
        $linkableHtml,
        '(?i)(?:href|src)\s*=\s*["'']([^"'']+)["'']'
    )
    foreach ($match in $attributeMatches) {
        $target = [Net.WebUtility]::HtmlDecode($match.Groups[1].Value).Trim()
        if (-not $target -or
            $target.StartsWith('#') -or
            $target.StartsWith('//') -or
            $target -match '^[a-z][a-z0-9+.-]*:' -or
            $target -match '[{}]') {
            continue
        }

        $pathPart = ($target -split '[?#]', 2)[0]
        if (-not $pathPart) {
            continue
        }

        try {
            $pathPart = [Uri]::UnescapeDataString($pathPart)
        }
        catch {
            Add-ValidationError "Invalid escaped local link in ${relativeFile}: $target"
            continue
        }

        $candidate = Join-Path $file.DirectoryName $pathPart
        if (-not (Test-Path -LiteralPath $candidate)) {
            Add-ValidationError "Broken local link in ${relativeFile}: $target"
        }
    }
}

$identityFiles = @(
    'docs/index.htm',
    'docs/static/content.js',
    'Project.hhp'
)
$forbiddenIdentity = @(
    'ahk_logo',
    'github.com/Lexikos/AutoHotkey_L-Docs',
    'Compiled file=AutoHotkey.chm',
    'Title=AutoHotkey v2 Help'
)
foreach ($relativePath in $identityFiles) {
    $text = [IO.File]::ReadAllText((Join-Path $repoRoot $relativePath))
    foreach ($forbidden in $forbiddenIdentity) {
        if ($text.Contains($forbidden)) {
            Add-ValidationError "Inherited shell identity '$forbidden' remains in $relativePath"
        }
    }
}

# The download links embed a release version, and so do the <!--ksver--> markers that display it.
# They are rewritten together by Set-KeysharpVersion.ps1, so disagreement means an edit by hand went
# only part of the way - which would leave the site advertising one version and serving another.
$downloadVersions = [System.Collections.Generic.HashSet[string]]::new()
foreach ($file in $htmlFiles) {
    $text = [IO.File]::ReadAllText($file.FullName)
    foreach ($pattern in @(
            '/releases/download/v(\d+(?:\.\d+){1,3})/',
            'keysharp-(\d+(?:\.\d+){1,3})-(?:win|linux|osx)-(?:x64|arm64)\.',
            'keysharp_(\d+(?:\.\d+){1,3})_(?:amd64|arm64)\.deb',
            '<!--ksver-->([^<]*)<!--/ksver-->')) {
        foreach ($match in [regex]::Matches($text, $pattern)) {
            [void]$downloadVersions.Add($match.Groups[1].Value)
        }
    }
}
if ($downloadVersions.Count -gt 1) {
    $list = ($downloadVersions | Sort-Object) -join ', '
    Add-ValidationError "Download links and version markers disagree ($list). Run ./scripts/Set-KeysharpVersion.ps1 <version>."
}

if ($errors.Count) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Documentation validation failed with $($errors.Count) error(s)."
}

$versionNote = if ($downloadVersions.Count -eq 1) { " Downloads target Keysharp $($downloadVersions | Select-Object -First 1)." } else { '' }
Write-Host "Validated $($htmlFiles.Count) HTML files; required files, local links, titles, and shell identity are consistent.$versionNote"

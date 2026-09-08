# Regenera las fichas de la raíz desde config/*.template.md y versions.json.
# README.md = descarga pública. README_developers.md = proceso de build.
# No introduce una segunda fuente de versiones: badges, tablas y nombres
# salen del manifiesto. El texto vive en las plantillas.
[CmdletBinding()]
param(
    [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$configPath = Join-Path $RepoRoot 'config\versions.json'
$templateDir = Join-Path $RepoRoot 'config'

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "No se encontro config/versions.json en $RepoRoot"
}

$required = @(
    'productName',
    'productVersion',
    'sparkVersion',
    'pysparkVersion',
    'hadoopWinutilsVersion',
    'javaMajorVersion',
    'pythonVersion',
    'ipykernelVersion'
)

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($name in $required) {
    if (-not $config.PSObject.Properties[$name] -or [string]::IsNullOrWhiteSpace([string]$config.$name)) {
        throw "Falta $name en config/versions.json"
    }
}

if (-not $config.PSObject.Properties['distribution']) {
    throw 'Falta distribution en config/versions.json'
}

$dist = $config.distribution
foreach ($name in @('repository', 'platform', 'defaultInstallDir')) {
    if (-not $dist.PSObject.Properties[$name] -or [string]::IsNullOrWhiteSpace([string]$dist.$name)) {
        throw "Falta distribution.$name en config/versions.json"
    }
}

$product = [string]$config.productName
$version = [string]$config.productVersion
$repo = [string]$dist.repository.TrimEnd('/')
$platform = [string]$dist.platform
$platformBadgeMessage = [uri]::EscapeDataString(($platform -replace '^Windows\s+', ''))

$values = [ordered]@{
    productName           = $product
    productVersion        = $version
    sparkVersion          = [string]$config.sparkVersion
    pysparkVersion        = [string]$config.pysparkVersion
    hadoopWinutilsVersion = [string]$config.hadoopWinutilsVersion
    javaMajorVersion      = [string]$config.javaMajorVersion
    pythonVersion         = [string]$config.pythonVersion
    ipykernelVersion      = [string]$config.ipykernelVersion
    repository            = $repo
    releasesUrl           = "$repo/releases"
    latestUrl             = "$repo/releases/latest"
    platform              = $platform
    platformBadgeMessage  = $platformBadgeMessage
    defaultInstallDir     = [string]$dist.defaultInstallDir
    setupGlob             = '{0}-Setup-*.exe' -f $product
    setupName             = '{0}-Setup-{1}.exe' -f $product, $version
    homeVar               = '{0}_HOME' -f ($product -replace '[^A-Za-z]', '').ToUpperInvariant()
    pythonShortcut        = 'Python ({0})' -f $product
}

$templates = Get-ChildItem -LiteralPath $templateDir -Filter '*.template.md' -File
if (-not $templates) {
    throw "No hay plantillas *.template.md en $templateDir"
}

foreach ($template in $templates) {
    $stem = $template.BaseName -replace '\.template$', ''
    $outputPath = Join-Path $RepoRoot "$stem.md"
    $text = [System.IO.File]::ReadAllText($template.FullName, $utf8NoBom)
    foreach ($key in $values.Keys) {
        $text = $text.Replace('{{' + $key + '}}', [string]$values[$key])
    }
    $unresolved = [regex]::Matches($text, '\{\{[A-Za-z][A-Za-z0-9]*\}\}')
    if ($unresolved.Count -gt 0) {
        throw "Quedan placeholders sin resolver en $($template.Name): $($unresolved[0].Value)"
    }
    [System.IO.File]::WriteAllText($outputPath, $text.TrimEnd() + [Environment]::NewLine, $utf8NoBom)
    Write-Host "Escrito $outputPath"
}

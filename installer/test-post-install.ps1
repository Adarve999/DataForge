# Prueba la post-instalacion sin recompilar el .exe
param(
    [Parameter(Mandatory)][string]$InstallRoot
)

$installerDir = $PSScriptRoot
$configPath = Join-Path $InstallRoot 'config\versions.json'
if (-not (Test-Path $configPath)) {
    $configPath = Join-Path (Split-Path -Parent $installerDir) 'config\versions.json'
}

& (Join-Path $installerDir 'scripts\post-install.ps1') `
    -InstallRoot $InstallRoot `
    -ConfigPath $configPath

# Script principal de post-instalacion (ejecutado por Inno Setup)
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [string]$ConfigPath = '',
    [string]$PidFile = '',
    [string]$CancelFile = '',
    [string]$ProgressFile = '',
    [string]$ExitCodeFile = '',
    [string]$UiLanguage = 'spanish'
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'common.ps1')

$script:InstallCancelFile = $CancelFile
$script:InstallProgressFile = $ProgressFile
$script:InstallUiLanguage = $UiLanguage
$env:DATAFORGE_INSTALL_CANCEL_FILE = $CancelFile
$env:DATAFORGE_INSTALL_PROGRESS_FILE = $ProgressFile
$env:DATAFORGE_INSTALL_UI_LANGUAGE = $UiLanguage

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $InstallRoot 'config\versions.json'
}

$logDir = Join-Path $InstallRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir 'install.log'

if ($PidFile) {
    $pidDir = Split-Path -Parent $PidFile
    if ($pidDir) {
        New-Item -ItemType Directory -Force -Path $pidDir | Out-Null
    }
    Set-SharedFileContent -Path $PidFile -Text ([string]$PID)
}

$config = Get-VersionsConfig -ConfigPath $ConfigPath
$paths = Get-EnvPaths -InstallRoot $InstallRoot

$env:PYTHONUNBUFFERED = '1'
$env:PYTHONIOENCODING = 'utf-8'

$exitCode = 1
try {
    Write-InstallProgress -Percent 2 -Status (Get-InstallUiText 'Starting') -LogFile $logFile
    Write-InstallLog -Message "=== $($config.productName) post-instalacion ===" -LogFile $logFile
    Write-InstallLog -Message "Directorio de instalacion: $InstallRoot" -LogFile $logFile
    Write-InstallLog -Message "Versiones: Java $($config.javaMajorVersion), Spark $($config.sparkVersion), PySpark $($config.pysparkVersion), ipykernel $($config.ipykernelVersion), Python $($config.pythonVersion)." -LogFile $logFile

    Test-InstallCancelled

    Write-InstallProgress -Percent 20 -Status (Get-InstallUiText 'CheckingPython') -LogFile $logFile
    if (-not (Test-Path -LiteralPath $paths.PythonExe)) {
        throw "No se encontro el runtime Python privado en $($paths.PythonExe)"
    }
    Write-InstallLog -Message "Runtime Python privado: $($paths.PythonExe)" -LogFile $logFile

    Test-InstallCancelled

    & (Join-Path $scriptDir 'setup-env.ps1') `
        -InstallRoot $InstallRoot `
        -ConfigPath $ConfigPath `
        -LogFile $logFile

    Test-InstallCancelled

    & (Join-Path $scriptDir 'verify-install.ps1') `
        -InstallRoot $InstallRoot `
        -ConfigPath $ConfigPath `
        -LogFile $logFile

    Write-InstallProgress -Percent 100 -Status (Get-InstallUiText 'Success') -LogFile $logFile
    $exitCode = 0
} catch {
    $message = [string]$_.Exception.Message
    if ($message -eq 'INSTALL_CANCELLED') {
        Write-InstallLog -Message (Get-InstallUiText 'Cancelled') -LogFile $logFile
        $exitCode = 1602
    } else {
        Write-InstallLog -Message ((Get-InstallUiText 'FailedPrefix') + $message) -LogFile $logFile
        $exitCode = 1
    }
} finally {
    if ($ExitCodeFile) {
        $exitDir = Split-Path -Parent $ExitCodeFile
        if ($exitDir) {
            New-Item -ItemType Directory -Force -Path $exitDir | Out-Null
        }
        Set-SharedFileContent -Path $ExitCodeFile -Text ([string]$exitCode)
    }
}

exit $exitCode

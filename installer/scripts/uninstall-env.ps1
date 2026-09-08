# Limpia variables de entorno de usuario al desinstalar
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [string]$LogFile = ''
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'common.ps1')

if (-not $LogFile) {
    $LogFile = Join-Path ([IO.Path]::GetTempPath()) 'DataForge-uninstall.log'
}

$logDir = Split-Path -Parent $LogFile
if ($logDir) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

try {
    $paths = Get-EnvPaths -InstallRoot $InstallRoot

    Write-InstallLog -Message '=== DataForge desinstalacion ===' -LogFile $LogFile
    Write-InstallLog -Message "Directorio de instalacion: $InstallRoot" -LogFile $LogFile

    $configPath = Join-Path $InstallRoot 'config\versions.json'
    $config = $null
    if (Test-Path -LiteralPath $configPath) {
        $config = Get-VersionsConfig -ConfigPath $configPath
    }

    Remove-StaleInstallPathEntries -InstallRoot $InstallRoot -Config $config -LogFile $LogFile

    $envNames = @(
        (Get-InstallHomeVariableName -Config $config)
        'JAVA_HOME'
        'SPARK_HOME'
        'HADOOP_HOME'
        'PYSPARK_PYTHON'
        'PYSPARK_DRIVER_PYTHON'
    )

    foreach ($name in @($envNames | Select-Object -Unique)) {
        Write-InstallLog -Message "Eliminando variable de entorno: $name" -LogFile $LogFile
        [Environment]::SetEnvironmentVariable($name, $null, 'User')
        Remove-ItemProperty -Path 'HKCU:\Environment' -Name $name -ErrorAction SilentlyContinue
    }

    Unregister-PrivatePythonDiscovery -Paths $paths -Config $config -LogFile $LogFile

    if (Test-Path -LiteralPath $paths.PythonHome) {
        Write-InstallLog -Message "Eliminando directorio de runtime: $($paths.PythonHome)" -LogFile $LogFile
        Remove-Item -LiteralPath $paths.PythonHome -Recurse -Force -ErrorAction Stop
        Write-InstallLog -Message "Eliminado: $($paths.PythonHome)" -LogFile $LogFile
    }

    Write-InstallLog -Message 'Variables de entorno y recursos privados preparados para eliminar.' -LogFile $LogFile
    Write-InstallLog -Message 'El desinstalador eliminara tambien las carpetas restantes, incluidos spark y logs.' -LogFile $LogFile
    exit 0
} catch {
    Write-InstallLog -Message "Limpieza de desinstalacion fallida: $($_.Exception.Message)" -LogFile $LogFile
    exit 1
}

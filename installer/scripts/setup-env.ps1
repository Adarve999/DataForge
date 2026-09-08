# Configura variables de entorno de usuario para DataForge
param(
    [Parameter(Mandatory)][string]$InstallRoot,
    [string]$ConfigPath = '',
    [string]$LogFile
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'common.ps1')

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $InstallRoot 'config\versions.json'
}

$config = Get-VersionsConfig -ConfigPath $ConfigPath
$paths = Get-EnvPaths -InstallRoot $InstallRoot

Write-InstallProgress -Percent 40 -Status (Get-InstallUiText 'ConfiguringEnvVars') -LogFile $LogFile

Remove-StaleInstallPathEntries -InstallRoot $InstallRoot -Config $config -LogFile $LogFile

$homeVar = Get-InstallHomeVariableName -Config $config
Set-UserEnvironmentVariable -Name $homeVar -Value $paths.InstallRoot
Set-UserEnvironmentVariable -Name 'JAVA_HOME' -Value $paths.JavaHome
Set-UserEnvironmentVariable -Name 'SPARK_HOME' -Value $paths.SparkHome
Set-UserEnvironmentVariable -Name 'HADOOP_HOME' -Value $paths.HadoopHome
Set-UserEnvironmentVariable -Name 'PYSPARK_PYTHON' -Value $paths.PythonExe
Set-UserEnvironmentVariable -Name 'PYSPARK_DRIVER_PYTHON' -Value $paths.PythonExe

foreach ($entry in (Get-EnvironmentPathEntries -Paths $paths -Config $config)) {
    if (Test-Path -LiteralPath $entry.ResolvedPath) {
        # Persistir rutas directas evita que cmd.exe conserve referencias
        # anidadas %VARIABLE% sin expandir durante la busqueda de comandos.
        Add-UserPathEntry -PathEntry $entry.PathValue
    }
}

Register-PrivatePythonDiscovery -Paths $paths -Config $config -LogFile $LogFile

# Actualizar sesion actual (util si se ejecuta manualmente)
Set-Item -LiteralPath "Env:$homeVar" -Value $paths.InstallRoot
$env:JAVA_HOME = $paths.JavaHome
$env:SPARK_HOME = $paths.SparkHome
$env:HADOOP_HOME = $paths.HadoopHome
$env:PYSPARK_PYTHON = $paths.PythonExe
$env:PYSPARK_DRIVER_PYTHON = $paths.PythonExe

Write-InstallProgress -Percent 70 -Status (Get-InstallUiText 'EnvVarsDone') -LogFile $LogFile

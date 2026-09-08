# Verifica que la instalacion de DataForge funciona
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

function Test-CommandExists {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) {
        return "$Label no encontrado: $Path"
    }
    return $null
}

$errors = @(
    Test-CommandExists -Path (Join-Path $paths.JavaBin 'java.exe') -Label 'Java'
    Test-CommandExists -Path (Join-Path $paths.HadoopBin 'winutils.exe') -Label 'winutils'
    Test-CommandExists -Path (Join-Path $paths.SparkBin 'spark-submit.cmd') -Label 'Spark'
    Test-CommandExists -Path $paths.PythonExe -Label 'Python'
) | Where-Object { $_ }
$errors = @($errors)

$errors += @(Test-PrivatePythonDiscovery -Paths $paths -Config $config)
$errors = @($errors | Where-Object { $_ })

if ($errors.Count -gt 0) {
    foreach ($err in $errors) {
        Write-InstallLog -Message "ERROR: $err" -LogFile $LogFile
    }
    throw "Verificacion fallida. Revisa el log de instalacion."
}

Write-InstallProgress -Percent 80 -Status (Get-InstallUiText 'VerifyingInstall') -LogFile $LogFile
Write-InstallLog -Message "Comprobando java -version..." -LogFile $LogFile
$java = Invoke-CapturedOutput -FilePath (Join-Path $paths.JavaBin 'java.exe') -ArgumentList @('-version')
if ($java.Output.Trim()) {
    Write-InstallLog -Message $java.Output.Trim() -LogFile $LogFile
}
if ($java.ExitCode -ne 0) {
    throw "java -version fallo (exit $($java.ExitCode))"
}

Write-InstallLog -Message "Comprobando import de ipykernel..." -LogFile $LogFile
$ipyCode = @"
import ipykernel
print('ipykernel', ipykernel.__version__)
print('OK_IPYKERNEL')
"@
$ipy = Invoke-CapturedOutput -FilePath $paths.PythonExe -ArgumentList @('-s', '-c', $ipyCode)
if ($ipy.Output.Trim()) {
    Write-InstallLog -Message $ipy.Output.Trim() -LogFile $LogFile
}
if (($ipy.ExitCode -ne 0) -or ($ipy.Output -notmatch '(?m)^OK_IPYKERNEL\s*$')) {
    throw "La verificacion de ipykernel no devolvio OK_IPYKERNEL."
}
if ($ipy.Output -notmatch [regex]::Escape([string]$config.ipykernelVersion)) {
    throw "La version de ipykernel no coincide con config/versions.json."
}

Write-InstallLog -Message "Comprobando import de pyspark..." -LogFile $LogFile
$pyCode = @"
import pyspark
from pyspark.sql import SparkSession
print('pyspark', pyspark.__version__)
spark = SparkSession.builder.master('local[*]').appName('dataforge-verify').getOrCreate()
print('spark_version', spark.version)
spark.stop()
print('OK')
"@

$env:JAVA_HOME = $paths.JavaHome
$env:SPARK_HOME = $paths.SparkHome
$env:HADOOP_HOME = $paths.HadoopHome
$env:PYSPARK_PYTHON = $paths.PythonExe
$env:PYSPARK_DRIVER_PYTHON = $paths.PythonExe

$pyFile = Join-Path $env:TEMP ('psb-verify-spark-' + [guid]::NewGuid().ToString('N') + '.py')
try {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($pyFile, $pyCode, $utf8)
    Invoke-LoggedProcess -FilePath $paths.PythonExe -ArgumentList @('-s', $pyFile) `
        -LogFile $LogFile -TimeoutSeconds 300
} finally {
    Remove-Item -LiteralPath $pyFile -Force -ErrorAction SilentlyContinue
}

Write-InstallProgress -Percent 98 -Status (Get-InstallUiText 'VerifyDone') -LogFile $LogFile

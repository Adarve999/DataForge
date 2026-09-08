# Shared helpers for DataForge installer scripts
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:DATAFORGE_INSTALL_CANCEL_FILE) {
    $script:InstallCancelFile = $env:DATAFORGE_INSTALL_CANCEL_FILE
} elseif (-not (Get-Variable -Scope Script -Name InstallCancelFile -ErrorAction SilentlyContinue)) {
    $script:InstallCancelFile = ''
}
if ($env:DATAFORGE_INSTALL_PROGRESS_FILE) {
    $script:InstallProgressFile = $env:DATAFORGE_INSTALL_PROGRESS_FILE
} elseif (-not (Get-Variable -Scope Script -Name InstallProgressFile -ErrorAction SilentlyContinue)) {
    $script:InstallProgressFile = ''
}
if ($env:DATAFORGE_INSTALL_UI_LANGUAGE) {
    $script:InstallUiLanguage = $env:DATAFORGE_INSTALL_UI_LANGUAGE
} elseif (-not (Get-Variable -Scope Script -Name InstallUiLanguage -ErrorAction SilentlyContinue)) {
    $script:InstallUiLanguage = 'spanish'
}

function Get-LegacyPythonDiscoveryCompanyNames {
    # Empresa PEP 514 y kernelspec publicados antes del cambio de nombre.
    @('PySparkBuilder')
}

function Get-InstallHomeVariableName {
    param($Config)

    $product = Get-PythonDiscoveryCompanyName -Config $Config
    $token = $product.ToUpperInvariant() -replace '[^A-Z0-9]', ''
    if (-not $token) {
        throw 'productName no puede derivar una variable de entorno'
    }
    return "${token}_HOME"
}

function Get-KnownInstallHomeVariableNames {
    param($Config)

    $names = @(Get-InstallHomeVariableName -Config $Config)
    return @($names | Where-Object { $_ } | Select-Object -Unique)
}

function Get-InstallRoot {
    param(
        [string]$Override,
        $Config
    )
    if ($Override) { return $Override.TrimEnd('\') }
    foreach ($name in (Get-KnownInstallHomeVariableNames -Config $Config)) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not $value) {
            $value = [Environment]::GetEnvironmentVariable($name, 'User')
        }
        if ($value) {
            return $value.TrimEnd('\')
        }
    }
    return $null
}

function Get-VersionsConfig {
    param([string]$ConfigPath)
    if (-not (Test-Path $ConfigPath)) {
        throw "No se encontro config de versiones: $ConfigPath"
    }
    return Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

function Get-EnvPaths {
    param(
        [Parameter(Mandatory)][string]$InstallRoot
    )

    $pythonHome = Join-Path $InstallRoot 'python'

    [ordered]@{
        InstallRoot          = $InstallRoot
        JavaHome             = Join-Path $InstallRoot 'java'
        SparkHome            = Join-Path $InstallRoot 'spark'
        HadoopHome           = Join-Path $InstallRoot 'hadoop'
        PythonHome           = $pythonHome
        PythonScripts        = Join-Path $pythonHome 'Scripts'
        PythonExe            = Join-Path $pythonHome 'python.exe'
        PythonWExe           = Join-Path $pythonHome 'pythonw.exe'
        SparkBin             = Join-Path $InstallRoot 'spark\bin'
        HadoopBin            = Join-Path $InstallRoot 'hadoop\bin'
        JavaBin              = Join-Path $InstallRoot 'java\bin'
    }
}

function Get-EnvironmentPathEntries {
    param(
        [Parameter(Mandatory)]$Paths,
        $Config
    )

    $homeVar = Get-InstallHomeVariableName -Config $Config

    # Persist direct paths in the user PATH. Nested %VARIABLE% references can
    # remain literal during command lookup in cmd.exe.
    @(
        [pscustomobject]@{
            ResolvedPath      = $Paths.JavaBin
            PathValue         = $Paths.JavaBin
            LegacyPathValue   = '%JAVA_HOME%\bin'
        }
        [pscustomobject]@{
            ResolvedPath      = $Paths.SparkBin
            PathValue         = $Paths.SparkBin
            LegacyPathValue   = '%SPARK_HOME%\bin'
        }
        [pscustomobject]@{
            ResolvedPath      = $Paths.HadoopBin
            PathValue         = $Paths.HadoopBin
            LegacyPathValue   = '%HADOOP_HOME%\bin'
        }
        [pscustomobject]@{
            ResolvedPath      = $Paths.PythonHome
            PathValue         = $Paths.PythonHome
            LegacyPathValue   = "%${homeVar}%\python"
        }
    )
}

function Set-UserEnvironmentVariable {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')

    $userEnvKey = 'HKCU:\Environment'
    Set-ItemProperty -Path $userEnvKey -Name $Name -Value $Value -Type ExpandString
}

function Add-UserPathEntry {
    param(
        [Parameter(Mandatory)][string]$PathEntry
    )

    $normalized = (($PathEntry.Trim() -replace '/', '\') -replace '\\+$', '')
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($current) {
        $parts = $current -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    if ($parts | Where-Object {
            ((($_ -replace '/', '\') -replace '\\+$', '').ToLowerInvariant()) -eq $normalized.ToLowerInvariant()
        }) {
        return
    }

    $parts = $parts + @($normalized)
    $newPath = ($parts -join ';')
    Set-UserEnvironmentVariable -Name 'Path' -Value $newPath
}

function Remove-UserPathEntry {
    param(
        [Parameter(Mandatory)][string]$PathEntry
    )

    $normalized = (($PathEntry.Trim() -replace '/', '\') -replace '\\+$', '').ToLowerInvariant()
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) { return }

    $parts = $current -split ';' |
        ForEach-Object { $_.Trim() } |
        Where-Object {
            $_ -and (((($_ -replace '/', '\') -replace '\\+$', '').ToLowerInvariant()) -ne $normalized)
        }

    Set-UserEnvironmentVariable -Name 'Path' -Value ($parts -join ';')
}

function Get-LegacyUserPathEntries {
    param($Config)

    $entries = @(
        '%JAVA_HOME%\bin'
        '%SPARK_HOME%\bin'
        '%HADOOP_HOME%\bin'
    )
    foreach ($homeName in (Get-KnownInstallHomeVariableNames -Config $Config)) {
        $entries += "%${homeName}%\python"
    }
    return @($entries | Select-Object -Unique)
}

function Test-PathIsUnderRoot {
    param(
        [Parameter(Mandatory)][string]$PathEntry,
        [Parameter(Mandatory)][string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($PathEntry) -or ($PathEntry -match '%')) {
        return $false
    }

    $normalizedEntry = Get-NormalizedFsPath $PathEntry
    $normalizedRoot = Get-NormalizedFsPath $Root
    if (-not $normalizedEntry -or -not $normalizedRoot) {
        return $false
    }

    return ($normalizedEntry -eq $normalizedRoot) -or
        $normalizedEntry.StartsWith($normalizedRoot + '\')
}

function Remove-UserPathEntriesUnderRoot {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$LogFile
    )

    $normalizedRoot = Get-NormalizedFsPath $Root
    if (-not $normalizedRoot) {
        return
    }

    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) {
        return
    }

    $kept = @()
    $changed = $false
    foreach ($part in ($current -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        if (Test-PathIsUnderRoot -PathEntry $part -Root $Root) {
            $changed = $true
            Write-InstallLog -Message "Eliminando entrada de PATH: $part" -LogFile $LogFile
            continue
        }
        $kept += $part
    }

    if ($changed) {
        Set-UserEnvironmentVariable -Name 'Path' -Value ($kept -join ';')
    }
}

function Remove-StaleInstallPathEntries {
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        $Config,
        [string]$LogFile
    )

    $roots = @($InstallRoot)
    foreach ($name in (Get-KnownInstallHomeVariableNames -Config $Config)) {
        $previousHome = [Environment]::GetEnvironmentVariable($name, 'User')
        if (-not $previousHome) {
            continue
        }
        $previousNorm = Get-NormalizedFsPath $previousHome
        $installNorm = Get-NormalizedFsPath $InstallRoot
        if ($previousNorm -and ($previousNorm -ne $installNorm)) {
            Write-InstallLog -Message ("$(Get-InstallUiText 'RemovingStalePath') $previousHome") -LogFile $LogFile
            $roots += $previousHome
        }
    }

    $seen = @{}
    foreach ($root in $roots) {
        $key = Get-NormalizedFsPath $root
        if (-not $key -or $seen.ContainsKey($key)) {
            continue
        }
        $seen[$key] = $true
        Remove-UserPathEntriesUnderRoot -Root $root -LogFile $LogFile
    }

    foreach ($legacy in (Get-LegacyUserPathEntries -Config $Config)) {
        Remove-UserPathEntry -PathEntry $legacy
    }
}

function Get-PythonDiscoveryCompanyName {
    param($Config)

    if ($Config -and $Config.PSObject.Properties['productName'] -and $Config.productName) {
        return [string]$Config.productName
    }
    return 'DataForge'
}

function Get-PythonDiscoveryKernelName {
    param($Config)

    return (Get-PythonDiscoveryCompanyName -Config $Config).ToLowerInvariant()
}

function Get-PythonShortVersion {
    param([Parameter(Mandatory)][string]$PythonVersion)

    $parts = @($PythonVersion -split '\.')
    if ($parts.Count -lt 2) {
        throw "pythonVersion debe tener al menos major.minor: $PythonVersion"
    }
    return "$($parts[0]).$($parts[1])"
}

function Get-NormalizedFsPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $s = $Path.Trim().Trim('"')
    try {
        $s = [IO.Path]::GetFullPath($s)
    } catch {
    }
    return ($s -replace '\\+$', '').ToLowerInvariant()
}

function Get-UserJupyterKernelDir {
    param([Parameter(Mandatory)][string]$KernelName)

    return Join-Path $env:APPDATA "jupyter\kernels\$KernelName"
}

function Get-Pep514CompanyKeyPath {
    param($Config)

    return "HKCU:\Software\Python\$(Get-PythonDiscoveryCompanyName -Config $Config)"
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][allowemptystring()][string]$Text
    )

    Ensure-ParentDirectory -Path $Path
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Get-PrivatePythonKernelJson {
    param(
        [Parameter(Mandatory)][string]$PythonExe,
        [Parameter(Mandatory)][string]$DisplayName
    )

    $spec = [ordered]@{
        argv                     = @($PythonExe, '-m', 'ipykernel_launcher', '-f', '{connection_file}')
        display_name             = $DisplayName
        language                 = 'python'
        metadata                 = [ordered]@{
            debugger              = $true
            supported_encryption  = 'curve'
        }
        kernel_protocol_version  = '5.5'
    }
    return (($spec | ConvertTo-Json -Depth 5) + [Environment]::NewLine)
}

function Set-PrivatePythonKernelSpec {
    param(
        [Parameter(Mandatory)][string]$DestinationDir,
        [Parameter(Mandatory)][string]$Json,
        [string]$LogoSourceDir,
        [string]$LogFile
    )

    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    Write-Utf8NoBomFile -Path (Join-Path $DestinationDir 'kernel.json') -Text $Json

    if (-not $LogoSourceDir -or -not (Test-Path -LiteralPath $LogoSourceDir)) {
        return
    }

    foreach ($logo in @('logo-32x32.png', 'logo-64x64.png', 'logo-svg.svg')) {
        $source = Join-Path $LogoSourceDir $logo
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $DestinationDir $logo) -Force
        }
    }
}

function Register-PrivatePythonDiscovery {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)]$Config,
        [string]$LogFile
    )

    if (-not (Test-Path -LiteralPath $Paths.PythonExe)) {
        throw "No se encontro python.exe para registrar el descubrimiento: $($Paths.PythonExe)"
    }

    $company = Get-PythonDiscoveryCompanyName -Config $Config
    $shortVersion = Get-PythonShortVersion -PythonVersion ([string]$Config.pythonVersion)
    $displayName = "Python $($Config.pythonVersion) ($company)"
    $kernelDisplayName = "Python ($company)"
    $companyKey = Get-Pep514CompanyKeyPath -Config $Config
    $pythonHomeSlash = ($Paths.PythonHome.TrimEnd('\')) + '\'
    $libPath = (Join-Path $Paths.PythonHome 'Lib') + '\'
    $dllPath = (Join-Path $Paths.PythonHome 'DLLs') + '\'

    Write-InstallLog -Message "Registrando CPython privado para VS Code (PEP 514, $company\$shortVersion)..." -LogFile $LogFile
    Unregister-LegacyPythonDiscovery -Config $Config -LogFile $LogFile

    if (Test-Path -LiteralPath $companyKey) {
        Remove-Item -LiteralPath $companyKey -Recurse -Force
    }

    $tagKey = Join-Path $companyKey $shortVersion
    $installKey = Join-Path $tagKey 'InstallPath'
    $pythonPathKey = Join-Path $tagKey 'PythonPath'
    New-Item -Path $installKey -Force | Out-Null
    New-Item -Path $pythonPathKey -Force | Out-Null

    Set-ItemProperty -LiteralPath $companyKey -Name 'DisplayName' -Value $company
    Set-ItemProperty -LiteralPath $tagKey -Name 'DisplayName' -Value $displayName
    Set-ItemProperty -LiteralPath $tagKey -Name 'Version' -Value ([string]$Config.pythonVersion)
    Set-ItemProperty -LiteralPath $tagKey -Name 'SysVersion' -Value $shortVersion
    Set-ItemProperty -LiteralPath $tagKey -Name 'SysArchitecture' -Value '64bit'
    Set-ItemProperty -LiteralPath $installKey -Name '(default)' -Value $pythonHomeSlash
    Set-ItemProperty -LiteralPath $installKey -Name 'ExecutablePath' -Value $Paths.PythonExe
    if (Test-Path -LiteralPath $Paths.PythonWExe) {
        Set-ItemProperty -LiteralPath $installKey -Name 'WindowedExecutablePath' -Value $Paths.PythonWExe
    }
    Set-ItemProperty -LiteralPath $pythonPathKey -Name '(default)' -Value ($libPath + ';' + $dllPath)

    $json = Get-PrivatePythonKernelJson -PythonExe $Paths.PythonExe -DisplayName $kernelDisplayName
    $prefixKernelDir = Join-Path $Paths.PythonHome 'share\jupyter\kernels\python3'
    $userKernelDir = Get-UserJupyterKernelDir -KernelName (Get-PythonDiscoveryKernelName -Config $Config)

    Write-InstallLog -Message "Escribiendo kernelspec con ruta absoluta: $userKernelDir" -LogFile $LogFile
    Set-PrivatePythonKernelSpec -DestinationDir $prefixKernelDir -Json $json -LogFile $LogFile
    Set-PrivatePythonKernelSpec `
        -DestinationDir $userKernelDir `
        -Json $json `
        -LogoSourceDir $prefixKernelDir `
        -LogFile $LogFile
}

function Unregister-PrivatePythonDiscovery {
    param(
        [Parameter(Mandatory)]$Paths,
        $Config,
        [string]$LogFile
    )

    $companyKey = Get-Pep514CompanyKeyPath -Config $Config
    if (Test-Path -LiteralPath $companyKey) {
        Write-InstallLog -Message "Eliminando registro PEP 514: $companyKey" -LogFile $LogFile
        Remove-Item -LiteralPath $companyKey -Recurse -Force
    }

    $userKernelDir = Get-UserJupyterKernelDir -KernelName (Get-PythonDiscoveryKernelName -Config $Config)
    if (Test-Path -LiteralPath $userKernelDir) {
        Write-InstallLog -Message "Eliminando kernelspec de usuario: $userKernelDir" -LogFile $LogFile
        Remove-Item -LiteralPath $userKernelDir -Recurse -Force
    }

    Unregister-LegacyPythonDiscovery -Config $Config -LogFile $LogFile
}

function Unregister-LegacyPythonDiscovery {
    param(
        $Config,
        [string]$LogFile
    )

    $current = Get-PythonDiscoveryCompanyName -Config $Config
    foreach ($legacy in (Get-LegacyPythonDiscoveryCompanyNames)) {
        if ($legacy -ieq $current) {
            continue
        }

        $companyKey = "HKCU:\Software\Python\$legacy"
        if (Test-Path -LiteralPath $companyKey) {
            Write-InstallLog -Message "Eliminando registro PEP 514 heredado: $companyKey" -LogFile $LogFile
            Remove-Item -LiteralPath $companyKey -Recurse -Force
        }

        $userKernelDir = Get-UserJupyterKernelDir -KernelName $legacy.ToLowerInvariant()
        if (Test-Path -LiteralPath $userKernelDir) {
            Write-InstallLog -Message "Eliminando kernelspec heredado: $userKernelDir" -LogFile $LogFile
            Remove-Item -LiteralPath $userKernelDir -Recurse -Force
        }
    }
}

function Test-PrivatePythonDiscovery {
    param(
        [Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)]$Config
    )

    $company = Get-PythonDiscoveryCompanyName -Config $Config
    $shortVersion = Get-PythonShortVersion -PythonVersion ([string]$Config.pythonVersion)
    $installKey = Join-Path (Get-Pep514CompanyKeyPath -Config $Config) "$shortVersion\InstallPath"
    $expected = Get-NormalizedFsPath $Paths.PythonExe
    $errors = @()

    if (-not (Test-Path -LiteralPath $installKey)) {
        $errors += "No esta el registro PEP 514 de $company ($installKey)."
    } else {
        $props = Get-ItemProperty -LiteralPath $installKey
        $registeredExe = ''
        if ($props.PSObject.Properties['ExecutablePath']) {
            $registeredExe = [string]$props.ExecutablePath
        }
        $registered = Get-NormalizedFsPath $registeredExe
        if ($registered -ne $expected) {
            $errors += "PEP 514 ExecutablePath no apunta al CPython privado ($registered)."
        }
    }

    $userKernelJson = Join-Path (Get-UserJupyterKernelDir -KernelName (Get-PythonDiscoveryKernelName -Config $Config)) 'kernel.json'
    if (-not (Test-Path -LiteralPath $userKernelJson)) {
        $errors += "No esta el kernelspec de usuario: $userKernelJson"
    } else {
        $raw = Get-Content -LiteralPath $userKernelJson -Raw
        if ($raw -notmatch [regex]::Escape($Paths.PythonExe.Replace('\', '\\')) -and
            $raw -notmatch [regex]::Escape($Paths.PythonExe)) {
            $errors += "El kernelspec de usuario no apunta a $($Paths.PythonExe)."
        }
    }

    return @($errors)
}

function Get-InstallUiText {
    param([Parameter(Mandatory)][string]$Key)

    $lang = $script:InstallUiLanguage
    if ([string]::IsNullOrWhiteSpace($lang)) {
        $lang = 'spanish'
    }
    $lang = $lang.ToLowerInvariant()

    $text = @{
        spanish = @{
            Starting                 = 'Iniciando la configuracion del entorno...'
            CheckingPython           = 'Comprobando el runtime Python privado...'
            ConfiguringEnvVars       = 'Configurando variables de entorno de usuario...'
            RemovingStalePath        = 'Eliminando rutas de una instalacion anterior...'
            EnvVarsDone              = 'Variables de entorno configuradas.'
            VerifyingInstall         = 'Comprobando que Java, Spark, PySpark e ipykernel funcionan...'
            VerifyDone               = 'Verificacion completada correctamente.'
            Success                  = 'Post-instalacion finalizada con exito.'
            Cancelled                = 'Instalacion cancelada por el usuario.'
            FailedPrefix             = 'Post-instalacion fallida: '
            CommandFailed            = 'El comando fallo'
            Running                  = 'Ejecutando'
            RemovingTempFiles        = 'Eliminando archivos temporales (installer, scripts, logs)...'
            ReadyForUse              = 'Instalacion lista para uso.'
        }
        english = @{
            Starting                 = 'Starting environment setup...'
            CheckingPython           = 'Checking the private Python runtime...'
            ConfiguringEnvVars       = 'Configuring user environment variables...'
            RemovingStalePath        = 'Removing paths from a previous installation...'
            EnvVarsDone              = 'Environment variables configured.'
            VerifyingInstall         = 'Verifying that Java, Spark, PySpark, and ipykernel work...'
            VerifyDone               = 'Verification completed successfully.'
            Success                  = 'Post-installation completed successfully.'
            Cancelled                = 'Installation cancelled by the user.'
            FailedPrefix             = 'Post-installation failed: '
            CommandFailed            = 'The command failed'
            Running                  = 'Running'
            RemovingTempFiles        = 'Removing temporary files (installer, scripts, logs)...'
            ReadyForUse              = 'Installation is ready to use.'
        }
    }

    if ($text.ContainsKey($lang) -and $text[$lang].ContainsKey($Key)) {
        return $text[$lang][$Key]
    }
    if ($text['spanish'].ContainsKey($Key)) {
        return $text['spanish'][$Key]
    }
    return $Key
}

function Test-InstallCancelled {
    if ([string]::IsNullOrWhiteSpace($script:InstallCancelFile)) {
        return
    }
    if (Test-Path -LiteralPath $script:InstallCancelFile) {
        throw 'INSTALL_CANCELLED'
    }
}

function Test-IsSharingViolation {
    param($ErrorRecord)

    $ex = $ErrorRecord.Exception
    while ($null -ne $ex) {
        $code = 0
        try {
            $code = $ex.HResult -band 0xFFFF
        } catch {
        }
        if ($code -in 32, 33) {
            return $true
        }
        $msg = [string]$ex.Message
        if ($msg -match 'utilizado en otro proceso|being used by another process|sharing violation') {
            return $true
        }
        $ex = $ex.InnerException
    }
    return $false
}

function Invoke-WithSharingRetry {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [int]$Retries = 80,
        [int]$DelayMs = 25
    )

    for ($i = 0; $i -le $Retries; $i++) {
        try {
            & $Action
            return
        } catch {
            if (($i -ge $Retries) -or -not (Test-IsSharingViolation $_)) {
                throw
            }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
}

function Ensure-ParentDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

function Write-SharedFileBytes {
    param(
        [Parameter(Mandatory)][string]$Path,
        [byte[]]$Bytes = @(),
        [Parameter(Mandatory)][IO.FileMode]$Mode
    )

    Ensure-ParentDirectory -Path $Path
    Invoke-WithSharingRetry -Action {
        $fs = [IO.File]::Open(
            $Path,
            $Mode,
            [IO.FileAccess]::Write,
            [IO.FileShare]::ReadWrite
        )
        try {
            if ($Mode -eq [IO.FileMode]::Create) {
                $fs.SetLength(0)
            }
            if ($Bytes.Length -gt 0) {
                $fs.Write($Bytes, 0, $Bytes.Length)
            }
            $fs.Flush()
        } finally {
            $fs.Dispose()
        }
    }
}

function Set-SharedFileContent {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][allowemptystring()][string]$Text
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    Write-SharedFileBytes -Path $Path -Bytes $bytes -Mode ([IO.FileMode]::Create)
}

function Add-SharedFileLines {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Lines
    )

    if (@($Lines).Count -eq 0) {
        return
    }

    $payload = (@($Lines) -join [Environment]::NewLine) + [Environment]::NewLine
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    Write-SharedFileBytes -Path $Path -Bytes $bytes -Mode ([IO.FileMode]::Append)
}

function Write-InstallProgress {
    param(
        [Parameter(Mandatory)][int]$Percent,
        [Parameter(Mandatory)][string]$Status,
        [string]$LogFile
    )

    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }

    Write-InstallLog -Message $Status -LogFile $LogFile

    if ([string]::IsNullOrWhiteSpace($script:InstallProgressFile)) {
        return
    }

    $payload = '{0}{1}{2}{1}' -f $Percent, [Environment]::NewLine, $Status
    try {
        Set-SharedFileContent -Path $script:InstallProgressFile -Text $payload
    } catch {
        Write-Host ("Aviso: no se pudo actualizar el progreso: " + $_.Exception.Message)
    }
}

function Stop-ProcessTree {
    param([Parameter(Mandatory)][int]$ProcessId)

    try {
        Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.ProcessId) {
                    Stop-ProcessTree -ProcessId ([int]$_.ProcessId)
                }
            }
    } catch {
    }

    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Write-InstallLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$LogFile
    )

    $rawLines = @([string]$Message -split '\r?\n', -1)
    $maxLines = 80
    $maxChars = 500
    if ($rawLines.Count -gt $maxLines) {
        $omitted = $rawLines.Count - $maxLines
        $keepHead = 15
        $keepTail = $maxLines - $keepHead - 1
        $rawLines = @($rawLines[0..($keepHead - 1)]) +
            @("... [$omitted lines omitted] ...") +
            @($rawLines[($rawLines.Count - $keepTail)..($rawLines.Count - 1)])
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $outLines = foreach ($rawLine in $rawLines) {
        if ($rawLine.Length -gt $maxChars) {
            $rawLine = $rawLine.Substring(0, $maxChars) + '... [truncated]'
        }
        $line = '[' + $timestamp + '] ' + $rawLine
        Write-Host $line
        $line
    }

    if (-not $LogFile -or @($outLines).Count -eq 0) {
        return
    }

    try {
        Add-SharedFileLines -Path $LogFile -Lines @($outLines)
    } catch {
        Write-Host ("Aviso: no se pudo escribir el log: " + $_.Exception.Message)
    }
}

function Get-CommandOutputText {
    param($Output)

    $lines = foreach ($item in @($Output)) {
        if ($null -eq $item) { continue }
        if ($item -is [System.Management.Automation.ErrorRecord]) {
            $msg = [string]$item.Exception.Message
            if ([string]::IsNullOrWhiteSpace($msg)) {
                $msg = [string]$item
            }
            $msg
        } else {
            [string]$item
        }
    }
    return ($lines -join [Environment]::NewLine)
}

function Invoke-CapturedOutput {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = & $FilePath @ArgumentList 2>&1
        $exitCode = 0
        if (Test-Path 'variable:LASTEXITCODE') {
            $exitCode = $LASTEXITCODE
        }
        return [pscustomobject]@{
            ExitCode = $exitCode
            Output   = (Get-CommandOutputText -Output $raw)
        }
    } finally {
        $ErrorActionPreference = $previousEap
    }
}

function Get-OutputTail {
    param(
        [string]$Text,
        [int]$Lines = 40
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $all = @([string]$Text -split '\r?\n', -1)
    if ($all.Count -le $Lines) {
        return $Text.Trim()
    }

    return (($all[($all.Count - $Lines)..($all.Count - 1)]) -join [Environment]::NewLine).Trim()
}

function Read-IncrementalTextFile {
    param(
        [string]$Path,
        [ref]$Position
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        if ($Position.Value -gt $fs.Length) {
            $Position.Value = 0
        }
        [void]$fs.Seek($Position.Value, [IO.SeekOrigin]::Begin)
        $reader = New-Object IO.StreamReader($fs, [Text.UTF8Encoding]::new($false), $true, 4096, $true)
        try {
            $chunk = $reader.ReadToEnd()
            $Position.Value = $fs.Position
            return $chunk
        } finally {
            $reader.Dispose()
        }
    } finally {
        $fs.Dispose()
    }
}

function Invoke-LoggedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$LogFile,
        [int]$TimeoutSeconds = 0,
        [switch]$NoOutputCapture
    )

    Test-InstallCancelled

    $argsText = ($ArgumentList -join ' ')
    Write-InstallLog -Message ((Get-InstallUiText 'Running') + ': "' + $FilePath + '" ' + $argsText) -LogFile $LogFile

    $startParams = @{
        FilePath    = $FilePath
        PassThru    = $true
        WindowStyle = 'Hidden'
    }
    if (@($ArgumentList).Count -gt 0) {
        # Windows PowerShell 5.1 une ArgumentList con espacios y no cita cada
        # valor; una cadena ya citada es el contrato estable hacia Start-Process.
        $startParams.ArgumentList = @(
            foreach ($arg in @($ArgumentList)) {
                $text = [string]$arg
                if ($text -match '[\s"]') {
                    '"' + ($text.Replace('"', '\"')) + '"'
                } else {
                    $text
                }
            }
        ) -join ' '
    }

    if ($NoOutputCapture) {
        $process = Start-Process @startParams
        if (-not $process) {
            throw "$(Get-InstallUiText 'CommandFailed'): `"$FilePath`" $argsText"
        }
        try {
            $elapsed = [Diagnostics.Stopwatch]::StartNew()
            while (-not $process.HasExited) {
                Test-InstallCancelled
                if (($TimeoutSeconds -gt 0) -and ($elapsed.Elapsed.TotalSeconds -ge $TimeoutSeconds)) {
                    Stop-ProcessTree -ProcessId $process.Id
                    throw "$(Get-InstallUiText 'CommandFailed') (timeout ${TimeoutSeconds}s): `"$FilePath`" $argsText"
                }
                Start-Sleep -Milliseconds 400
            }
            $process.WaitForExit()
            $exitCode = 0
            if ($null -ne $process.ExitCode) {
                $exitCode = [int]$process.ExitCode
            }
            if ($exitCode -ne 0) {
                throw "$(Get-InstallUiText 'CommandFailed') (exit $exitCode): `"$FilePath`" $argsText"
            }
        } catch {
            if ([string]$_.Exception.Message -eq 'INSTALL_CANCELLED') {
                Stop-ProcessTree -ProcessId $process.Id
            }
            throw
        }
        return
    }

    $outFile = Join-Path $env:TEMP ('psb-out-' + [guid]::NewGuid().ToString('N') + '.log')
    $errFile = Join-Path $env:TEMP ('psb-err-' + [guid]::NewGuid().ToString('N') + '.log')
    $outPos = 0L
    $errPos = 0L
    $collected = New-Object System.Text.StringBuilder

    $drainFiles = {
        foreach ($item in @(
                @{ Path = $outFile; Pos = [ref]$outPos },
                @{ Path = $errFile; Pos = [ref]$errPos }
            )) {
            $chunk = Read-IncrementalTextFile -Path $item.Path -Position $item.Pos
            if ([string]::IsNullOrWhiteSpace($chunk)) {
                continue
            }
            [void]$collected.Append($chunk.TrimEnd() + [Environment]::NewLine)
            Write-InstallLog -Message $chunk.TrimEnd() -LogFile $LogFile
        }
    }

    $p = $null
    try {
        $p = Start-Process @startParams -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        if (-not $p) {
            throw "$(Get-InstallUiText 'CommandFailed'): `"$FilePath`" $argsText"
        }

        $elapsed = [Diagnostics.Stopwatch]::StartNew()
        while (-not $p.HasExited) {
            Test-InstallCancelled
            if (($TimeoutSeconds -gt 0) -and ($elapsed.Elapsed.TotalSeconds -ge $TimeoutSeconds)) {
                Stop-ProcessTree -ProcessId $p.Id
                throw "$(Get-InstallUiText 'CommandFailed') (timeout ${TimeoutSeconds}s): `"$FilePath`" $argsText"
            }
            & $drainFiles
            Start-Sleep -Milliseconds 400
        }
        $p.WaitForExit()
        Start-Sleep -Milliseconds 50
        & $drainFiles

        $exitCode = 0
        if ($null -ne $p.ExitCode) {
            $exitCode = [int]$p.ExitCode
        }
        if ($exitCode -ne 0) {
            $output = $collected.ToString()
            $tail = Get-OutputTail -Text $output
            $detail = "$(Get-InstallUiText 'CommandFailed') (exit $exitCode): `"$FilePath`" $argsText"
            if ($tail) {
                $detail = $detail + [Environment]::NewLine + $tail
            }
            throw $detail
        }
    } catch {
        if ($p -and -not $p.HasExited) {
            Stop-ProcessTree -ProcessId $p.Id
        }
        throw
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

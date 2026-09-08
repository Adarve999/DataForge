# Descarga componentes, prepara staging y compila el instalador con Inno Setup
[CmdletBinding()]
param(
    [switch]$SkipDownload,
    [switch]$SkipCompile,
    [string]$InnoSetupCompiler = '',
    [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$configPath = Join-Path $RepoRoot 'config\versions.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.ipykernelVersion) {
    throw "Falta ipykernelVersion en config/versions.json"
}

$installerDir = Join-Path $RepoRoot 'installer'
$downloadsDir = Join-Path $installerDir 'downloads'
$stagingDir = Join-Path $installerDir 'staging'
$distDir = Join-Path $installerDir 'dist'

$dirs = @($downloadsDir, $stagingDir, $distDir)
foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-DownloadPath {
    param([string]$Name)
    return Join-Path $downloadsDir $Name
}

function Invoke-FileDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Label = 'archivo'
    )

    if (Test-Path $Destination) {
        Write-Host "  Ya existe: $Destination"
        return
    }

    Write-Host "  Descargando $Label..."
    Write-Host "  URL: $Url"

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    curl.exe -fL --retry 3 --retry-delay 2 -o $Destination $Url
    if ($LASTEXITCODE -ne 0) {
        throw "Error descargando $Label"
    }
}

function Remove-DirectoryRetry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$Attempts = 8
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $lastMessage = ''
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $Path)) {
                return
            }
        } catch {
            $lastMessage = $_.Exception.Message
        }

        cmd.exe /c "rmdir /s /q `"$Path`"" | Out-Null
        if (-not (Test-Path -LiteralPath $Path)) {
            return
        }

        Start-Sleep -Milliseconds (400 * $i)
    }

    throw "No se pudo eliminar $Path. Cierra Explorer u otros procesos que usen esa carpeta e intentalo de nuevo. $lastMessage"
}

function Expand-ArchiveToDirectory {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$Destination,
        [string]$InnerRootName = ''
    )

    if (Test-Path $Destination) {
        Remove-DirectoryRetry -Path $Destination
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    $ext = [IO.Path]::GetExtension($ArchivePath).ToLowerInvariant()
    $tempExtract = Join-Path $downloadsDir ("extract_" + [Guid]::NewGuid().ToString('N'))

    try {
        New-Item -ItemType Directory -Force -Path $tempExtract | Out-Null

        if ($ext -eq '.zip') {
            Expand-Archive -Path $ArchivePath -DestinationPath $tempExtract -Force
        } elseif ($ext -eq '.tgz' -or $ArchivePath -like '*.tar.gz') {
            tar -xzf $ArchivePath -C $tempExtract
        } else {
            throw "Formato de archivo no soportado: $ArchivePath"
        }

        $sourceRoot = $tempExtract
        if ($InnerRootName) {
            $candidate = Join-Path $tempExtract $InnerRootName
            if (Test-Path $candidate) {
                $sourceRoot = $candidate
            }
        } else {
            $children = @(Get-ChildItem $tempExtract)
            if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
                $sourceRoot = $children[0].FullName
            }
        }

        Copy-Item -Path (Join-Path $sourceRoot '*') -Destination $Destination -Recurse -Force
    } finally {
        if (Test-Path $tempExtract) {
            Remove-DirectoryRetry -Path $tempExtract
        }
    }
}

function Reset-StagingLayout {
    param([string]$Root)

    foreach ($name in @('java', 'spark', 'hadoop', 'python', 'config', 'scripts', 'installer', 'bin', 'logs')) {
        $path = Join-Path $Root $name
        if (Test-Path $path) {
            Remove-DirectoryRetry -Path $path
        }
    }
    foreach ($name in @('LICENSE.txt', 'PRODUCT_INFO.txt')) {
        $path = Join-Path $Root $name
        if (Test-Path $path) {
            Remove-Item -Force $path
        }
    }

    foreach ($name in @('java', 'spark', 'hadoop', 'python', 'config', 'scripts')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Root $name) | Out-Null
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'hadoop\bin') | Out-Null
}

function Find-InnoSetupCompiler {
    param([string]$Override)

    if ($Override -and (Test-Path $Override)) {
        return $Override
    }

    $candidates = @(
        "$env:ProgramFiles\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Test-InnoSetupResourceLockError {
    param([string]$Output)

    return $Output -match 'EndUpdateResource failed|excluding the Output folder from your antivirus'
}

function Clear-InnoSetupOutputDirectory {
    param([Parameter(Mandatory)][string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Force -Path $Directory | Out-Null
        return
    }

    Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.exe' } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            } catch {
                Write-Host "  No se pudo borrar $($_.FullName): $($_.Exception.Message)"
            }
        }
}

function Invoke-InnoSetupCompile {
    param(
        [Parameter(Mandatory)][string]$Compiler,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [int]$Attempts = 3
    )

    $lastExit = 1
    $lastOutput = ''
    for ($i = 1; $i -le $Attempts; $i++) {
        if ($i -gt 1) {
            Write-Host "  Reintento $i/${Attempts}: Inno Setup no pudo sellar Setup.exe (bloqueo habitual del antivirus)."
            Start-Sleep -Seconds (4 * ($i - 1))
            Clear-InnoSetupOutputDirectory -Directory $OutputDirectory
        }

        $logFile = Join-Path $env:TEMP ('dataforge-iscc-' + [guid]::NewGuid().ToString('N') + '.log')
        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $Compiler @ArgumentList 2>&1 | Tee-Object -FilePath $logFile
            $lastExit = 0
            if (Test-Path 'variable:LASTEXITCODE') {
                $lastExit = [int]$LASTEXITCODE
            }
            if (Test-Path -LiteralPath $logFile) {
                $lastOutput = [IO.File]::ReadAllText($logFile)
            }
        } finally {
            $ErrorActionPreference = $previousEap
            Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
        }

        if ($lastExit -eq 0) {
            return
        }

        if (-not (Test-InnoSetupResourceLockError -Output $lastOutput)) {
            break
        }
    }

    $hint = @"
La compilacion de Inno Setup fallo (exit $lastExit).
Si el log muestra EndUpdateResource failed (110), Windows Defender u otro
antivirus ha bloqueado installer\dist mientras ISCC actualizaba iconos de
Setup.exe. El staging sigue siendo valido: recompila con -SkipDownload.
Para evitar el bloqueo, excluye esa carpeta del analisis en tiempo real.
"@
    throw $hint.Trim()
}

function Sync-StagingAssets {
    param([string]$Root)

    $legacyBin = Join-Path $Root 'bin'
    if (Test-Path $legacyBin) {
        Remove-Item -Recurse -Force $legacyBin
    }

    foreach ($name in @('config', 'scripts')) {
        $dest = Join-Path $Root $name
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        $source = Join-Path $RepoRoot $name
        if ($name -ne 'config') {
            $source = Join-Path $installerDir $name
        }
        Copy-Item -Path (Join-Path $source '*') -Destination $dest -Recurse -Force
    }
}

function Write-LicenseFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Config
    )

    $text = @"
$($Config.productName)
Copyright (C) 2026 the $($Config.productName) contributors

================================================================================
Independencia y marcas / Independence and trademarks
================================================================================

$($Config.productName) es un instalador comunitario independiente. No es un
producto oficial de The Apache Software Foundation, Eclipse Foundation AISBL
ni Python Software Foundation. No esta afiliado, respaldado ni patrocinado
por esas organizaciones.

$($Config.productName) is an independent community installer. It is not an
official product of the Apache Software Foundation, Eclipse Foundation AISBL,
or the Python Software Foundation. It is not affiliated with, endorsed by,
or sponsored by those organizations.

Uso descriptivo permitido por la ASF: "$($Config.productName), powered by Apache Spark".
ASF-permitted descriptive form: "$($Config.productName), powered by Apache Spark".
https://spark.apache.org/trademarks.html
https://www.apache.org/foundation/marks/

Apache, Apache Spark, Spark, Apache Hadoop, Hadoop, the Spark logo and
related marks are trademarks of the Apache Software Foundation.

Eclipse and Eclipse Temurin are trademarks of Eclipse Foundation AISBL.
https://www.eclipse.org/legal/logo-guidelines/

Python is a registered trademark of the Python Software Foundation.
https://www.python.org/psf/trademarks/

Java is a trademark of Oracle and/or its affiliates.

Este instalador no usa logotipos de Apache Spark ni de Eclipse. El nombre
del producto no contiene Spark, PySpark, Hadoop, Python, Java ni Apache.

This installer does not use Apache Spark or Eclipse logos. The product
name does not include Spark, PySpark, Hadoop, Python, Java, or Apache.

================================================================================
Aviso de licencias / License notice
================================================================================

Este instalador copia un runtime local que incluye Apache Spark y PySpark.
No cambia la licencia del software de terceros: cada componente conserva
su copyright y su licencia original. Las versiones de esta copia se leyeron
de config/versions.json durante la construccion del instalador.

This installer copies a local runtime that includes Apache Spark and
PySpark. It does not relicense third-party software: each component keeps
its original copyright and license. The versions in this copy were read
from config/versions.json when the installer was built.

$($Config.productName) entrega este runtime "TAL CUAL" / "AS IS", sin
garantia de ningun tipo, en la medida permitida por la ley.

By installing, you accept the terms of each bundled component.

================================================================================
Componentes de esta copia / Components in this copy
================================================================================

  $($Config.productName.PadRight(28))$($Config.productVersion)
  $('Eclipse Temurin JDK'.PadRight(28))$($Config.javaMajorVersion.ToString().PadRight(10))GPLv2 + Classpath Exception
  $('Apache Spark'.PadRight(28))$($Config.sparkVersion.PadRight(10))Apache License 2.0
  $('PySpark'.PadRight(28))$($Config.pysparkVersion.PadRight(10))Apache License 2.0
  $('ipykernel'.PadRight(28))$($Config.ipykernelVersion.PadRight(10))BSD 3-Clause
  $('Apache Hadoop winutils'.PadRight(28))$($Config.hadoopWinutilsVersion.PadRight(10))Apache License 2.0
  $('CPython'.PadRight(28))$($Config.pythonVersion.PadRight(10))PSF License Version 2

Las licencias completas viajan con cada componente:
Complete license texts ship with each component:

  java\     LICENSE, legal\          Eclipse Temurin / OpenJDK
  spark\    LICENSE, NOTICE          Apache Spark and bundled libraries
  hadoop\   LICENSE.txt, NOTICE      Apache Hadoop winutils attribution
  python\   LICENSE.txt              CPython
  python\   Lib\site-packages        PySpark, ipykernel and pip dependencies

Este archivo no es una segunda fuente canonica de versiones.
This file is not a second canonical source of version numbers.

================================================================================
1. Eclipse Temurin (OpenJDK)
================================================================================

Eclipse Temurin is a distribution of OpenJDK produced by the Eclipse
Adoptium Working Group. "Eclipse Temurin" is the formal product name.

OpenJDK is licensed under the GNU General Public License, version 2,
with the Classpath Exception (GPLv2+CE). Copyright (c) Oracle and/or
its affiliates, and other contributors.

The Classpath Exception permits linking this library with independent
modules under other licenses, and distributing the resulting executable
under terms of your choice, provided you also meet the license of each
independent module.

Full text:  java\legal\  and  https://openjdk.org/legal/gplv2+ce.html
Source:     https://adoptium.net/  and  https://github.com/adoptium
Build URL:  $($Config.downloads.java.url)

================================================================================
2. Apache Spark and PySpark
================================================================================

Apache Spark
Copyright 2014 and onwards The Apache Software Foundation.

This product includes software developed at
The Apache Software Foundation (https://www.apache.org/).

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Spark redistributes third-party libraries under their own licenses.
Those copyrights and terms are in spark\LICENSE and spark\NOTICE,
including the Apache export-control notice for cryptographic software.

PySpark is the Python API of Apache Spark and uses the same license.
It is installed into the private CPython prefix (python\).

Spark archive: $($Config.downloads.spark.url)

================================================================================
3. Apache Hadoop winutils
================================================================================

Apache Hadoop
Copyright 2006 and onwards The Apache Software Foundation.

winutils.exe, hadoop.dll and related native Windows binaries are Apache
Hadoop native Windows support files. They are not an official Apache
Hadoop Windows release. This installer copies the bin\ files from the
community distribution $($Config.downloads.winutils.repo)
(branch $($Config.downloads.winutils.branch)) for Apache Hadoop
$($Config.hadoopWinutilsVersion).

Licensed under the Apache License, Version 2.0.
https://www.apache.org/licenses/LICENSE-2.0
https://hadoop.apache.org/

Attribution files, when available from that distribution, are copied to
hadoop\ together with this notice. The Apache License requires that
LICENSE and NOTICE travel with redistributed binaries.

================================================================================
4. CPython (Python Software Foundation)
================================================================================

Python software and documentation are licensed under the Python Software
Foundation License Version 2.

Copyright (c) 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010,
2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022,
2023 Python Software Foundation; All Rights Reserved.

Some software incorporated into Python is under different licenses.
Those terms are listed in python\LICENSE.txt.

Installer used at build time: $($Config.downloads.python.filename)
Source: $($Config.downloads.python.url)

================================================================================
5. ipykernel
================================================================================

BSD 3-Clause License

Copyright (c) 2015, IPython Development Team
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

ipykernel $($Config.ipykernelVersion) is installed with its Python
dependencies (IPython, jupyter_client, traitlets, pyzmq and others).
Those packages keep their own licenses under python\Lib\site-packages.

================================================================================
6. $($Config.productName) installer
================================================================================

Copyright (C) 2026 the $($Config.productName) contributors

The installer, wizard and packaging scripts are original work that copies
and configures the components listed above. They do not replace those
licenses.

Permission is hereby granted, free of charge, to any person obtaining a
copy of this installer code and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Generated from config/versions.json during the installer build.
"@

    $legacyProductInfo = Join-Path (Split-Path -Parent $Path) 'PRODUCT_INFO.txt'
    if (Test-Path $legacyProductInfo) {
        Remove-Item -Force $legacyProductInfo
    }

    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    # UTF-8 BOM: Inno Setup LicenseFile needs it for Unicode text.
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText(
        $Path,
        ($text.TrimEnd() + [Environment]::NewLine),
        $utf8Bom)
}

function Copy-WinutilsLegalFiles {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$HadoopDir,
        [Parameter(Mandatory)]$Config
    )

    New-Item -ItemType Directory -Force -Path $HadoopDir | Out-Null
    foreach ($name in @('LICENSE', 'LICENSE.txt', 'NOTICE', 'NOTICE.txt')) {
        $source = Join-Path $RepoRoot $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $HadoopDir $name) -Force
        }
    }

    $hasNotice = (Test-Path -LiteralPath (Join-Path $HadoopDir 'NOTICE')) -or
        (Test-Path -LiteralPath (Join-Path $HadoopDir 'NOTICE.txt'))
    if (-not $hasNotice) {
        $notice = @"
Apache Hadoop
Copyright 2006 and onwards The Apache Software Foundation.

This product includes software developed at
The Apache Software Foundation (https://www.apache.org/).

Windows native binaries (winutils.exe and related files) were obtained
from https://github.com/$($Config.downloads.winutils.repo)
for Apache Hadoop $($Config.hadoopWinutilsVersion).
"@
        [IO.File]::WriteAllText(
            (Join-Path $HadoopDir 'NOTICE.txt'),
            ($notice.TrimEnd() + [Environment]::NewLine))
    }

    $hasLicense = (Test-Path -LiteralPath (Join-Path $HadoopDir 'LICENSE')) -or
        (Test-Path -LiteralPath (Join-Path $HadoopDir 'LICENSE.txt'))
    if (-not $hasLicense) {
        $license = @"
The Apache Hadoop Windows native binaries in this directory are licensed
under the Apache License, Version 2.0.

    https://www.apache.org/licenses/LICENSE-2.0
    https://hadoop.apache.org/

They are not an official Apache Hadoop Windows release.
Source: https://github.com/$($Config.downloads.winutils.repo)
"@
        [IO.File]::WriteAllText(
            (Join-Path $HadoopDir 'LICENSE.txt'),
            ($license.TrimEnd() + [Environment]::NewLine))
    }
}

function Invoke-BuildProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$NoOutputCapture
    )

    $argsText = ($ArgumentList -join ' ')
    Write-Host "  Ejecutando: `"$FilePath`" $argsText"

    if ($NoOutputCapture) {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -WindowStyle Hidden
        if (-not $process) {
            throw "No se pudo iniciar: `"$FilePath`" $argsText"
        }
        $process.WaitForExit()
        $exitCode = 0
        if ($null -ne $process.ExitCode) {
            $exitCode = [int]$process.ExitCode
        }
        if ($exitCode -ne 0) {
            throw "El comando fallo (exit $exitCode): `"$FilePath`" $argsText"
        }
        return
    }

    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $FilePath @ArgumentList
        $exitCode = 0
        if (Test-Path 'variable:LASTEXITCODE') {
            $exitCode = $LASTEXITCODE
        }
    } finally {
        $ErrorActionPreference = $previousEap
    }

    if ($exitCode -ne 0) {
        throw "El comando fallo (exit $exitCode): `"$FilePath`" $argsText"
    }
}

function Get-PythonRuntimeStamp {
    param([Parameter(Mandatory)]$Config)
    return "python=$($Config.pythonVersion);pyspark=$($Config.pysparkVersion);ipykernel=$($Config.ipykernelVersion)"
}

function Get-PythonRuntimeStampPath {
    param([Parameter(Mandatory)][string]$PythonRoot)
    return "$PythonRoot.stamp"
}

function Test-PythonRuntimeFresh {
    param(
        [Parameter(Mandatory)][string]$PythonRoot,
        [Parameter(Mandatory)]$Config
    )

    $pythonExe = Join-Path $PythonRoot 'python.exe'
    if (-not (Test-Path -LiteralPath $pythonExe)) {
        return $false
    }

    $stampPath = Get-PythonRuntimeStampPath -PythonRoot $PythonRoot
    if (-not (Test-Path -LiteralPath $stampPath)) {
        return $false
    }

    $stamp = (Get-Content -LiteralPath $stampPath -Raw).Trim()
    return $stamp -eq (Get-PythonRuntimeStamp -Config $Config)
}

function Get-NormalizedDirPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $s = $Path.Trim().Trim('"')
    try {
        $s = [IO.Path]::GetFullPath($s)
    } catch {
        return ($s -replace '\\+$', '').ToLowerInvariant()
    }
    return ($s -replace '\\+$', '').ToLowerInvariant()
}

function Get-RegisteredPythonInstallPath {
    param([Parameter(Mandatory)][string]$PythonVersion)

    $shortVersion = ($PythonVersion -split '\.')[0..1] -join '.'
    $keyPath = "HKCU:\Software\Python\PythonCore\$shortVersion\InstallPath"
    if (-not (Test-Path -LiteralPath $keyPath)) {
        return ''
    }

    $props = Get-ItemProperty -LiteralPath $keyPath -ErrorAction SilentlyContinue
    if (-not $props) {
        return ''
    }

    $installPath = [string]$props.'(default)'
    if ([string]::IsNullOrWhiteSpace($installPath) -and $props.PSObject.Properties['ExecutablePath']) {
        $exe = [string]$props.ExecutablePath
        if ($exe) {
            $installPath = Split-Path -Parent $exe
        }
    }
    return $installPath
}

function Get-OfficialPythonInstallArgs {
    param([Parameter(Mandatory)][string]$PythonRoot)

    @(
        '/quiet',
        'InstallAllUsers=0',
        'PrependPath=0',
        'Include_launcher=0',
        'InstallLauncherAllUsers=0',
        'Shortcuts=0',
        'AssociateFiles=0',
        'Include_test=0',
        'Include_doc=0',
        'Include_dev=0',
        'Include_tcltk=0',
        'Include_pip=1',
        'CompileAll=0',
        "TargetDir=$PythonRoot"
    )
}

function Test-PythonHasPip {
    param([Parameter(Mandatory)][string]$PythonRoot)

    $pythonExe = Join-Path $PythonRoot 'python.exe'
    if (-not (Test-Path -LiteralPath $pythonExe)) {
        return $false
    }

    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & $pythonExe -m pip --version 2>&1
        $exitCode = 1
        if (Test-Path 'variable:LASTEXITCODE') {
            $exitCode = $LASTEXITCODE
        }
        return ($exitCode -eq 0)
    } finally {
        $ErrorActionPreference = $previousEap
    }
}

function Restore-PipViaEnsurepip {
    param([Parameter(Mandatory)][string]$PythonRoot)

    $pythonExe = Join-Path $PythonRoot 'python.exe'
    if (-not (Test-Path -LiteralPath $pythonExe)) {
        return
    }
    if (Test-PythonHasPip -PythonRoot $PythonRoot) {
        return
    }

    Write-Host "  Restaurando pip con ensurepip en $PythonRoot..."
    Invoke-BuildProcess -FilePath $pythonExe -ArgumentList @(
        '-m', 'ensurepip', '--upgrade', '--default-pip'
    )
}

function Test-OfficialPythonReady {
    param([Parameter(Mandatory)][string]$PythonRoot)

    $pythonExe = Join-Path $PythonRoot 'python.exe'
    return (Test-Path -LiteralPath $pythonExe) -and (Test-PythonHasPip -PythonRoot $PythonRoot)
}

function Write-OfficialPythonInstallFailure {
    param([Parameter(Mandatory)][string]$PythonRoot)

    $logHint = ''
    $latestLog = Get-ChildItem -LiteralPath $env:TEMP -Filter 'Python *.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latestLog) {
        $logHint = " Revisa el log del instalador: $($latestLog.FullName)"
    }
    throw "CPython oficial no quedo instalado (python.exe + pip) en $PythonRoot.$logHint"
}

function Test-IsBuildOwnedPythonPrefix {
    param([string]$Path)

    $norm = Get-NormalizedDirPath $Path
    if (-not $norm) {
        return $false
    }
    return $norm -match '[\\/]installer[\\/]downloads[\\/]python-root$'
}

function Test-PythonPrefixHasInterpreter {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    return (Test-Path -LiteralPath (Join-Path $Path 'python.exe'))
}

function Test-OfficialPythonBundleRegistered {
    param([Parameter(Mandatory)][string]$PythonVersion)

    $expectedName = "Python $PythonVersion (64-bit)"
    $uninstallRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    if (-not (Test-Path -LiteralPath $uninstallRoot)) {
        return $false
    }

    foreach ($item in Get-ChildItem -LiteralPath $uninstallRoot -ErrorAction SilentlyContinue) {
        $props = Get-ItemProperty -LiteralPath $item.PSPath -ErrorAction SilentlyContinue
        if (-not $props) {
            continue
        }
        if ($props.PSObject.Properties['DisplayName'] -and ([string]$props.DisplayName -eq $expectedName)) {
            return $true
        }
    }
    return $false
}

function Test-OfficialPythonProductPresent {
    param([Parameter(Mandatory)][string]$PythonVersion)

    $registered = Get-RegisteredPythonInstallPath -PythonVersion $PythonVersion
    return (-not [string]::IsNullOrWhiteSpace($registered)) -or (Test-OfficialPythonBundleRegistered -PythonVersion $PythonVersion)
}

function Invoke-OfficialPythonRepair {
    param(
        [Parameter(Mandatory)][string]$PythonInstaller,
        [Parameter(Mandatory)][string]$PythonRoot
    )

    $repairArgs = Get-OfficialPythonInstallArgs -PythonRoot $PythonRoot
    Invoke-BuildProcess -FilePath $PythonInstaller -ArgumentList (@('/repair') + $repairArgs) -NoOutputCapture
}

function Restore-OfficialPythonPrefixForUninstall {
    param(
        [Parameter(Mandatory)][string]$PythonInstaller,
        [Parameter(Mandatory)][string]$RegisteredPath
    )

    if (Test-PythonPrefixHasInterpreter -Path $RegisteredPath) {
        return
    }

    Write-Host "  Restaurando CPython de build en $RegisteredPath para poder desinstalarlo..."
    Invoke-OfficialPythonRepair -PythonInstaller $PythonInstaller -PythonRoot $RegisteredPath
    if (-not (Test-PythonPrefixHasInterpreter -Path $RegisteredPath)) {
        throw "No se pudo restaurar python.exe en $RegisteredPath. El MSI de pip del instalador oficial exige un Python detectable y /uninstall falla (1603) si falta."
    }
}

function Uninstall-OfficialPythonBundle {
    param(
        [Parameter(Mandatory)][string]$PythonInstaller,
        [Parameter(Mandatory)][string]$PythonVersion,
        [Parameter(Mandatory)][string]$Reason
    )

    Write-Host "  Desinstalando CPython oficial de build: $Reason"
    Invoke-BuildProcess -FilePath $PythonInstaller -ArgumentList @('/uninstall', '/quiet') -NoOutputCapture
    if (Test-OfficialPythonProductPresent -PythonVersion $PythonVersion) {
        throw "CPython $PythonVersion sigue registrado tras /uninstall. Un /quiet nuevo hace Modify y no escribe archivos."
    }
}

function Install-OfficialPython {
    param(
        [Parameter(Mandatory)][string]$PythonRoot,
        [Parameter(Mandatory)][string]$PythonInstaller,
        [Parameter(Mandatory)][string]$PythonVersion
    )

    if (-not (Test-Path -LiteralPath $PythonInstaller)) {
        throw "No se encontro el instalador oficial de Python: $PythonInstaller"
    }

    $parent = Split-Path -Parent $PythonRoot
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    if (Test-OfficialPythonReady -PythonRoot $PythonRoot) {
        return
    }

    $installArgs = Get-OfficialPythonInstallArgs -PythonRoot $PythonRoot
    $registeredPath = Get-RegisteredPythonInstallPath -PythonVersion $PythonVersion
    $registeredNorm = Get-NormalizedDirPath $registeredPath
    $rootNorm = Get-NormalizedDirPath $PythonRoot
    $registeredToBuildPrefix = $registeredNorm -and ($registeredNorm -eq $rootNorm)
    $registeredIsBuildOwned = Test-IsBuildOwnedPythonPrefix -Path $registeredPath
    $registeredMissingFiles = $registeredNorm -and -not (Test-PythonPrefixHasInterpreter -Path $registeredPath)
    $bundleRegistered = Test-OfficialPythonBundleRegistered -PythonVersion $PythonVersion

    if ($registeredToBuildPrefix) {
        Write-Host "  Reparando CPython de build (Windows Installer aun lo registra en $PythonRoot)..."
        Invoke-OfficialPythonRepair -PythonInstaller $PythonInstaller -PythonRoot $PythonRoot
        Restore-PipViaEnsurepip -PythonRoot $PythonRoot
        if (Test-OfficialPythonReady -PythonRoot $PythonRoot) {
            return
        }

        Write-Host "  La reparacion no dejo un CPython usable. Se intentara desinstalar el registro huerfano..."
        Restore-OfficialPythonPrefixForUninstall `
            -PythonInstaller $PythonInstaller `
            -RegisteredPath $PythonRoot
        Uninstall-OfficialPythonBundle `
            -PythonInstaller $PythonInstaller `
            -PythonVersion $PythonVersion `
            -Reason "registro huerfano en $PythonRoot"
    } elseif ($registeredIsBuildOwned -or $registeredMissingFiles) {
        Restore-OfficialPythonPrefixForUninstall `
            -PythonInstaller $PythonInstaller `
            -RegisteredPath $registeredPath
        $reason = if ($registeredMissingFiles) {
            "registro huerfano en $registeredPath"
        } else {
            "prefijo de build anterior en $registeredPath"
        }
        Uninstall-OfficialPythonBundle `
            -PythonInstaller $PythonInstaller `
            -PythonVersion $PythonVersion `
            -Reason $reason
    } elseif ($registeredNorm) {
        throw "CPython $PythonVersion ya esta registrado en $registeredPath. El instalador oficial per-user no puede crear un segundo prefijo y DataForge no modifica un Python ajeno."
    } elseif ($bundleRegistered) {
        Uninstall-OfficialPythonBundle `
            -PythonInstaller $PythonInstaller `
            -PythonVersion $PythonVersion `
            -Reason "el paquete Windows Installer sigue registrado sin InstallPath"
    }

    if (Test-Path -LiteralPath $PythonRoot) {
        Write-Host "  Eliminando prefijo Python anterior: $PythonRoot"
        Remove-DirectoryRetry -Path $PythonRoot
    }

    Write-Host "  Instalando CPython oficial en $PythonRoot..."
    Invoke-BuildProcess -FilePath $PythonInstaller -ArgumentList $installArgs -NoOutputCapture
    Restore-PipViaEnsurepip -PythonRoot $PythonRoot

    if (-not (Test-OfficialPythonReady -PythonRoot $PythonRoot)) {
        Write-OfficialPythonInstallFailure -PythonRoot $PythonRoot
    }
}

function New-StagedPythonRuntime {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$PythonInstaller,
        [Parameter(Mandatory)][string]$PythonRoot,
        [Parameter(Mandatory)][string]$StagingPythonDir
    )

    $pythonExe = Join-Path $PythonRoot 'python.exe'
    $stampPath = Get-PythonRuntimeStampPath -PythonRoot $PythonRoot

    if (Test-PythonRuntimeFresh -PythonRoot $PythonRoot -Config $Config) {
        Write-Host "  Reutilizando runtime Python de build: $PythonRoot"
    } else {
        if (-not (Test-OfficialPythonReady -PythonRoot $PythonRoot)) {
            Install-OfficialPython `
                -PythonRoot $PythonRoot `
                -PythonInstaller $PythonInstaller `
                -PythonVersion $Config.pythonVersion
        }

        Write-Host "  Instalando PySpark $($Config.pysparkVersion) e ipykernel $($Config.ipykernelVersion) en el runtime de build..."
        $previousNoUserSite = $env:PYTHONNOUSERSITE
        $env:PYTHONNOUSERSITE = '1'
        try {
            Invoke-BuildProcess -FilePath $pythonExe -ArgumentList @(
                '-s', '-m', 'pip', 'install',
                '--disable-pip-version-check',
                '--no-warn-script-location',
                '--no-user',
                "pyspark==$($Config.pysparkVersion)",
                "ipykernel==$($Config.ipykernelVersion)"
            )
        } finally {
            if ($null -eq $previousNoUserSite) {
                Remove-Item Env:PYTHONNOUSERSITE -ErrorAction SilentlyContinue
            } else {
                $env:PYTHONNOUSERSITE = $previousNoUserSite
            }
        }

        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText(
            $stampPath,
            ((Get-PythonRuntimeStamp -Config $Config) + [Environment]::NewLine),
            $utf8NoBom)
    }

    if (Test-Path -LiteralPath $StagingPythonDir) {
        Remove-DirectoryRetry -Path $StagingPythonDir
    }
    New-Item -ItemType Directory -Force -Path $StagingPythonDir | Out-Null
    Write-Host "  Copiando runtime Python a staging: $StagingPythonDir"
    Copy-Item -Path (Join-Path $PythonRoot '*') -Destination $StagingPythonDir -Recurse -Force

    $stagedPython = Join-Path $StagingPythonDir 'python.exe'
    if (-not (Test-Path -LiteralPath $stagedPython)) {
        throw "No se copio python.exe a $StagingPythonDir"
    }
}

if (-not $SkipDownload) {
    Write-Step "Descargando dependencias"

    $sparkArchive = Get-DownloadPath $config.downloads.spark.filename
    $javaArchive = Get-DownloadPath $config.downloads.java.filename
    $winutilsArchive = Get-DownloadPath $config.downloads.winutils.filename
    $pythonInstaller = Get-DownloadPath $config.downloads.python.filename

    Invoke-FileDownload -Url $config.downloads.spark.url -Destination $sparkArchive -Label "Apache Spark $($config.sparkVersion)"
    Invoke-FileDownload -Url $config.downloads.java.url -Destination $javaArchive -Label "Java $($config.javaMajorVersion) (Temurin)"
    Invoke-FileDownload -Url "https://github.com/$($config.downloads.winutils.repo)/archive/refs/heads/$($config.downloads.winutils.branch).zip" `
        -Destination $winutilsArchive -Label "winutils (Hadoop $($config.hadoopWinutilsVersion))"
    Invoke-FileDownload -Url $config.downloads.python.url -Destination $pythonInstaller -Label "Python $($config.pythonVersion)"

    Write-Step "Preparando staging"

    Reset-StagingLayout -Root $stagingDir

    Expand-ArchiveToDirectory -ArchivePath $javaArchive -Destination (Join-Path $stagingDir 'java')
    Expand-ArchiveToDirectory -ArchivePath $sparkArchive -Destination (Join-Path $stagingDir 'spark') -InnerRootName $config.downloads.spark.archiveInnerDir

    $winutilsExtract = Join-Path $downloadsDir 'winutils_extract'
    if (Test-Path $winutilsExtract) {
        Remove-DirectoryRetry -Path $winutilsExtract
    }
    Expand-Archive -Path $winutilsArchive -DestinationPath $winutilsExtract -Force

    $repoFolderName = "winutils-$($config.downloads.winutils.branch)"
    $winutilsSource = Join-Path (Join-Path $winutilsExtract $repoFolderName) ($config.downloads.winutils.sourcePath -replace '/', '\')
    if (-not (Test-Path $winutilsSource)) {
        $repoFolder = Get-ChildItem $winutilsExtract -Directory | Select-Object -First 1
        $winutilsSource = Join-Path $repoFolder.FullName ($config.downloads.winutils.sourcePath -replace '/', '\')
    }

    if (-not (Test-Path $winutilsSource)) {
        throw "No se encontro winutils en el archivo descargado"
    }

    Copy-Item -Path (Join-Path $winutilsSource '*') -Destination (Join-Path $stagingDir 'hadoop\bin') -Recurse -Force

    $winutilsRepoRoot = Join-Path $winutilsExtract $repoFolderName
    if (-not (Test-Path -LiteralPath $winutilsRepoRoot)) {
        $winutilsRepoRoot = (Get-ChildItem $winutilsExtract -Directory | Select-Object -First 1).FullName
    }
    Copy-WinutilsLegalFiles `
        -RepoRoot $winutilsRepoRoot `
        -HadoopDir (Join-Path $stagingDir 'hadoop') `
        -Config $config

    Write-Step "Preparando runtime Python $($config.pythonVersion) con PySpark $($config.pysparkVersion) e ipykernel $($config.ipykernelVersion)"
    $pythonRoot = Join-Path $downloadsDir 'python-root'
    New-StagedPythonRuntime `
        -Config $config `
        -PythonInstaller $pythonInstaller `
        -PythonRoot $pythonRoot `
        -StagingPythonDir (Join-Path $stagingDir $config.downloads.python.targetDir)

    Write-Host "  Staging listo en: $stagingDir"
} else {
    Write-Host "Omitiendo descarga (--SkipDownload)"
    if (-not (Test-Path $stagingDir)) {
        throw "No existe staging. Ejecuta primero sin --SkipDownload."
    }
}

Write-Step "Sincronizando scripts y config en staging"
Sync-StagingAssets -Root $stagingDir
Write-LicenseFile -Path (Join-Path $stagingDir 'LICENSE.txt') -Config $config
Copy-WinutilsLegalFiles `
    -RepoRoot (Join-Path $stagingDir '.no-winutils-repo') `
    -HadoopDir (Join-Path $stagingDir 'hadoop') `
    -Config $config

$requiredStagingFiles = @(
    (Join-Path $stagingDir 'java\bin\java.exe'),
    (Join-Path $stagingDir 'spark\bin\spark-submit.cmd'),
    (Join-Path $stagingDir 'hadoop\bin\winutils.exe'),
    (Join-Path $stagingDir 'config\versions.json'),
    (Join-Path $stagingDir 'scripts\post-install.ps1'),
    (Join-Path $stagingDir 'LICENSE.txt'),
    (Join-Path $stagingDir 'python\python.exe')
)
$missingStagingFiles = @($requiredStagingFiles | Where-Object { -not (Test-Path $_) })
if ($missingStagingFiles.Count -gt 0) {
    throw @"
El staging esta incompleto. Faltan:
$($missingStagingFiles -join [Environment]::NewLine)
Ejecuta primero .\build-installer.ps1 -SkipCompile para descargar y preparar todas las dependencias.
"@
}

if (-not $SkipCompile) {
    Write-Step "Compilando instalador con Inno Setup"

    $iscc = Find-InnoSetupCompiler -Override $InnoSetupCompiler
    if (-not $iscc) {
        throw @"
No se encontro Inno Setup 7 ni Inno Setup 6.3+ (ISCC.exe).
Instalalo desde https://jrsoftware.org/isinfo.php
o pasa -InnoSetupCompiler 'C:\ruta\a\ISCC.exe'
"@
    }

    $issFile = Join-Path $installerDir 'DataForge.iss'
    $homeVar = ($config.productName.ToUpperInvariant() -replace '[^A-Z0-9]', '') + '_HOME'
    $issDefines = @(
        "/DRepoRoot=$RepoRoot",
        "/DMyAppName=$($config.productName)",
        "/DMyHomeVar=$homeVar",
        "/DMyAppVersion=$($config.productVersion)",
        "/DJavaMajorVersion=$($config.javaMajorVersion)",
        "/DSparkVersion=$($config.sparkVersion)",
        "/DPySparkVersion=$($config.pysparkVersion)",
        "/DIpykernelVersion=$($config.ipykernelVersion)",
        "/DHadoopWinutilsVersion=$($config.hadoopWinutilsVersion)",
        "/DPythonVersion=$($config.pythonVersion)"
    )
    $isccArgs = @($issFile) + $issDefines
    Invoke-InnoSetupCompile -Compiler $iscc -ArgumentList $isccArgs -OutputDirectory $distDir

    Write-Host ""
    Write-Host "Instalador generado en: $distDir" -ForegroundColor Green
} else {
    Write-Host "Omitiendo compilacion (--SkipCompile)"
}

; DataForge - Instalador Windows (Inno Setup 6.3+)
; Compilar: .\build-installer.ps1

#ifndef RepoRoot
  #define RepoRoot ".."
#endif

#ifndef MyAppVersion
  #error Este archivo debe compilarse mediante build-installer.ps1 para cargar config/versions.json
#endif

#define StagingDir RepoRoot + "\installer\staging"
#define OutputDir RepoRoot + "\installer\dist"
#define MyAppURL "https://github.com/DataForge/DataForge"
#ifndef MyHomeVar
  #define MyHomeVar "DATAFORGE_HOME"
#endif
; Empresa PEP 514 y kernelspec publicados antes del cambio de nombre.
#define MyLegacyAppName "PySparkBuilder"
; GUID sin llaves. AppId usa {{ para que el compilador conserve las llaves.
; Se conserva para reemplazar instalaciones publicadas con el nombre anterior.
#define MyAppGuid "A7B3C4D5-E6F7-4890-ABCD-EF1234567890"
#define MyAppId "{{" + MyAppGuid + "}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVerName={#MyAppName} {#MyAppVersion}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppName}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
AppCopyright=Copyright (C) 2026 the {#MyAppName} contributors
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppName}
VersionInfoOriginalFileName={#MyAppName}-Setup-{#MyAppVersion}.exe
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=yes
DisableReadyPage=no
DisableFinishedPage=no
AllowCancelDuringInstall=yes
LicenseFile={#StagingDir}\LICENSE.txt
OutputDir={#OutputDir}
OutputBaseFilename={#MyAppName}-Setup-{#MyAppVersion}
SetupIconFile=assets\setup.ico
UninstallDisplayName={#MyAppName} {#MyAppVersion}
WizardImageFile=assets\wizard-image.png
WizardSmallImageFile=assets\wizard-small.png
WizardImageStretch=yes
WizardImageBackColor=$20120B
WizardStyle=modern
WizardSizePercent=130
ShowLanguageDialog=yes
LanguageDetectionMethod=uilanguage
Compression=lzma2/ultra64
SolidCompression=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
ChangesEnvironment=yes
SetupLogging=yes
SetupMutex={#MyAppName}SetupMutex
AppMutex={#MyAppName}AppMutex
CloseApplications=yes
ExtraDiskSpaceRequired=500000000
UsePreviousAppDir=yes
UsePreviousLanguage=yes
DirExistsWarning=auto

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#StagingDir}\java\*"; DestDir: "{app}\java"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StagingDir}\spark\*"; DestDir: "{app}\spark"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StagingDir}\hadoop\*"; DestDir: "{app}\hadoop"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StagingDir}\python\*"; DestDir: "{app}\python"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#StagingDir}\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
; Payload de post-instalacion: no se copia a {app}. ExtractTemporaryFile lo
; materializa en {tmp} solo mientras corre PowerShell. uninstall-env.ps1
; permanece en el repo como utilidad y no viaja en el .exe.
Source: "{#StagingDir}\scripts\post-install.ps1"; Flags: dontcopy
Source: "{#StagingDir}\scripts\common.ps1"; Flags: dontcopy
Source: "{#StagingDir}\scripts\setup-env.ps1"; Flags: dontcopy
Source: "{#StagingDir}\scripts\verify-install.ps1"; Flags: dontcopy
Source: "{#StagingDir}\config\versions.json"; Flags: dontcopy

[Icons]
Name: "{group}\Apache Spark shell"; Filename: "{cmd}"; Parameters: "{code:GetPySparkShellParameters}"; WorkingDir: "{app}"
Name: "{group}\Python ({#MyAppName})"; Filename: "{cmd}"; Parameters: "{code:GetPySparkPythonParameters}"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Apache Spark shell"; Filename: "{cmd}"; Parameters: "{code:GetPySparkShellParameters}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{cmd}"; Parameters: "{code:GetPySparkShellParameters}"; Description: "{cm:LaunchPySparkShell}"; Flags: nowait postinstall skipifsilent unchecked
Filename: "{app}"; Description: "{cm:OpenInstallFolder}"; Flags: nowait postinstall skipifsilent unchecked shellexec

[UninstallDelete]
; Elimina tambien contenido generado durante la instalacion/ejecucion.
Type: filesandordirs; Name: "{app}\java"
Type: filesandordirs; Name: "{app}\spark"
Type: filesandordirs; Name: "{app}\hadoop"
Type: filesandordirs; Name: "{app}\config"
Type: filesandordirs; Name: "{app}\scripts"
Type: filesandordirs; Name: "{app}\installer"
Type: filesandordirs; Name: "{app}\python"
Type: filesandordirs; Name: "{userappdata}\jupyter\kernels\{#MyAppName}"
Type: filesandordirs; Name: "{userappdata}\jupyter\kernels\{#MyLegacyAppName}"
Type: filesandordirs; Name: "{app}\logs"
Type: files; Name: "{app}\LICENSE.txt"
; Instalaciones anteriores a LICENSE.txt.
Type: files; Name: "{app}\PRODUCT_INFO.txt"
; Compatibilidad con instalaciones anteriores al layout minimo.
Type: filesandordirs; Name: "{app}\bin"
Type: files; Name: "{app}\setup.ico"
Type: dirifempty; Name: "{app}"

[Messages]
spanish.WelcomeLabel1=Bienvenido a [name], powered by Apache Spark
spanish.WelcomeLabel2=Esto instalara [name/ver] en su equipo.%n%nIncluye Eclipse Temurin {#JavaMajorVersion}, Apache Spark {#SparkVersion}, winutils de Apache Hadoop {#HadoopWinutilsVersion} y Python {#PythonVersion} con PySpark {#PySparkVersion} e ipykernel {#IpykernelVersion}.%n%nSe recomienda cerrar las demas aplicaciones antes de continuar.
spanish.FinishedHeadingLabel=Instalacion de [name] completada
spanish.FinishedLabel={#MyAppName} se ha instalado en su equipo.%n%nAbra una terminal nueva o use el acceso directo Apache Spark shell. Los cambios de PATH no se aplican a terminales que ya estaban abiertas.
spanish.FinishedLabelNoIcons={#MyAppName} se ha instalado en su equipo.%n%nAbra una terminal nueva para usar pyspark. Los cambios de PATH no se aplican a terminales que ya estaban abiertas.
spanish.ClickFinish=Haga clic en Finalizar para cerrar el instalador.
spanish.SelectDirLabel3=El programa se instalara en la siguiente carpeta.
spanish.DiskSpaceMBLabel=Espacio libre requerido (aprox.): [mb] MB
spanish.ButtonInstall=&Instalar
spanish.ReadyLabel1=El instalador esta listo para copiar [name] en su equipo.
spanish.ReadyLabel2b=Haga clic en Instalar para continuar. La copia de archivos es el primer paso; despues se configurara el entorno y debera pulsar Siguiente cuando termine.
spanish.InstallingLabel=Copiando archivos de {#MyAppName}. Espere...
spanish.ExitSetupTitle=Cancelar instalacion
spanish.ExitSetupMessage=Seguro que desea cancelar la instalacion de {#MyAppName}?
spanish.SetupAppTitle=Instalador de [name]
spanish.UninstallAppTitle=Desinstalador de [name]
spanish.ConfirmUninstall=Seguro que desea desinstalar %1 por completo?

english.WelcomeLabel1=Welcome to [name], powered by Apache Spark
english.WelcomeLabel2=This will install [name/ver] on your computer.%n%nIt includes Eclipse Temurin {#JavaMajorVersion}, Apache Spark {#SparkVersion}, Apache Hadoop {#HadoopWinutilsVersion} winutils, and Python {#PythonVersion} with PySpark {#PySparkVersion} and ipykernel {#IpykernelVersion}.%n%nIt is recommended that you close other applications before continuing.
english.FinishedHeadingLabel=Completing the [name] Setup Wizard
english.FinishedLabel={#MyAppName} has been installed on your computer.%n%nOpen a new terminal or use the Apache Spark shell shortcut. PATH changes do not apply to terminals that were already open.
english.FinishedLabelNoIcons={#MyAppName} has been installed on your computer.%n%nOpen a new terminal to use pyspark. PATH changes do not apply to terminals that were already open.
english.ClickFinish=Click Finish to close Setup.
english.SelectDirLabel3=Setup will install into the following folder.
english.DiskSpaceMBLabel=Required free space (approx.): [mb] MB
english.ButtonInstall=&Install
english.ReadyLabel1=Setup is ready to copy [name] to your computer.
english.ReadyLabel2b=Click Install to continue. Copying files is the first step; afterwards the environment will be configured and you must click Next when it finishes.
english.InstallingLabel=Copying {#MyAppName} files. Please wait...
english.ExitSetupTitle=Exit Setup
english.ExitSetupMessage=Are you sure you want to cancel the {#MyAppName} installation?
english.SetupAppTitle=[name] Setup
english.UninstallAppTitle=[name] Uninstall
english.ConfirmUninstall=Are you sure you want to completely remove %1?

[CustomMessages]
spanish.CreateDesktopIcon=Crear un acceso directo en el escritorio (Apache Spark shell)
spanish.AdditionalIcons=Accesos directos:
spanish.LaunchPySparkShell=Iniciar Apache Spark shell (recomendado para comprobar la instalacion)
spanish.OpenInstallFolder=Abrir la carpeta de instalacion
spanish.PostInstallCaption=Configuracion del entorno
spanish.PostInstallDescription=Configurando el entorno y comprobando Java, Spark, PySpark e ipykernel.
spanish.PostInstallWaiting=Preparando la configuracion...
spanish.PostInstallDetail=El detalle se muestra en tiempo real. Puede cancelar si lo necesita; se limpiara la instalacion incompleta.
spanish.PostInstallSuccess=Configuracion completada correctamente.
spanish.PostInstallSuccessDetail=Revise el registro si lo desea y haga clic en Siguiente para finalizar y eliminar los archivos temporales.
spanish.PostInstallFailed=La configuracion del entorno no se completo.
spanish.PostInstallFailedDetail=Revise el registro. Al cerrar podra quitar los archivos incompletos o conservarlos para diagnostico.
spanish.PostInstallCleanupFailed=El runtime se configuro, pero no se pudieron eliminar todos los archivos temporales.
spanish.PostInstallCleanupFailedDetail=Cierre el instalador y revise los archivos en uso o los permisos. Se conservara la evidencia disponible para diagnostico.
spanish.ConfirmCancelSetup=La configuracion del entorno aun no ha terminado.%n%nSi cancela ahora, se detendra la verificacion y se eliminara la instalacion incompleta.%n%nDesea cancelar?
spanish.CancellingSetup=Cancelando y deteniendo procesos...
spanish.CancelCleanup=El usuario cancelo la instalacion. Limpiando...
spanish.CloseButton=Cerrar
spanish.FailedKeepFiles=La instalacion no se completo.%n%nDesea quitar los archivos incompletos?%n%nSi = eliminar todo%nNo = conservarlos para diagnostico (podra desinstalar despues)
spanish.ReadyMemoIntro=El instalador realizara lo siguiente:
spanish.ReadyMemoComponents=Componentes que se configuraran:
spanish.ReadyMemoTime=Despues de copiar archivos se configuraran las variables de entorno y se comprobara una SparkSession local. No requiere Internet. Al terminar debera pulsar Siguiente.
spanish.NeedPowerShell={#MyAppName} necesita Windows PowerShell 5.1 para instalarse.
spanish.PostInstallStartFailed=No se pudo iniciar la configuracion del entorno.
spanish.PostInstallLogCopied=Copiando archivos...
spanish.PostInstallLogTruncated=El registro es demasiado largo para mostrarlo aqui. Consulte install.log en la carpeta logs de la instalacion.
spanish.UninstallCaption=Desinstalando {#MyAppName}
spanish.UninstallDescription=Eliminando el entorno y mostrando el detalle en tiempo real.
spanish.ReplaceExistingCaption=Reemplazar instalacion existente
spanish.ReplaceExistingDescription=Ya hay una copia de {#MyAppName} en este equipo.
spanish.ReplaceExistingBody=Se encontro {#MyAppName} %1 en:%n%n%2%n%nEste instalador la reemplazara en esa misma carpeta con la version %3. No se admite una segunda copia.%n%nSi necesita otra carpeta, pulse Cancelar, desinstale desde Agregar o quitar programas y vuelva a instalar.
spanish.ReplaceExistingUnknownVersion=una version anterior
spanish.ReplaceDirLocked={#MyAppName} ya esta instalado. Debe reemplazarse en:%n%n%1
spanish.ReplacePrivilegeMismatch={#MyAppName} ya esta instalado %1:%n%n%2%n%nDesinstale esa copia desde Agregar o quitar programas y vuelva a ejecutar este instalador. No se admite una segunda copia.
spanish.ReplacePrivilegeAllUsers=para todos los usuarios
spanish.ReplacePrivilegeCurrentUser=para el usuario actual
spanish.ReplaceReadyNote=Se reemplazara la instalacion existente en la misma carpeta. No se creara una segunda copia.
spanish.ReplaceMissingLocation=(ubicacion no registrada)
spanish.ReplaceUnknownDir={#MyAppName} ya aparece como instalado, pero no se pudo determinar la carpeta. Desinstalelo desde Agregar o quitar programas y vuelva a ejecutar este instalador.

english.CreateDesktopIcon=Create a desktop shortcut (Apache Spark shell)
english.AdditionalIcons=Shortcuts:
english.LaunchPySparkShell=Launch Apache Spark shell (recommended to verify the installation)
english.OpenInstallFolder=Open the installation folder
english.PostInstallCaption=Environment setup
english.PostInstallDescription=Configuring the environment and verifying Java, Spark, PySpark, and ipykernel.
english.PostInstallWaiting=Preparing configuration...
english.PostInstallDetail=Details are shown in real time. You can cancel if needed; the incomplete installation will be removed.
english.PostInstallSuccess=Configuration completed successfully.
english.PostInstallSuccessDetail=Review the log if you wish, then click Next to finish and remove the temporary files.
english.PostInstallFailed=Environment setup did not complete.
english.PostInstallFailedDetail=Review the log. When you close, you can remove the incomplete files or keep them for diagnosis.
english.PostInstallCleanupFailed=The runtime was configured, but not all temporary files could be removed.
english.PostInstallCleanupFailedDetail=Close Setup and check for files in use or permission issues. Available diagnostic evidence will be preserved.
english.ConfirmCancelSetup=Environment setup is still running.%n%nIf you cancel now, verification will be stopped and the incomplete installation will be removed.%n%nDo you want to cancel?
english.CancellingSetup=Cancelling and stopping processes...
english.CancelCleanup=The user cancelled the installation. Cleaning up...
english.CloseButton=Close
english.FailedKeepFiles=Setup did not complete.%n%nDo you want to remove the incomplete files?%n%nYes = remove everything%nNo = keep them for diagnosis (you can uninstall later)
english.ReadyMemoIntro=Setup will perform the following:
english.ReadyMemoComponents=Components that will be configured:
english.ReadyMemoTime=After copying files, Setup will configure environment variables and verify a local SparkSession. Internet is not required. When it finishes you must click Next.
english.NeedPowerShell={#MyAppName} requires Windows PowerShell 5.1 to install.
english.PostInstallStartFailed=Could not start environment setup.
english.PostInstallLogCopied=Copying files...
english.PostInstallLogTruncated=The log is too long to display here. See install.log in the installation logs folder.
english.UninstallCaption=Uninstalling {#MyAppName}
english.UninstallDescription=Removing the environment and showing details in real time.
english.ReplaceExistingCaption=Replace existing installation
english.ReplaceExistingDescription={#MyAppName} is already installed on this computer.
english.ReplaceExistingBody={#MyAppName} %1 was found at:%n%n%2%n%nThis installer will replace it in that same folder with version %3. A second copy is not supported.%n%nIf you need a different folder, click Cancel, uninstall from Apps & features, then run Setup again.
english.ReplaceExistingUnknownVersion=a previous version
english.ReplaceDirLocked={#MyAppName} is already installed. It must be replaced at:%n%n%1
english.ReplacePrivilegeMismatch={#MyAppName} is already installed %1:%n%n%2%n%nUninstall that copy from Apps & features, then run this installer again. A second copy is not supported.
english.ReplacePrivilegeAllUsers=for all users
english.ReplacePrivilegeCurrentUser=for the current user
english.ReplaceReadyNote=The existing installation will be replaced in the same folder. A second copy will not be created.
english.ReplaceMissingLocation=(location not recorded)
english.ReplaceUnknownDir={#MyAppName} is already registered as installed, but Setup could not determine the folder. Uninstall it from Apps & features, then run this installer again.

[Code]
#include "wizard-code.iss"

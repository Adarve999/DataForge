# Desarrollo y release

Este documento define el flujo de trabajo actual para modificar y validar
DataForge. Describe el proceso disponible en el repositorio; no implica
que exista automatización CI ni certificación de release.

## 1. Prerrequisitos locales

Para construir el instalador se necesita:

- Windows 10/11 x64;
- Windows PowerShell 5.1 o posterior;
- Inno Setup 6.3+ o 7 (`ISCC.exe`);
- acceso a Internet;
- `curl.exe`, `tar` y `Expand-Archive`;
- espacio suficiente para staging, el prefijo CPython de build y el ejecutable
  resultante.

La post-instalación necesita una ruta de prueba no productiva con el payload
de staging (incluido `python/`). No requiere red. No se debe usar un Python
ajeno como destino de las pruebas.

## 2. Principios antes de cambiar código

1. Leer la [Constitución](CONSTITUTION.md), el documento de arquitectura
   relevante y el archivo fuente antes de modificarlo.
2. Mantener `config/versions.json` como fuente de los valores vivos.
3. Reutilizar los helpers de `installer/scripts/common.ps1` para rutas, logs,
   procesos y `PATH`.
4. Delimitar las mutaciones al directorio de prueba y al usuario de prueba.
5. Documentar cualquier cambio de contrato, efecto externo, limitación o
   resultado de prueba en el mismo cambio.

## 3. Flujo de build

Desde la raíz:

```powershell
cd installer

# 1. Descargar dependencias y preparar staging, sin compilar el .exe.
.\build-installer.ps1 -SkipCompile

# 2. Validar la post-instalación sobre una copia o instalación de prueba.
.\test-post-install.ps1 -InstallRoot C:\testing

# 3. Compilar usando el staging ya validado.
.\build-installer.ps1 -SkipDownload
```

Opciones relevantes:

```powershell
# Indicar explícitamente el compilador de Inno Setup.
.\build-installer.ps1 -InnoSetupCompiler "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

# Recompilar solo si el staging completo ya existe.
.\build-installer.ps1 -SkipDownload
```

`-SkipDownload` no evita las comprobaciones: el script exige los binarios,
configuración, scripts, `LICENSE.txt` y `python\python.exe` que conforman
un staging válido.

Si ISCC aborta con `EndUpdateResource failed (110)` al actualizar iconos de
`Setup.exe`, el antivirus (con frecuencia Windows Defender) ha bloqueado el
ejecutable recién creado. El staging no se invalida: recompila con
`-SkipDownload`. El build reintenta esa clase de fallo. Para evitarlo,
excluye `installer/dist/` del análisis en tiempo real.

Si se borra `installer/downloads/python-root` a mano, o se mueve el repo,
Windows Installer puede seguir creyendo que CPython de la versión del
manifiesto está instalado. Un `/quiet` nuevo sale con código 0 y no escribe
archivos (acción Modify). El build repara el prefijo cuando
`HKCU\Software\Python\PythonCore\<mayor.menor>\InstallPath` apunta a la ruta
de build actual. Si el registro apunta a otro
`installer\downloads\python-root` (clone o nombre de repo anterior), o
`python.exe` ya no está ahí, restaura primero ese prefijo con `/repair`
(el MSI de pip aborta `/uninstall` con 1603 si no detecta un Python) y
después desinstala e instala en la ruta actual. No toca un Python ajeno
con archivos presentes en otra carpeta. Tras reparar o reinstalar, exige
`python.exe` y el módulo `pip` (`ensurepip` si falta).

`test-post-install.ps1` no prepara el directorio de prueba. Antes de usarlo,
la ruta indicada debe contener el runtime (Java, Spark, winutils y Python).
Los scripts se toman del repo; `versions.json` se busca en
`{InstallRoot}\config` o, si falta, en el manifiesto del repo. Esta utilidad
no ejecuta la limpieza final del wizard y por tanto conserva `logs/` para
inspección.

## 4. Cambiar versiones o fuentes externas

Al editar `config/versions.json`:

1. actualizar la combinación completa de componentes, no solo una versión
   aislada;
2. confirmar que cada URL, nombre de archivo, directorio interno y ruta de
   winutils siguen siendo correctos;
3. evaluar compatibilidad de Java, Spark, PySpark, ipykernel, Python y winutils;
4. regenerar `README.md` y `README_developers.md` con
   `.\config\Update-Readme.ps1` (no editar esas fichas a mano);
5. ejecutar el build desde cero sin `-SkipDownload`;
6. instalar y verificar el resultado en una ruta de prueba;
7. actualizar el estado, la especificación y las decisiones si cambia una
   restricción o política.

Las URLs que resuelven a recursos mutables no garantizan que dos builds
produzcan el mismo artefacto. Hasta que se implementen hashes o pinning, la
validación del payload descargado forma parte de la responsabilidad de release.

## 5. Cambiar PowerShell, Inno Setup o launchers

| Área modificada | Validación mínima |
| --- | --- |
| `installer/scripts/*.ps1` | Preparar staging, ejecutar post-instalación en ruta de prueba y comprobar efectos de `PATH` |
| `installer/build-installer.ps1` | Preparar staging desde cero y comprobar los archivos requeridos |
| `installer/*.iss` | Compilar `.exe`, recorrer wizard y validar desinstalación |
| Accesos directos de Inno Setup | Ejecutar Apache Spark shell y Python privado desde rutas con espacios y una terminal nueva |
| `config/versions.json` | Build desde cero, post-instalación, smoke test de Spark y `.\config\Update-Readme.ps1` |
| `config/*.template.md` | Regenerar fichas y comprobar que no quedan placeholders |

Para scripts PowerShell, conservar `Set-StrictMode -Version Latest`,
`$ErrorActionPreference = 'Stop'` y mensajes de error que permitan encontrar el
log. En Inno Setup, mantener coherentes los textos en español e inglés y el
protocolo de progreso/cancelación del wizard.

## 6. Matriz mínima de validación manual

No hay una suite automatizada que cubra estos escenarios. Antes de un release,
registrar cuáles se ejecutaron y su resultado.

| Escenario | Resultado esperado |
| --- | --- |
| Build limpio | Staging completo y ejecutable creado en `installer/dist/` |
| Instalación limpia | Durante la copia y la post-instalación, `{app}` no contiene `scripts/` ni `config/`; el log se conserva hasta avanzar desde la pantalla de éxito; después la raíz contiene `java/`, `spark/`, `hadoop/`, `python/`, `LICENSE.txt` y `unins*` |
| Python ajeno presente | No se modifica su configuración, no se escribe `PythonCore` ni se registra el lanzador `py.exe` |
| Descubrimiento VS Code / Jupyter | `HKCU\Software\Python\<producto>` y `%APPDATA%\jupyter\kernels\<producto>` apuntan a `{app}\python\python.exe` |
| Sin red | La post-instalación completa con código cero: runtime Python copiado, `SparkSession` y layout final |
| Cancelación del wizard | Se detiene la post-instalación y se ejecuta la limpieza configurada |
| Fallo durante la configuración | El wizard muestra el error, deja cerrar la ventana y pregunta si se conservan los archivos incompletos |
| Accesos directos | Apache Spark shell y Python privado abren una sesión con Java, Spark, Hadoop y el CPython correctos |
| Nueva terminal | `spark-shell` se resuelve desde cualquier directorio y todas las entradas propias del `PATH` son rutas absolutas, sin `%VARIABLE%` heredadas |
| Desinstalación | Elimina recursos propios sin borrar un Python ajeno |
| Reinstalación, mismo privilegio | Reemplaza la carpeta existente; no se puede elegir otra; el `PATH` no acumula la raíz anterior |
| Reinstalación, otro privilegio | El Setup aborta y pide desinstalar la copia existente |
| `/DIR=` distinto con copia previa | Se ignora y se usa la carpeta ya instalada |

El smoke test funcional esperado equivale al que ejecuta
[`verify-install.ps1`](../installer/scripts/verify-install.ps1):

```powershell
python -c "import ipykernel; print(ipykernel.__version__)"
python -c "from pyspark.sql import SparkSession; spark = SparkSession.builder.getOrCreate(); print(spark.version); spark.stop()"
```

## 7. Checklist de release

Antes de distribuir un ejecutable:

- [ ] La versión y las fuentes de `config/versions.json` fueron revisadas.
- [ ] El build desde cero terminó correctamente.
- [ ] El staging validado contiene todos los archivos requeridos.
- [ ] La post-instalación se probó sobre una ruta limpia.
- [ ] `verify-install.ps1` confirmó `ipykernel`, el registro PEP 514 propio, el
      kernelspec de usuario y una `SparkSession` local.
- [ ] Los accesos directos de Apache Spark shell y Python se comprobaron desde una ruta con espacios.
- [ ] `where spark-shell` resuelve el binario bajo el directorio de instalación.
- [ ] `LICENSE.txt` lista las mismas versiones que `config/versions.json` y se muestra como contrato de licencia del wizard.
- [ ] Tras finalizar el wizard, la raíz solo contiene los cuatro directorios de runtime, `LICENSE.txt` y `unins*`.
- [ ] Las entradas de `PATH` de DataForge son rutas absolutas y la
      desinstalación elimina también las formas heredadas `%VARIABLE%`.
- [ ] Reinstalar sobre una copia del mismo privilegio sustituye esa carpeta;
      `/DIR=` distinto no crea un segundo árbol; una copia en el otro
      privilegio se rechaza.
- [ ] La desinstalación se probó y no dejó efectos propios conocidos, incluido
      el registro PEP 514 y el kernelspec de usuario.
- [ ] Se registró la evidencia de las pruebas y las limitaciones restantes en
      [Estado del proyecto](PROJECT_STATUS.md).
- [ ] Se actualizaron la especificación, decisiones y, si cambió un contrato
      o flujo de uso, las plantillas de `config/` (después
      `.\config\Update-Readme.ps1`).
- [ ] El nombre del artefacto y la versión publicada coinciden con el
      manifiesto.

## 8. Diagnóstico y recuperación

Durante una post-instalación fallida, el wizard conserva `logs/` y el runtime
copiado dentro del directorio de instalación. `scripts/` y `config/` no se
escriben en `{app}`. El archivo principal de diagnóstico es `logs/install.log`.

Al investigar:

1. conservar el directorio fallido antes de volver a ejecutar la instalación;
2. revisar el último comando y su código de salida en el log;
3. comprobar espacio, permisos, Java, Spark, winutils y el Python privado;
4. registrar el resultado y, si aplica, un riesgo o decisión en la
   documentación viva.

## 9. Estado de automatización

Actualmente el proyecto no contiene CI/CD, PSScriptAnalyzer, Pester, formatter,
pre-commit ni firma de artefactos. Introducir cualquiera de estas herramientas
debe tratarse como una mejora deliberada: definir su entorno Windows, sus
criterios de fallo, la fuente de artefactos y cómo actualiza este procedimiento.

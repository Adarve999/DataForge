# {{productName}} — desarrollo

[![{{productName}}](https://img.shields.io/badge/{{productName}}-{{productVersion}}-2563eb)](docs/PROJECT_SPECIFICATION.md)
[![Eclipse Temurin {{javaMajorVersion}}](https://img.shields.io/badge/Eclipse%20Temurin-{{javaMajorVersion}}-ed8b00?logo=openjdk&logoColor=white)](https://adoptium.net/)
[![Python {{pythonVersion}}](https://img.shields.io/badge/Python-{{pythonVersion}}-3776ab?logo=python&logoColor=white)](https://www.python.org/)
[![Apache Spark {{sparkVersion}}](https://img.shields.io/badge/Apache%20Spark-{{sparkVersion}}-e25a1c)](https://spark.apache.org/)
[![PySpark {{pysparkVersion}}](https://img.shields.io/badge/PySpark-{{pysparkVersion}}-e25a1c)](https://spark.apache.org/docs/latest/api/python/)
[![{{platform}}](https://img.shields.io/badge/Windows-{{platformBadgeMessage}}-0078d6?logo=windows&logoColor=white)](https://www.microsoft.com/windows/)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391fe?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)

Guía técnica para construir y modificar el instalador. La ficha pública de
descarga es [`README.md`](README.md); no edites a mano ni esa ficha ni esta:
salen de `config/*.template.md` y [`config/versions.json`](config/versions.json).

**{{productName}}, powered by Apache Spark** es un instalador comunitario
**solo para Windows**. No está afiliado a The Apache Software Foundation.
Deja un runtime local de Apache Spark operativo desde cero, con el stack
del manifiesto:

| Componente | Versión |
|------------|---------|
| Java (Eclipse Temurin) | `{{javaMajorVersion}}` |
| Apache Spark | `{{sparkVersion}}` |
| PySpark | `{{pysparkVersion}}` |
| ipykernel | `{{ipykernelVersion}}` |
| winutils (Hadoop) | `{{hadoopWinutilsVersion}}` (`bin/`) |
| CPython oficial | `{{pythonVersion}}` |

Tras cambiar el manifiesto, regenera las fichas:

```powershell
.\config\Update-Readme.ps1
```

## Índice

- [Documentación para desarrollo](#documentación-para-desarrollo)
- [Qué hace el instalador](#qué-hace-el-instalador)
- [Requisitos para construir el instalador](#requisitos-para-construir-el-instalador)
- [Construir el instalador](#construir-el-instalador)
- [Instalación para el usuario final](#instalación-para-el-usuario-final)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Variables de entorno configuradas](#variables-de-entorno-configuradas)
- [Logs y diagnóstico](#logs-y-diagnóstico)
- [Desinstalación](#desinstalación)
- [Personalizar versiones](#personalizar-versiones)
- [Notas](#notas)

## Documentación para desarrollo

La documentación viva del proyecto está en [`docs/`](docs/README.md):

- [Especificación](docs/PROJECT_SPECIFICATION.md), [arquitectura](docs/ARCHITECTURE.md)
  y [constitución](docs/CONSTITUTION.md) definen los contratos e invariantes.
- [Estado](docs/PROJECT_STATUS.md), [decisiones](docs/DECISIONS.md) y
  [desarrollo/release](docs/DEVELOPMENT_AND_RELEASE.md) reflejan la situación
  verificada y el procedimiento de trabajo.

La jerarquía es: configuración y código como evidencia ejecutable; la
especificación como contrato; el estado como fotografía factual. Para agentes
de Cursor, [`AGENTS.md`](AGENTS.md) actúa como índice y
[`.cursor/rules/`](.cursor/rules/) contiene reglas breves que remiten a estos
documentos.

## Qué hace el instalador

1. Copia Eclipse Temurin, Apache Spark, winutils de Apache Hadoop y un CPython oficial con PySpark e ipykernel en `{InstallDir}` (por defecto `{{defaultInstallDir}}`).
2. No modifica un Python ajeno ni registra el lanzador `py.exe`.
3. Configura variables de usuario: `{{homeVar}}`, `JAVA_HOME`, `SPARK_HOME`, `HADOOP_HOME`, `PYSPARK_PYTHON`, etc.
4. Verifica que `pyspark` arranca con Apache Spark local y que `ipykernel` se importa. No necesita Internet.
5. Crea accesos directos a **Apache Spark shell** y **{{pythonShortcut}}**.
6. Si todo va bien, conserva el log hasta que pulses **Siguiente** y después elimina `logs/`. Los scripts de instalación no se copian a la carpeta del producto.

Tras una instalación correcta, la raíz contiene `java/`, `spark/`, `hadoop/`,
`python/`, `LICENSE.txt` y los archivos técnicos `unins*` de Inno Setup
necesarios para desinstalar. `LICENSE.txt` se genera durante el build desde
`config/versions.json`: lista las versiones de esa copia, el copyright y la
licencia de cada componente (Temurin/OpenJDK, Spark, PySpark, Hadoop
winutils, CPython e ipykernel) y apunta a los textos completos dentro de
`java/`, `spark/` y `python/`. El wizard lo muestra como contrato de licencia.

## Requisitos para construir el instalador

- {{platform}} x64
- PowerShell 5.1+
- [Inno Setup 7](https://jrsoftware.org/isinfo.php) (también compatible con 6.3+; necesario para mostrar el log en tiempo real)
- Conexión a internet (para descargar dependencias durante el build)

## Construir el instalador

Orden recomendado:

1. **Staging** — descarga y empaqueta componentes (`build-installer.ps1 -SkipCompile`)
2. **Probar post-instalación** — validar scripts antes de compilar el `.exe`
3. **Compilar `.exe`** — Inno Setup, cuando todo funcione

Desde la raíz del repo:

```powershell
cd installer
.\build-installer.ps1 -SkipCompile
```

Probar post-instalación en una carpeta (por ejemplo tras copiar staging o tras instalar manualmente):

```powershell
.\test-post-install.ps1 -InstallRoot C:\testing
```

Cuando la post-instalación pase, generar el instalador:

```powershell
.\build-installer.ps1 -SkipDownload
```

El `.exe` quedará en `installer/dist/`, con el nombre generado a partir de `productVersion`
(`{{setupName}}` con el manifiesto actual).

Opciones útiles:

```powershell
# Solo recompilar (staging ya preparado)
.\build-installer.ps1 -SkipDownload

# Solo descargar/preparar staging, sin compilar
.\build-installer.ps1 -SkipCompile

# Ruta custom de ISCC.exe
.\build-installer.ps1 -InnoSetupCompiler "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
```

## Instalación para el usuario final

1. Ejecutar el `.exe` generado en `installer/dist/`.
2. Esperar a que termine la copia de archivos y la verificación de Spark. No se necesita Internet.
3. Abrir una **nueva** terminal o usar el acceso directo **Apache Spark shell**.
4. Probar:

```powershell
pyspark
```

O desde el acceso directo **{{pythonShortcut}}**:

```powershell
python -c "import ipykernel; print(ipykernel.__version__)"
python -c "from pyspark.sql import SparkSession; spark = SparkSession.builder.getOrCreate(); print(spark.version); spark.stop()"
```

El runtime Python vive en `{InstallDir}\python` e incluye `ipykernel`. La
post-instalación registra ese `python.exe` para VS Code y Jupyter (PEP 514
propio y un kernelspec de usuario). No registra el lanzador `py.exe` ni escribe
en `PythonCore`. Paquetes adicionales se instalan con `python -m pip` y pueden
requerir red.

## Estructura del proyecto

```
{{productName}}/
├── .cursor/
│   └── rules/                     # Instrucciones versionadas para Cursor Agent
├── AGENTS.md                      # Índice de contexto para agentes
├── config/
│   ├── versions.json              # Versiones y URLs de descarga
│   ├── README.template.md         # Ficha pública
│   ├── README_developers.template.md
│   └── Update-Readme.ps1          # Regenera README.md y README_developers.md
├── docs/                          # Especificación, arquitectura y operación
├── installer/
│   ├── build-installer.ps1        # Build: descarga + staging + ISCC
│   ├── {{productName}}.iss              # Script Inno Setup
│   ├── wizard-code.iss            # UI del wizard y post-instalación
│   ├── test-post-install.ps1      # Post-instalación sin recompilar el .exe
│   ├── assets/                    # Icono y bitmaps del wizard
│   ├── scripts/                   # Post-install, verificación, desinstalación
│   ├── staging/                   # (generado) contenido del instalador
│   ├── downloads/                 # (generado) archivos descargados
│   └── dist/                      # (generado) instalador .exe
├── README.md                      # Ficha pública (generada)
└── README_developers.md           # Esta guía (generada)
```

## Variables de entorno configuradas

| Variable | Valor |
|----------|-------|
| `{{homeVar}}` | Directorio de instalación |
| `JAVA_HOME` | `{InstallDir}\java` |
| `SPARK_HOME` | `{InstallDir}\spark` |
| `HADOOP_HOME` | `{InstallDir}\hadoop` |
| `PYSPARK_PYTHON` | `{InstallDir}\python\python.exe` |
| `PYSPARK_DRIVER_PYTHON` | Igual que `PYSPARK_PYTHON` |

Todas las rutas que {{productName}} añade al `PATH` de usuario se guardan como
rutas absolutas bajo `{InstallDir}`: Eclipse Temurin, Apache Spark, Apache
Hadoop y el directorio de CPython. Esto evita que Windows conserve
referencias anidadas como `%SPARK_HOME%\bin` sin expandir y no pueda
resolver comandos. El instalador y el desinstalador también retiran las
referencias heredadas con `%…%` y, al reemplazar, las rutas de un
`{{homeVar}}` anterior. Tras instalar, abre una terminal nueva para
que el `PATH` actualizado esté disponible.

Si {{productName}} (o una copia anterior del mismo `AppId`) ya está
instalado, el Setup lo reemplaza en la misma carpeta. No instala una
segunda copia. Para cambiar de ubicación, desinstala primero desde
**Agregar o quitar programas**. Si la copia existente es de otro ámbito
(usuario actual frente a todos los usuarios), el instalador se detiene y
pide desinstalarla.

## Logs y diagnóstico

- Durante la post-instalación, el instalador muestra un log en tiempo real junto a la barra de progreso.
- En la pantalla de éxito, `logs/install.log` sigue disponible hasta pulsar **Siguiente**; entonces se elimina `logs/`.
- Si falla, se conservan `logs/` y el runtime copiado para poder diagnosticar el problema. Los scripts no quedan en la carpeta de instalación.

## Desinstalación

Usar **Agregar o quitar programas**. El desinstalador muestra en su propia ventana el
log de limpieza, elimina las variables de entorno, las entradas simbólicas y antiguas
del `PATH`, el registro PEP 514 propio, el kernelspec de usuario, el CPython privado y el contenido de la instalación (`java`,
`spark`, `hadoop`, `python` y `LICENSE.txt`). No elimina ni modifica otras
instalaciones de Python.

## Personalizar versiones

Edita `config/versions.json`, regenera las fichas (`.\config\Update-Readme.ps1`)
y vuelve a ejecutar `build-installer.ps1`. El build propaga esos valores al
script de Inno Setup, a `LICENSE.txt` y a la post-instalación.

## Notas

- El payload incluye Eclipse Temurin, Apache Spark y un CPython con PySpark;
  el tamaño del instalador depende de esa combinación y de la compresión LZMA.
- El build necesita Internet (descargas y PyPI). La instalación en el PC no.
- `HADOOP_HOME` apunta a la carpeta que contiene `bin\winutils.exe`.
- {{productName}} no está afiliado a The Apache Software Foundation, Eclipse
  Foundation AISBL ni Python Software Foundation. Apache Spark™ y Spark™
  son marcas de la ASF. Ver [marcas de Apache Spark](https://spark.apache.org/trademarks.html).
- El código original del instalador se publica bajo la licencia MIT del
  archivo `LICENSE` de la raíz. Los componentes empaquetados conservan
  las suyas.

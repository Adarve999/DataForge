# {{productName}}

[![{{productName}}](https://img.shields.io/badge/{{productName}}-{{productVersion}}-2563eb)]({{latestUrl}})
[![Eclipse Temurin {{javaMajorVersion}}](https://img.shields.io/badge/Eclipse%20Temurin-{{javaMajorVersion}}-ed8b00?logo=openjdk&logoColor=white)](https://adoptium.net/)
[![Python {{pythonVersion}}](https://img.shields.io/badge/Python-{{pythonVersion}}-3776ab?logo=python&logoColor=white)](https://www.python.org/)
[![Apache Spark {{sparkVersion}}](https://img.shields.io/badge/Apache%20Spark-{{sparkVersion}}-e25a1c)](https://spark.apache.org/)
[![PySpark {{pysparkVersion}}](https://img.shields.io/badge/PySpark-{{pysparkVersion}}-e25a1c)](https://spark.apache.org/docs/latest/api/python/)
[![{{platform}}](https://img.shields.io/badge/Windows-{{platformBadgeMessage}}-0078d6?logo=windows&logoColor=white)](https://www.microsoft.com/windows/)

**{{productName}}, powered by Apache Spark** es un instalador comunitario para
{{platform}}. No está afiliado a The Apache Software Foundation. Deja un
runtime local de Apache Spark listo para usar.

Este repositorio publica las versiones. El instalador y las notas de cada
entrega están en [Releases]({{releasesUrl}}).

## Índice

- [Descargar](#descargar)
- [Componentes](#componentes)
- [Qué hace el instalador](#qué-hace-el-instalador)
- [Comprobar](#comprobar)
- [Variables de entorno](#variables-de-entorno)
- [Logs](#logs)
- [Desinstalación](#desinstalación)
- [Licencia y marcas](#licencia-y-marcas)

## Descargar

1. Abre la [última Release]({{latestUrl}}).
2. Descarga `{{setupGlob}}`.
3. Ejecútalo. No hace falta Internet durante la instalación.
4. Abre una **nueva** terminal o el acceso directo **Apache Spark shell**.

## Componentes

La tabla refleja la entrega **{{productVersion}}** anunciada en este README.
Cada [Release]({{releasesUrl}}) puede traer otras versiones; en ese caso
prevalece la tabla de esa entrega.

| Componente | Versión |
|------------|---------|
| Java (Eclipse Temurin) | {{javaMajorVersion}} |
| Apache Spark | {{sparkVersion}} |
| PySpark | {{pysparkVersion}} |
| ipykernel | {{ipykernelVersion}} |
| winutils (Hadoop) | {{hadoopWinutilsVersion}} |
| CPython oficial | {{pythonVersion}} |

## Qué hace el instalador

Copia un runtime autocontenido en `{InstallDir}` (por defecto
`{{defaultInstallDir}}`):

- Eclipse Temurin, Apache Spark, winutils de Apache Hadoop y un CPython
  oficial con PySpark e ipykernel
- Variables de usuario: `{{homeVar}}`, `JAVA_HOME`, `SPARK_HOME`,
  `HADOOP_HOME`, `PYSPARK_PYTHON` y `PYSPARK_DRIVER_PYTHON`
- Accesos directos **Apache Spark shell** y **{{pythonShortcut}}**
- Comprobación de que `pyspark` arranca en local y de que `ipykernel`
  se importa

No modifica un Python ajeno ni registra `py.exe`. Si el producto ya
está instalado, el Setup lo reemplaza en la misma carpeta. Para cambiar
de ubicación, desinstala primero desde **Agregar o quitar programas**.

Tras instalar, la raíz contiene `java/`, `spark/`, `hadoop/`,
`python/` y `LICENSE.txt` (versiones y licencias de esa copia).

## Comprobar

```powershell
pyspark
```

O desde el acceso directo **{{pythonShortcut}}**:

```powershell
python -c "import ipykernel; print(ipykernel.__version__)"
python -c "from pyspark.sql import SparkSession; spark = SparkSession.builder.getOrCreate(); print(spark.version); spark.stop()"
```

El runtime Python vive en `{InstallDir}\python`. Los paquetes extra se
instalan con `python -m pip` y pueden requerir red.

## Variables de entorno

| Variable | Valor |
|----------|-------|
| `{{homeVar}}` | Directorio de instalación |
| `JAVA_HOME` | `{InstallDir}\java` |
| `SPARK_HOME` | `{InstallDir}\spark` |
| `HADOOP_HOME` | `{InstallDir}\hadoop` |
| `PYSPARK_PYTHON` | `{InstallDir}\python\python.exe` |
| `PYSPARK_DRIVER_PYTHON` | Igual que `PYSPARK_PYTHON` |

Las rutas que {{productName}} añade al `PATH` de usuario son absolutas bajo
`{InstallDir}`. Tras instalar, abre una terminal nueva.

## Logs

- Durante la post-instalación el instalador muestra un log en tiempo real.
- Si todo va bien, el log sigue visible hasta pulsar **Siguiente** y
  después se elimina `logs/`.
- Si falla, se conservan `logs/` y el runtime copiado.

## Desinstalación

Usa **Agregar o quitar programas**. El desinstalador elimina las
variables de entorno, las entradas propias del `PATH`, el registro
PEP 514 propio, el kernelspec de usuario, el CPython privado y el
contenido de la instalación. No toca otras instalaciones de Python.

## Licencia y marcas

- El `.exe` incluye el runtime; el tamaño es grande (cientos de MiB).
- `HADOOP_HOME` apunta a la carpeta que contiene `bin\winutils.exe`.
- {{productName}} no está afiliado a The Apache Software Foundation, Eclipse
  Foundation AISBL ni Python Software Foundation. Apache Spark™ y Spark™
  son marcas de la ASF. Ver [marcas de Apache Spark](https://spark.apache.org/trademarks.html).
- El instalador se publica bajo la licencia MIT del archivo `LICENSE`
  de este repositorio. Los componentes empaquetados conservan las suyas.

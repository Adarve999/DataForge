# Especificación del producto

## 1. Identidad y objetivo

**DataForge** entrega un instalador Windows que deja operativo un entorno
local de Apache Spark. El instalador empaqueta las dependencias binarias de base y
un CPython oficial con PySpark e ipykernel preinstalados; durante la post-instalación
configura el entorno de usuario y verifica el runtime, sin resolver paquetes
en red.

El entregable del proyecto es un ejecutable de instalación generado por Inno
Setup, no una aplicación Python ni una librería para construir pipelines de
datos.

## 2. Alcance

El producto debe:

- preparar Java, Apache Spark y `winutils` dentro del directorio elegido para la
  instalación;
- copiar un CPython privado, aislado de instalaciones Python ajenas;
- incluir las versiones de PySpark e ipykernel indicadas, resueltas en el build;
- configurar las variables de entorno de usuario necesarias para ejecutar
  PySpark y registrar el CPython privado para que VS Code y Jupyter lo
  descubran, sin registrar `py.exe` ni tocar un Python ajeno;
- ofrecer accesos directos y launchers para Apache Spark shell y el Python privado;
- comprobar que Java, Spark, `ipykernel` y una `SparkSession` local funcionan antes de
  completar con éxito la post-instalación;
- si ya hay una instalación del mismo `AppId` en el mismo ámbito de
  privilegios, reemplazarla en esa carpeta y no crear una segunda copia;
- eliminar únicamente los recursos que pertenecen a DataForge al
  desinstalar.

No forma parte del alcance actual:

- crear o ejecutar jobs, notebooks, modelos o pipelines de PySpark;
- soportar Linux, macOS, arquitecturas que no sean x64 o instalaciones
  multiusuario;
- administrar instalaciones globales de Python, ni registrar el
  lanzador `py.exe` ni escribir en `PythonCore`;
- ofrecer `pip install` u otras descargas posteriores a la instalación como
  un flujo sin red;
- ejecutar `ipykernel install` (el nombre genérico `python3`), ni entregar
  JupyterLab o Notebook como aplicación;
- ofrecer reparación tipo Windows (Modify/Repair), coexistir dos copias o
  gestionar dependencias adicionales como un contrato formal.

## 3. Entorno soportado

| Área | Contrato actual |
| --- | --- |
| Sistema operativo | Windows 10/11 x64 |
| Instalación | Inno Setup, con PowerShell 5.1 disponible |
| Construcción | PowerShell, `curl.exe`, `tar`, `Expand-Archive`, Internet e Inno Setup 6.3+ o 7 |
| Red | Necesaria durante el build para descargas y PyPI. La instalación en el PC no requiere red |
| Permisos | La instalación intenta usar privilegios mínimos; las rutas protegidas pueden requerir permisos adicionales para modificar el entorno posteriormente |

Las versiones verificables y URLs de descarga viven en
[`config/versions.json`](../config/versions.json). El código no debe
introducir versiones paralelas en scripts, documentos o reglas.

## 4. Componentes del producto

| Componente | Origen y responsabilidad |
| --- | --- |
| Java | Descargado y empaquetado durante el build; se instala bajo `java/` |
| Apache Spark | Descargado y extraído durante el build; se instala bajo `spark/` |
| winutils | Extraído durante el build; se instala bajo `hadoop/bin/` |
| CPython | Instalador oficial de python.org usado solo en el build; el prefijo se copia bajo `python/` |
| PySpark | Se instala con `pip` durante el build dentro de ese prefijo |
| ipykernel | Se instala con `pip` durante el build en el mismo prefijo; la post-instalación escribe un kernelspec de usuario con ruta absoluta y no ejecuta `ipykernel install` |
| Accesos directos | Inno Setup abre Apache Spark shell o el Python privado sin conservar wrappers bajo `bin/` |

## 5. Contrato de configuración

`config/versions.json` es el manifiesto ejecutable del producto. Contiene:

| Grupo | Campos | Uso |
| --- | --- | --- |
| Producto | `productName`, `productVersion` | Metadatos y nombre del instalador generado |
| Compatibilidad | `sparkVersion`, `pysparkVersion`, `ipykernelVersion`, `hadoopWinutilsVersion`, `javaMajorVersion`, `pythonVersion` | Selección coherente del stack |
| Descargas | `downloads.spark`, `downloads.java`, `downloads.winutils`, `downloads.python` | URLs, nombres de archivo, rutas y estructura de extracción |

Al cambiar este archivo se debe:

1. comprobar que las combinaciones de Java, Spark, PySpark, ipykernel, Python y winutils
   son compatibles;
2. comprobar que las URLs, nombres de archivo y rutas internas del archivo
   descargado siguen siendo válidos;
3. ejecutar de nuevo la preparación de staging, pues el build regenera el
   prefijo Python y propaga estos valores a Inno Setup;
4. validar una instalación real antes de declarar la combinación soportada.

El manifiesto describe entradas de descarga, pero no implementa actualmente
checksums ni un schema JSON validado automáticamente. Esta es una limitación
conocida, no una garantía de integridad.

Durante el build se generan `LICENSE.es.txt` y `LICENSE.en.txt` a partir de
este manifiesto. Cada uno es un aviso de copyright y licencias de los
componentes empaquetados (estilo NOTICE de Apache Spark). El texto propio de
DataForge sigue el idioma del archivo; las licencias de terceros permanecen
en su idioma original. El wizard muestra el aviso del idioma elegido y lo
instala junto al runtime como `LICENSE.txt`. No es otra fuente canónica de
versiones; las licencias completas viajan dentro de `java/`, `spark/` y
`python/`.

## 6. Contrato de build

La única entrada de build soportada es
[`installer/build-installer.ps1`](../installer/build-installer.ps1). El script:

1. lee el manifiesto de configuración;
2. descarga Java, Spark, winutils y el instalador oficial de Python, instala
   CPython en un prefijo de build y ejecuta `pip install pyspark` e
   `ipykernel`, salvo que se indique `-SkipDownload`;
3. construye `installer/staging/` con el payload que copiará el instalador,
   incluido `staging/python`;
4. valida el staging existente cuando se omite la descarga;
5. sincroniza configuración y scripts en staging (el `.exe` los extrae a
   `{tmp}`, no a `{app}`), y genera `LICENSE.es.txt` y `LICENSE.en.txt`;
6. invoca `ISCC.exe` con los defines derivados de la configuración, salvo que
   se indique `-SkipCompile`.

[`installer/DataForge.iss`](../installer/DataForge.iss) no debe
compilarse directamente: requiere defines suministrados por el script de build.
El artefacto esperado se genera en `installer/dist/` y los directorios de
staging, descargas y salida son artefactos reproducibles no versionados.

## 7. Contrato de instalación

El producto admite una sola copia por ámbito de privilegios (usuario actual o
todos los usuarios). Antes de copiar archivos, el wizard consulta la clave de
desinstalación del `AppId` en `HKCU` y `HKLM`:

- si hay una instalación en el **otro** ámbito, el Setup aborta y exige
  desinstalar esa copia desde Agregar o quitar programas;
- si hay una instalación en el **mismo** ámbito, la reemplaza en esa carpeta:
  omite la página de directorio, ignora `/DIR=` distinto y muestra que se
  sustituye la copia existente;
- si no hay registro de desinstalación pero `DATAFORGE_HOME` apunta a una
  carpeta que existe, esa carpeta es el destino de reemplazo;
- si el registro existe y no se puede determinar la carpeta, el Setup aborta
  y exige desinstalar.

No se crea un segundo árbol. Para cambiar de carpeta hay que desinstalar y
volver a instalar. La post-instalación retira del `PATH` de usuario las
entradas bajo el hogar anterior (`DATAFORGE_HOME`) cuando esa raíz no
coincide con la instalación actual, además de las formas heredadas
`%VARIABLE%`.

Después de que Inno Setup copie el runtime al directorio de instalación, el
wizard extrae [`post-install.ps1`](../installer/scripts/post-install.ps1) y
`versions.json` a `{tmp}` e inicia la post-instalación desde ahí. Debe
ejecutar, en este orden:

1. comprobar que existe el `python.exe` privado copiado bajo `python/`;
2. [`setup-env.ps1`](../installer/scripts/setup-env.ps1): configurar
   variables de entorno, entradas del `PATH` de usuario y el descubrimiento
   del CPython privado (PEP 514 propio y kernelspec de usuario);
3. [`verify-install.ps1`](../installer/scripts/verify-install.ps1): verificar
   binarios, Java, descubrimiento del CPython privado, import de `ipykernel` y
   una sesión local de Spark.

La instalación se considera correcta únicamente si esos pasos finalizan con
éxito. `scripts/` y `config/` no se escriben en `{app}`: viven en `{tmp}`
solo mientras corre PowerShell y se borran al terminar ese proceso. En la
ruta gráfica, el wizard conserva `logs/` hasta que la persona usuaria avanza
desde la pantalla de éxito y entonces lo elimina. En modo silencioso
la misma limpieza de `logs/` ocurre después del código cero. Si falla, se
conservan `logs/` y el runtime copiado para diagnóstico.

El árbol final contiene `java/`, `spark/`, `hadoop/`, `python/`,
`LICENSE.txt` y los archivos `unins*` necesarios para desinstalar.

La interacción asíncrona entre el wizard y PowerShell se realiza mediante
archivos de PID, cancelación, progreso, código de salida y log. La cancelación
esperada devuelve el código `1602`; otros fallos devuelven un código no nulo.
Tras un fallo, la ventana debe seguir pudiéndose cerrar: el wizard no espera
de forma indefinida a procesos hijos y, al salir, puede conservar el directorio
para diagnóstico o revertir la copia después de detener el runtime propio.

## 8. Contrato de ejecución

Los accesos directos generados por Inno Setup construyen una sesión de `cmd.exe`
con las rutas del directorio instalado. Después ejecutan `spark/bin/pyspark.cmd`
o el Python privado. No dependen de `config/versions.json` ni de wrappers
permanentes bajo `bin/`.

Además de la sesión del launcher, la instalación persiste las variables de
usuario derivadas de `productName` (`DATAFORGE_HOME`), más `JAVA_HOME`,
`SPARK_HOME`, `HADOOP_HOME`, `PYSPARK_PYTHON` y `PYSPARK_DRIVER_PYTHON`.
`PYSPARK_PYTHON` y `PYSPARK_DRIVER_PYTHON` son las variables que exige
Apache Spark; no son el nombre del producto. Todas las entradas que el
producto añade al `PATH` se persisten como rutas absolutas bajo el
directorio de instalación. Así se evita que Windows conserve referencias
anidadas como `%SPARK_HOME%\bin` literalmente y bloquee la resolución de
comandos. Al actualizar o desinstalar, se retiran las rutas absolutas
propias, las de un hogar anterior si apunta a otra carpeta, y las
referencias heredadas con `%…%`, incluida `%DATAFORGE_HOME%`.

Para que VS Code y Jupyter descubran el CPython copiado, la post-instalación
registra una clave PEP 514 propia (`HKCU\Software\Python\<producto>`, nunca
`PythonCore`) y escribe un kernelspec de usuario cuyo `argv` es
`{InstallDir}\python\python.exe`. No se registra el lanzador `py.exe`.

## 9. Contrato de desinstalación

El flujo activo de desinstalación está implementado en
[`installer/wizard-code.iss`](../installer/wizard-code.iss) y en la sección
`[UninstallDelete]` del archivo principal de Inno Setup. Debe:

- retirar las variables de entorno que creó DataForge, incluida
  `DATAFORGE_HOME`;
- retirar del `PATH` sus entradas propias, incluidas rutas absolutas y
  referencias heredadas;
- retirar el registro PEP 514 propio y el kernelspec de usuario;
- eliminar el CPython privado y el contenido instalado.

El archivo [`uninstall-env.ps1`](../installer/scripts/uninstall-env.ps1) existe
como utilidad PowerShell en el repo, no viaja en el `.exe` y no está invocado
por el `.iss` actual. No debe considerarse una ruta de desinstalación canónica
sin cablearla y validarla.

## 10. Efectos externos y límites de seguridad

DataForge modifica recursos del usuario actual. Estos efectos deben ser
explícitos y reversibles:

- archivos bajo el directorio de instalación;
- variables y registro del usuario actual (`HKCU\Environment` y
  `HKCU\Software\Python\<producto>`);
- kernelspec de usuario bajo `%APPDATA%\jupyter\kernels\<producto>`;
- `PATH` de usuario;
- accesos directos del menú Inicio y, si se selecciona, del escritorio.

La instalación no debe borrar, sobrescribir ni reconfigurar instalaciones
Python ajenas, ni registrar el lanzador `py.exe`, ni escribir en
`PythonCore`.

## 11. Criterios de aceptación

Una entrega puede declararse funcional cuando:

1. `build-installer.ps1` prepara staging sin archivos requeridos ausentes;
2. Inno Setup genera el ejecutable usando los valores de la configuración;
3. una instalación limpia finaliza con código cero;
4. `verify-install.ps1` confirma Java, `winutils`, Spark, el Python privado,
   el registro PEP 514 propio, el kernelspec de usuario, `ipykernel` y una
   `SparkSession` local;
5. los accesos directos y los comandos de PySpark funcionan desde una sesión
   nueva;
6. la desinstalación no deja variables ni rutas propias y no borra un Python
  ajeno;
7. reinstalar sobre una copia del mismo privilegio sustituye esa carpeta y no
  deja una segunda entrada de `PATH`; una copia en el otro privilegio se
  rechaza hasta desinstalarla;
8. el resultado y las limitaciones observadas se registran en
  [Estado del proyecto](PROJECT_STATUS.md).

Los escenarios de prueba mínimos y el procedimiento de release están definidos
en [Desarrollo y release](DEVELOPMENT_AND_RELEASE.md).

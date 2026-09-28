# Decisiones arquitectónicas

Este registro conserva decisiones duraderas. Las entradas iniciales se han
reconstruido a partir de la implementación revisada el 2026-08-20; describen
lo que el proyecto hace hoy, no necesariamente la fecha histórica en la que se
tomó cada decisión.

## Formato para nuevas entradas

```markdown
## D-XXX — Título

- Estado: propuesta | aceptada | sustituida | retirada
- Fecha: AAAA-MM-DD
- Contexto:
- Decisión:
- Consecuencias:
- Evidencia o validación:
```

Una decisión debe añadirse cuando cambie una restricción duradera, se elija
entre alternativas relevantes o se introduzca una incompatibilidad para
instalaciones existentes. Los detalles de implementación menores pertenecen al
código o a la arquitectura.

## D-001 — Configuración centralizada del stack

- **Estado:** aceptada y aplicada.
- **Contexto:** el producto necesita propagar de forma coherente versiones,
  nombres y rutas de descarga a build, installer y runtime.
- **Decisión:** mantener esos datos en
  [`config/versions.json`](../config/versions.json) y hacer que el script de
  build los traduzca a defines de Inno Setup.
- **Consecuencias:** no se deben hardcodear versiones en scripts. Cambiar una
  versión exige volver a preparar staging y validar la combinación completa.
- **Evidencia:** `build-installer.ps1` y los scripts temporales de
  post-instalación leen el manifiesto; el build genera `LICENSE.txt`.

## D-002 — Miniconda privada y aislada

- **Estado:** sustituida por D-010.
- **Fecha de sustitución:** 2026-08-22.
- **Contexto:** el instalador debe coexistir con Conda preexistente sin alterar
  sus preferencias ni sus directorios de entornos.
- **Decisión:** instalar Miniconda dentro del directorio de DataForge y
  generar una `.condarc` privada con directorios locales para paquetes y
  entornos.
- **Consecuencias:** sustituida porque el runtime Python pasó a ser CPython
  oficial empaquetado en el build. D-011 retiró también la limpieza de restos
  de esa Miniconda.

## D-003 — Alias Conda seguro para un entorno por ruta

- **Estado:** sustituida por D-010.
- **Fecha de sustitución:** 2026-08-22.
- **Contexto:** el entorno privado debe poder aparecer por nombre para
  `conda activate` sin crear una segunda copia.
- **Decisión:** crear un junction en la misma unidad o un enlace simbólico
  entre unidades bajo `%USERPROFILE%\.conda\envs\<condaEnvName>`, solo si no
  ocupa un entorno ajeno.
- **Consecuencias:** las instalaciones nuevas no registran alias Conda. D-011
  retiró la limpieza de un alias heredado.

## D-004 — PATH compatible con el buscador de comandos

- **Estado:** aceptada; revisada el 2026-08-20.
- **Contexto:** las rutas expandibles reducen duplicación, pero en Windows las
  entradas de usuario con `%VARIABLE%` pueden permanecer literales al buscar un
  ejecutable. En ese caso los binarios del producto no se resuelven aunque sus
  variables de entorno existan.
- **Decisión:** persistir como rutas absolutas todas las entradas que
  DataForge añade al `PATH` de usuario.
- **Consecuencias:** mover manualmente la instalación no está soportado; una
  reinstalación vuelve a registrar sus rutas. Los scripts deben retirar tanto
  rutas absolutas propias como referencias heredadas `%VARIABLE%` y abrir una
  terminal nueva tras instalar.
- **Evidencia:** `Get-EnvironmentPathEntries` y `Add-UserPathEntry` en
  `common.ps1`; comprobación manual de `spark-shell` con una ruta absoluta.

## D-005 — Post-instalación asíncrona observable

- **Estado:** aceptada y aplicada.
- **Contexto:** configurar el runtime y verificar una `SparkSession` local
  requiere una UI que informe progreso y permita cancelar.
- **Decisión:** el wizard de Inno Setup lanza `post-install.ps1` de forma
  asíncrona y se comunica mediante archivos de progreso, log, PID,
  cancelación y código de salida.
- **Consecuencias:** los scripts deben mantener esos archivos de coordinación
  y respetar la cancelación. Una cancelación puede terminar procesos hijos.
- **Evidencia:** `StartPostInstallAsync`, `PollPostInstall` y
  `KillPostInstall` en `wizard-code.iss`.

## D-006 — Limpieza temporal solo tras éxito

- **Estado:** aceptada y aplicada; revisada por D-016.
- **Contexto:** los scripts, la configuración y los logs son útiles
  para diagnosticar fallos, pero no deben permanecer en una instalación
  completada.
- **Decisión:** borrar `config/`, `installer/`, `scripts/` y `logs/` tras una
  post-instalación correcta; conservarlos cuando falla. En el wizard gráfico,
  el borrado comienza cuando la persona usuaria avanza desde la pantalla de
  éxito para que pueda revisar el log completo.
- **Consecuencias:** las investigaciones posteriores a una instalación exitosa
  deben basarse en validaciones nuevas, ya que no se retiene su log inicial
  después de cerrar el wizard. Si la limpieza no puede completarse, se
  conservan los recursos que queden para diagnóstico.
- **Revisión:** D-016 deja de copiar `scripts/` y `config/` a `{app}`. El
  diagnóstico de un fallo usa `logs/` y el runtime copiado. `RemoveInstallOnlyFolders`
  sigue borrando `scripts/` y `config/` residuales de instalaciones antiguas,
  y `logs/` tras un éxito.
- **Evidencia:** `RemoveInstallOnlyFolders` en `wizard-code.iss`.

## D-007 — Inno Setup como empaquetador y limpiador activo

- **Estado:** aceptada y aplicada.
- **Contexto:** el proyecto necesita un instalador gráfico Windows con copia de
  archivos, accesos directos, post-instalación y desinstalación.
- **Decisión:** utilizar Inno Setup como empaquetador y mantener el flujo
  activo de desinstalación en `wizard-code.iss` y `[UninstallDelete]`.
- **Consecuencias:** `DataForge.iss` se compila a través del build. Los
  cambios de desinstalación deben alinearse con esa implementación activa.
- **Evidencia:** [`DataForge.iss`](../installer/DataForge.iss) y
  [`wizard-code.iss`](../installer/wizard-code.iss).

## D-008 — Raíz mínima de instalación

- **Estado:** aceptada y aplicada; revisada el 2026-08-22.
- **Fecha:** 2026-08-21.
- **Contexto:** el payload de post-instalación incluye configuración, scripts
  y archivos de coordinación que no son necesarios para ejecutar el runtime
  una vez verificado.
- **Decisión:** tras éxito, conservar en la raíz solo `java/`, `spark/`,
  `hadoop/`, `python/`, `LICENSE.txt` y los archivos `unins*`
  requeridos por Inno Setup. Los accesos directos construyen su sesión sin
  wrappers permanentes bajo `bin/`.
- **Consecuencias:** `LICENSE.txt` es generado desde la configuración y
  no puede editarse como fuente de versiones. Las instalaciones anteriores
  pueden conservar `bin/` o `PRODUCT_INFO.txt` hasta que el nuevo flujo lo
  limpie o se desinstalen.
- **Evidencia o validación:** implementación en `build-installer.ps1`,
  `DataForge.iss`, `wizard-code.iss` y `common.ps1`.

## D-009 — Entorno Conda resuelto en el build

- **Estado:** sustituida por D-010.
- **Fecha:** 2026-08-21.
- **Fecha de sustitución:** 2026-08-22.
- **Contexto:** Java, Spark y winutils ya se materializan en el build, pero el
  entorno Python se creaba en el PC con conda-forge y PyPI. Esa asimetría
  impedía instalar sin red y alargaba la post-instalación.
- **Decisión:** crear el entorno durante el build, empaquetarlo con `conda-pack`
  y, en el PC, instalar Miniconda en silencio, extraer el pack y ejecutar
  `conda-unpack`.
- **Consecuencias:** el modelo Miniconda + pack se sustituyó por un prefijo
  CPython copiado como el resto del runtime. Se conserva el contrato de
  instalación sin red en el PC.

## D-010 — CPython oficial empaquetado en el build

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-08-22.
- **Contexto:** Miniconda, un env de build y `conda-pack` duplicaban el trabajo
  que Java y Spark ya resuelven copiando un árbol al staging. El usuario
  necesita un runtime más ligero y un código más simple, sin `conda activate`.
- **Decisión:** descargar el instalador oficial de CPython 3.11.9 de python.org,
  instalarlo en silencio solo en la máquina de build (`Include_launcher=0`,
  `PrependPath=0`, `AssociateFiles=0`), ejecutar `pip install pyspark` sobre
  ese prefijo y copiarlo a `staging/python`. Inno lo instala bajo `{app}\python`
  como Java y Spark. La post-instalación comprueba `python.exe`, configura
  variables y verifica una `SparkSession`. No se registra `py.exe`. La
  desinstalación de restos de Miniconda quedó retirada por D-011.
- **Consecuencias:** se sustituyen D-002, D-003 y D-009. El §3 de la
  constitución pasa a aislar CPython privado. El `PATH` de usuario incluye
  `{app}\python` y no `Scripts`, porque los lanzadores de pip pueden conservar
  el prefijo de build; se usa `python.exe` y `python -m pip`. El instalador
  oficial no se ejecuta en el PC del usuario. Las 3.11 posteriores a 3.11.9
  no publican binarios oficiales. Un `pip install` posterior en el PC sí puede
  necesitar red. Upgrade y repair in-place siguen fuera de contrato.
  Instalaciones 1.0.0 basadas en Conda no se migran in-place; hay que
  desinstalar y volver a instalar.
- **Evidencia o validación:** `build-installer.ps1 -SkipCompile` instaló CPython
  3.11.9 en `downloads/python-root`, ejecutó `pip install pyspark==3.5.9` y
  copió `staging/python` (404,7 MiB; staging total 1.136,7 MiB, sin Miniconda
  ni pack). `test-post-install.ps1` sobre `%TEMP%\psb-cpython-test` con proxy
  `http://127.0.0.1:9` completó `SparkSession` 3.5.9 y salida `OK`.
  `uninstall-env.ps1` vació las variables de usuario y eliminó el `python/`
  de prueba. `build-installer.ps1 -SkipDownload` compiló
  `installer/dist/PySparkBuilder-Setup-1.0.0.exe` (832,3 MiB). No se recorrió
  el wizard gráfico ni una instalación `/SILENT` del Setup.

## D-011 — Sin Conda en el producto ni en la desinstalación

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-08-22.
- **Contexto:** D-010 ya sustituyó Miniconda por CPython empaquetado, pero el
  instalador y los scripts seguían limpiando `miniconda/`, alias bajo
  `%USERPROFILE%\.conda` y entradas de `PATH` de esa etapa. Eso mantenía
  Conda como contrato de desinstalación y como superficie de código.
- **Decisión:** eliminar del código ejecutable toda lógica de Conda o
  Miniconda. El producto no instala, no registra y no limpia recursos de
  Conda. La desinstalación se limita al CPython privado, variables propias y
  entradas de `PATH` de Java, Spark, Hadoop y `{app}\python`.
- **Consecuencias:** se modifica el §4 de la constitución. Una instalación
  1.0.0 basada en Conda que no se desinstaló con su propio desinstalador
  puede dejar `miniconda/`, un alias o formas `%<HOME>%\miniconda\…`
  en el `PATH`. Esos restos no son responsabilidad del producto actual. D-002,
  D-003 y D-009 permanecen como registro histórico.
- **Evidencia o validación:** revisión estática de `common.ps1`,
  `setup-env.ps1`, `uninstall-env.ps1`, `wizard-code.iss`,
  `DataForge.iss` y `build-installer.ps1`. No se ejecutó una
  desinstalación de una instalación Conda heredada.

## D-012 — ipykernel empaquetado en el build

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-08-22.
- **Contexto:** el CPython privado ya incluye PySpark resuelto en el build
  (D-010). Para usar ese mismo intérprete en notebooks de VS Code o Cursor
  hace falta `ipykernel` dentro del prefijo, no un Jupyter de usuario.
- **Decisión:** pinar `ipykernelVersion` en `config/versions.json` e instalar
  `ipykernel==<version>` con `pip` durante el build, junto a PySpark. La
  post-instalación importa el módulo y comprueba la versión. No se ejecuta
  `ipykernel install` (ese comando registra el nombre genérico `python3`). El
  kernelspec de usuario con nombre propio y ruta absoluta quedó en D-013. No se
  empaqueta JupyterLab ni Notebook. El `pip` del build usa `python -s`
  y `--no-user` para instalar en el prefijo privado, no en
  `%APPDATA%\Python`.
- **Consecuencias:** el prefijo Python crece con las dependencias de
  `ipykernel` (IPython, jupyter_client, pyzmq, etc.). Un notebook usa
  `{app}\python\python.exe` como intérprete. El `pip` de build y la
  verificación ejecutan `python -s` y `pip --no-user` para no tomar paquetes
  del site de usuario. Cambiar `ipykernelVersion` invalida el stamp de
  `downloads/python-root` y vuelve a ejecutar `pip`.
- **Evidencia o validación:** `build-installer.ps1 -SkipCompile` instaló
  `ipykernel==7.3.0` en `downloads/python-root` con `python -s -m pip
  install --no-user` (el primer intento sin `-s` resolvió el paquete en
  `%APPDATA%\Python\Python311` y no lo copió). `python -s -c` sobre
  `staging/python\python.exe` importó `ipykernel` 7.3.0 desde
  `Lib\site-packages` y PySpark 3.5.9. El prefijo `staging/python` pasó a
  485,4 MiB. No se reejecutó `test-post-install.ps1` ni se compiló el `.exe`
  en este ciclo.

## D-013 — Descubrimiento del CPython privado en VS Code y Jupyter

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-08-22.
- **Contexto:** el prefijo instalado es una copia de archivos. VS Code descubre
  intérpretes sobre todo por PEP 514 (`PythonCore` y otras empresas), por
  venv/conda y por el `PATH` del proceso. El build deja `PythonCore\3.11`
  apuntando a `downloads/python-root` en la máquina de build; la copia en
  `{app}\python` no queda registrada. El `kernel.json` que instala `pip`
  usa el comando genérico `python`, y no había kernelspec de usuario. El
  selector de notebooks no ofrecía el runtime instalado.
- **Decisión:** en `setup-env.ps1`, registrar el CPython copiado bajo
  `HKCU\Software\Python\<producto>` (PEP 514, empresa propia; nunca
  `PythonCore` ni `py.exe`), reescribir el `kernel.json` del prefijo con la
  ruta absoluta de `{app}\python\python.exe` y escribir un kernelspec de
  usuario en `%APPDATA%\jupyter\kernels\<producto>` con el mismo `argv`.
  `verify-install.ps1` comprueba ambos. La desinstalación (Inno y
  `uninstall-env.ps1`) elimina solo esas claves y ese directorio.
- **Consecuencias:** VS Code y Jupyter pueden listar el runtime instalado sin
  seleccionar la ruta a mano. Un Python 3.11 ajeno registrado en `PythonCore`
  no se sobrescribe. Hay un efecto externo más que revertir al desinstalar.
  D-012 se mantiene para el empaquetado de `ipykernel`; deja de prohibir el
  kernelspec de nombre propio.
- **Evidencia o validación:** `setup-env.ps1` se ejecutó sobre
  `C:\testing\PySparkBuilder` (instalación de usuario ya presente; nombre
  entonces publicado). Quedó
  `HKCU\Software\Python\PySparkBuilder\3.11\InstallPath` con
  `ExecutablePath=C:\testing\PySparkBuilder\python\python.exe`.
  `PythonCore\3.11` siguió apuntando a `downloads/python-root`. El
  kernelspec `%APPDATA%\jupyter\kernels\pysparkbuilder\kernel.json` y el del
  prefijo usan esa ruta absoluta. `Test-PrivatePythonDiscovery` devolvió
  cero errores. No se recompiló el `.exe`, no se recorrió el wizard y no se
  reejecutó `verify-install.ps1` con SparkSession.

## D-014 — Cierre no bloqueante tras fallo de post-instalación

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-08-22.
- **Contexto:** si la configuración fallaba después de copiar archivos, el
  wizard podía quedar inoperable: `taskkill /T /F` esperaba sin tope, un
  volcado de Spark saturaba el hilo de la UI, y `ExitProcess` desde
  `CancelButtonClick` podía dejar el proceso de Setup colgado (había que
  matarlo desde el Administrador de tareas). El rollback también se bloqueaba
  si `java.exe` o `python.exe` del runtime seguían en uso.
- **Decisión:** esperar a `taskkill` y a procesos propios de forma acotada;
  matar procesos cuyo ejecutable está bajo `{app}` antes de revertir o salir;
  diferir la salida al conservar archivos (timer, no `ExitProcess` dentro del
  manejador de Cancelar); truncar el log en la UI y en `Write-InstallLog`;
  verificar Spark con cancelación y un timeout de 300 s.
- **Consecuencias:** un fallo de configuración debe dejar Cerrar usable. El
  memo puede omitir líneas; el diagnóstico completo sigue en
  `logs/install.log`. Un JVM ajeno bajo el mismo directorio de instalación
  también se detendría al cerrar con error o cancelar.
- **Evidencia o validación:** cambio en `wizard-code.iss`, `common.ps1` y
  `verify-install.ps1`. El parser de PowerShell aceptó los scripts. No se
  recompiló el `.exe` ni se recorrió el wizard gráfico en este ciclo.

## D-015 — Aviso de licencias en lugar de PRODUCT_INFO

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-08-22.
- **Contexto:** `PRODUCT_INFO.txt` era un manifiesto `clave=valor` en la raíz
  instalada. No informaba copyright ni licencias de Java, Spark, Hadoop,
  CPython, PySpark e ipykernel, y el wizard tenía `LicenseFile` vacío.
- **Decisión:** el build genera `LICENSE.txt` desde
  [`config/versions.json`](../config/versions.json) con el estilo NOTICE de
  Apache Spark: versiones de esa copia, titular de copyright y nombre de
  licencia de cada componente, más el texto BSD de ipykernel (redistribución
  binaria) y punteros a los textos completos en `java/`, `spark/` y
  `python/`. Inno Setup usa ese archivo como `LicenseFile` y lo copia a
  `{app}`. Se deja de generar `PRODUCT_INFO.txt`.
- **Consecuencias:** aparece la página de aceptación de licencia del wizard.
  `LICENSE.txt` no es una segunda fuente canónica de versiones. D-008 pasa a
  conservar `LICENSE.txt` en la raíz. La desinstalación sigue borrando un
  `PRODUCT_INFO.txt` heredado.
- **Evidencia o validación:** implementación en `build-installer.ps1` y
  `DataForge.iss`. El parser de PowerShell aceptó el script de build.
  `Write-LicenseFile` escribió `installer/staging/LICENSE.txt` con las
  versiones del manifiesto. No se recompiló el `.exe` ni se recorrió la
  página de licencia del wizard.

## D-016 — Scripts y config solo en `{tmp}`

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-09-02.
- **Contexto:** D-006 y D-008 ya exigían un árbol final mínimo, pero Inno
  copiaba `scripts/` y `config/` a `{app}` durante la instalación. Eso
  exponía el código de post-instalación en la carpeta del producto mientras
  corría el wizard, y también tras un fallo.
- **Decisión:** empaquetar `post-install.ps1`, `common.ps1`, `setup-env.ps1`,
  `verify-install.ps1` y `versions.json` con `dontcopy`. El wizard los extrae
  a `{tmp}` solo para lanzar PowerShell y los borra al terminar ese proceso,
  al cancelar o al salir del modo silencioso. No se copian a `{app}`.
  `uninstall-env.ps1` no viaja en el `.exe`; sigue siendo utilidad del repo.
  `logs/` permanece en `{app}` durante la post-instalación.
- **Consecuencias:** durante y después de instalar, la persona usuaria no ve
  `scripts/` ni `config/` en el directorio del producto. Un fallo se
  diagnostica con `logs/install.log`. Esto no cifra el payload: quien extraiga
  el `.exe` con herramientas de Inno puede recuperar los `.ps1`. D-006 queda
  revisada en cuanto a conservar scripts y config bajo `{app}`.
- **Evidencia o validación:** cambio en `DataForge.iss` y
  `wizard-code.iss`. No se recompiló el `.exe` ni se recorrió el wizard en
  este ciclo.

## D-017 — Una sola copia: reemplazar o exigir desinstalar

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-09-02.
- **Contexto:** Inno Setup con un `AppId` fijo ya sobrescribía archivos, pero
  permitía cambiar de carpeta. Eso podía dejar un árbol huérfano y entradas
  duplicadas en el `PATH`. O-003 pedía una política de upgrade. Las
  alternativas eran desinstalar en silencio y reinstalar, permitir dos copias
  o solo ocultar la página de directorio.
- **Decisión:** detectar la clave de desinstalación del `AppId` en `HKCU` y
  `HKLM`. En el mismo ámbito, reemplazar en esa carpeta (sin segunda copia,
  ignorando `/DIR=` distinto). En el otro ámbito, abortar y exigir
  desinstalar. Si no hay registro pero existe `DATAFORGE_HOME`, usar esa
  carpeta. `setup-env.ps1` retira del `PATH` las entradas bajo un
  `DATAFORGE_HOME` anterior.
  No se ofrece Repair de Windows ni
  desinstalación automática previa (el reemplazo in-place evita borrar y
  recopiar todo el runtime).
- **Consecuencias:** cambiar de carpeta exige desinstalar y volver a
  instalar. Una instalación por usuario y otra para todos los usuarios no
  pueden coexistir. Se modifica el §4 de la constitución. O-003 queda
  resuelta para el reemplazo; Repair tipo ARP sigue fuera de alcance.
- **Evidencia o validación:** `wizard-code.iss` compiló en Inno Setup 7.1.0
  con un `.iss` mínimo (sin payload). El parser de PowerShell aceptó
  `common.ps1`, `setup-env.ps1` y `uninstall-env.ps1`. `Test-PathIsUnderRoot`
  cubrió raíces propias, `%VARIABLE%` y un vecino que no debe coincidir. No
  se recorrió el wizard gráfico ni un `/SILENT` sobre una instalación real.

## D-018 — Nombre DataForge y avisos de marcas

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-09-03.
- **Contexto:** las normas de Apache Spark prohíben usar “Spark” o
  derivados en el nombre de un producto de software, salvo la forma
  descriptiva “for Apache Spark” o “powered by Apache Spark”. El nombre
  anterior incorporaba PySpark. El `LICENSE.txt` generado no declaraba
  la independencia respecto de la ASF, Eclipse Foundation y PSF, ni
  advertía que winutils no es un binario oficial de Apache Hadoop.
- **Decisión:** el `productName` pasa a **DataForge**. La forma descriptiva
  permitida es “DataForge, powered by Apache Spark”. Se conserva el `AppId` para
  reemplazar copias publicadas con el nombre anterior. La variable de
  hogar pasa a derivarse de `productName` (`DATAFORGE_HOME`). La limpieza
  PEP 514 conserva el nombre de empresa publicado antes del cambio de
  nombre. El `LICENSE.txt` del instalador declara no afiliación,
  atribuye las marcas y publica el código propio bajo MIT. El build
  copia o genera `hadoop\LICENSE.txt` y `NOTICE`. No se usan logotipos
  de Apache Spark.
- **Consecuencias:** el ejecutable pasa a `DataForge-Setup-*.exe` y el
  script Inno a `DataForge.iss`. Hay que renombrar el repositorio y el
  dominio de GitHub para que no contengan “spark” (la ASF no permite
  esos dominios sin permiso). Este registro no es asesoramiento jurídico.
- **Evidencia o validación:** cambio de `config/versions.json`,
  `Write-LicenseFile`, wizard y scripts. El `[Code]` se recompiló en un
  `.iss` mínimo. No se recorrió el wizard gráfico ni se redistribuyó un
  `.exe` nuevo.

## D-019 — Liberar un CPython de build huérfano

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-09-03.
- **Contexto:** el instalador oficial de CPython es un producto per-user
  único. Tras borrar `python-root`, mover el repo o renombrar el proyecto
  (D-018, `PySparkBuilder` → `DataForge`), Windows Installer sigue
  registrando esa versión. Un `/quiet` nuevo hace Modify, sale 0 y no
  escribe `python.exe` en la ruta de build. El build solo reparaba cuando
  `PythonCore` apuntaba exactamente al prefijo actual, así que un registro
  en un `installer\downloads\python-root` anterior bloqueaba el staging.
- **Decisión:** reparar si el registro apunta al prefijo de build actual.
  Si apunta a otro `...\installer\downloads\python-root`, o `python.exe`
  ya no está en la ruta registrada, restaurar ese prefijo con `/repair`
  (el MSI `pip` aborta `/uninstall` con 1603 si no detecta un Python),
  desinstalar el producto y volver a instalar. Si el ARP sigue presente
  sin `InstallPath`, intentar `/uninstall`. Si `PythonCore` apunta a un
  CPython ajeno con `python.exe` presente, fallar sin tocarlo.
- **Consecuencias:** un build desde cero en una máquina que ya construyó
  este producto (u otro clone) no queda bloqueado por un registro
  huérfano. `/repair` puede recrear temporalmente el árbol de un repo
  anterior solo para poder desinstalarlo. Sigue prohibido desinstalar o
  reparar un Python de usuario usable. El instalador oficial solo se
  ejecuta en la máquina de build (D-010).
- **Evidencia o validación:** en esta máquina, `PythonCore\3.11` apuntaba
  a `C:\PySparkBuilder\installer\downloads\python-root` sin `python.exe`.
  `/uninstall /quiet` salió 1603 (`pip` LaunchConditions: "No Python 3.11
  installation was detected").   `/repair` restauró archivos en esa ruta
  (ignora el `TargetDir` nuevo) y el `/uninstall` posterior dejó ARP y
  `PythonCore` vacíos. `build-installer.ps1 -SkipCompile` instaló
  CPython en `downloads/python-root`, `pip` 24.0, PySpark 3.5.9 e
  ipykernel 7.3.0, y copió `staging/python`. No se compiló el `.exe`.

## D-022 — Dos fichas generadas: pública y de desarrollo

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-09-08.
- **Contexto:** el README original de la raíz mezclaba la ficha de descarga
  con el proceso de build. El remoto público publica versiones; el árbol
  privado conserva recetas. Las versiones vivas ya están en
  `config/versions.json`.
- **Decisión:** `README.md` es la ficha pública (descarga, runtime, uso).
  `README_developers.md` es la guía técnica (build, estructura, pruebas).
  Ambas se generan con `config/Update-Readme.ps1` desde
  `config/*.template.md` y el manifiesto. No se editan a mano ni copian
  versiones como segunda fuente.
- **Consecuencias:** un cambio de `productVersion` o del stack exige
  regenerar las fichas. La documentación viva de contratos sigue en
  `docs/`. Quien clone solo el remoto público puede quedarse con
  `README.md` generado y omitir la guía de desarrollo.
- **Evidencia o validación:** el script se ejecutó en esta máquina y escribió
  ambas fichas con `productVersion` del manifiesto. No equivale a un
  build ni a una instalación.

## D-023 — Aviso de licencia según el idioma del wizard

- **Estado:** aceptada y aplicada.
- **Fecha:** 2026-09-28.
- **Contexto:** `Write-LicenseFile` escribía un único `LICENSE.txt` con el
  texto propio de DataForge duplicado en español e inglés. El wizard lo
  mostraba entero en la página de licencia, con independencia del idioma
  elegido.
- **Decisión:** el build genera `LICENSE.es.txt` y `LICENSE.en.txt`. El
  texto propio (independencia, marcas, aviso y lista de componentes) va en
  el idioma del archivo. Las licencias de terceros y el texto MIT del
  instalador permanecen en su idioma original. Cada entrada de
  `[Languages]` usa su `LicenseFile`. Inno copia a `{app}\LICENSE.txt` solo
  el archivo del idioma seleccionado.
- **Consecuencias:** la página de licencia y el archivo instalado siguen el
  idioma del wizard, incluido `/LANG=`. Deja de generarse un `LICENSE.txt`
  bilingüe en staging. Sigue sin ser una segunda fuente canónica de
  versiones. `build-installer.ps1` se guarda en UTF-8 con BOM para que
  Windows PowerShell 5.1 no corrompa los acentos del texto español.
- **Evidencia o validación:** el parser de PowerShell aceptó
  `build-installer.ps1`. `Write-LicenseFile` escribió
  `installer/staging/LICENSE.es.txt` y `LICENSE.en.txt` desde
  `config/versions.json`: el prefacio va en un solo idioma y las secciones
  de terceros más el texto MIT siguen en inglés. No se recompiló el `.exe`
  ni se recorrió la página de licencia del wizard.

## Cuestiones abiertas

### O-001 — Consolidar la desinstalación

`uninstall-env.ps1` contiene una limpieza similar a la de Inno Setup pero no
está referenciado por el flujo actual. Antes de modificar cualquiera de ambas
rutas se debe decidir si el script se integra, se mantiene como utilidad
manual o se retira.

### O-002 — Integridad y reproducibilidad de descargas

Las fuentes actuales no se verifican mediante hashes y algunas se resuelven
desde referencias mutables. Se necesita una política de versiones inmutables,
checksums y validación previa a la extracción.

### O-003 — Repair tipo Windows

D-017 cubre el reemplazo de una copia existente. Sigue sin haber un botón
Repair/Modify en Agregar o quitar programas. Cualquier promesa sobre ese
escenario exige especificación, pruebas y una nueva decisión.

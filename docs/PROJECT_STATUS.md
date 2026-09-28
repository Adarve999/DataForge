# Estado del proyecto

## Fotografía revisada

- **Fecha de revisión:** 2026-09-08.
- **Producto declarado:** `DataForge` (`config/versions.json`).
- **Versión declarada en la configuración revisada:** `0.0.1`.
- **Fuente de los valores vivos:** [`config/versions.json`](../config/versions.json).
- **Alcance de esta revisión:** D-022: `README.md` (público) y
  `README_developers.md` (proceso) se generan desde plantillas. D-019 y
  D-018 se mantienen.
- **Build verificado:** `build-installer.ps1 -SkipCompile` instaló CPython
  3.11.9 en `downloads/python-root` (tras `/repair` + `/uninstall` del
  registro huérfano), `pip install` de PySpark 3.5.9 e ipykernel 7.3.0, y
  copió `staging/python`. No se compiló el Setup (`DataForge-Setup-*.exe`).
- **Post-instalación:** no se recorrió el wizard gráfico ni `/SILENT`
  sobre una instalación ya presente.
- **Límite de validación local:** `Update-Readme.ps1` escribió las dos
  fichas de la raíz. El parser de PowerShell aceptó `build-installer.ps1`.
  No se reejecutó `test-post-install.ps1` ni se recorrió un reemplazo de
  instalación.
- **Actualización 2026-09-28 (D-023):** `Write-LicenseFile` escribió
  `installer/staging/LICENSE.es.txt` y `LICENSE.en.txt`. El parser aceptó
  `build-installer.ps1`. No se recompiló el `.exe` ni se recorrió la página
  de licencia del wizard.

Esta página es una fotografía factual. Debe actualizarse después de validar
cambios funcionales, no al inicio de una tarea.

## Capacidades observadas en código

| Capacidad | Evidencia | Estado |
| --- | --- | --- |
| Preparar staging con Java, Spark, winutils y CPython+PySpark+ipykernel | `installer/build-installer.ps1` | ` -SkipCompile` ejecutado en este ciclo; CPython+PySpark+ipykernel en `staging/python` |
| Generar el aviso de licencia en el idioma del wizard | `Write-LicenseFile` | D-023: escribió `LICENSE.es.txt` y `LICENSE.en.txt` en staging; no se recompiló el `.exe` ni se abrió la página de licencia |
| Generar ejecutable Inno Setup desde el build | `build-installer.ps1` y `DataForge.iss` | Implementada; el `.exe` de este ciclo no se recompiló |
| Extraer scripts y config solo a `{tmp}` | `[Files]` con `dontcopy` y `ExtractInstallerPayload` | Implementada (D-016); no se recorrió el wizard |
| Reemplazar una copia previa en la misma carpeta | `EvaluateExistingInstallation` y página de reemplazo | Código actualizado (D-017); no se recorrió el wizard |
| Rechazar una copia en el otro ámbito de privilegios | `EvaluateExistingInstallation` | Código actualizado; no se ejecutó el aborto real |
| Retirar `PATH` de un hogar anterior | `Remove-StaleInstallPathEntries` | Parser y prueba en memoria de `Test-PathIsUnderRoot`; no se mutó el `PATH` del usuario |
| Post-instalación con progreso y cancelación | `wizard-code.iss` y `post-install.ps1` | Código actualizado (rutas `{tmp}`); la ruta gráfica no se recorrió |
| Runtime Python copiado, con ipykernel | `staging/python` | Evidencia previa; no se regeneró staging |
| Configurar variables, `PATH` y descubrimiento VS Code/Jupyter | `setup-env.ps1` y `common.ps1` | Implementada; no se reejecutó en este ciclo |
| Verificar ipykernel, descubrimiento y SparkSession local | `verify-install.ps1` | No se reejecutó en este ciclo |
| Accesos directos para Apache Spark shell y Python | `[Icons]` y `[Run]` de `DataForge.iss` | Pendiente de recompilar y de abrir enlaces `.lnk` |
| Limpieza de desinstalación mediante Inno Setup | `wizard-code.iss` y `[UninstallDelete]` | Sin cambio funcional en este ciclo |
| Fichas pública y de desarrollo | `config/Update-Readme.ps1` y `config/*.template.md` | Script ejecutado; escribió `README.md` y `README_developers.md` |

“Implementada” indica que la capacidad está presente en el código revisado; no
prueba que se haya ejecutado correctamente en todas las versiones de Windows,
rutas o escenarios.

## Evidencia de calidad disponible

| Área | Evidencia actual | Limitación |
| --- | --- | --- |
| Verificación funcional | `verify-install.ps1` comprobó Java y una `SparkSession` local 3.5.9 en un ciclo anterior | No se reejecutó tras D-016 |
| Descubrimiento VS Code/Jupyter | `setup-env.ps1` + lectura de PEP 514 y `kernel.json` en `C:\testing\PySparkBuilder` (nombre entonces publicado) | Ciclo anterior; no se reabrió VS Code |
| Harness de post-instalación | `test-post-install.ps1` sobre una copia de staging | No equivale a una instalación gráfica ni a `/SILENT` |
| Build | Staging con CPython y compilaciones reales del `.exe` | No hay CI; este ciclo no compiló |
| Instalación sin red | Proxy `127.0.0.1:9` en un ciclo anterior | No se revalidó |
| Desinstalación | `uninstall-env.ps1` sobre la ruta de prueba en un ciclo anterior | `uninstall-env.ps1` ya no viaja en el `.exe` (D-016) |
| Calidad estática | Revisión de `DataForge.iss` y `wizard-code.iss` | No hay PSScriptAnalyzer, formatter ni pre-commit |
| Entrega | Artefacto `.exe` en `installer/dist/` (ciclo anterior) | El `.exe` empaquetado aún no incluye D-016 ni D-017 |
| Código del wizard | Compilación de `wizard-code.iss` con Inno Setup 7.1.0 en un `.iss` mínimo | No equivale al Setup del producto ni a un reemplazo real |

No se han encontrado workflows de CI/CD, una suite Pester, un linter
configurado ni un sistema de pruebas unitarias en el repositorio.

## Riesgos y deuda conocida

| Prioridad | Hecho observado | Impacto |
| --- | --- | --- |
| Alta | Las descargas no se verifican mediante checksums; algunas fuentes son mutables, como una URL de Java `latest` y una rama de repositorio para winutils | Un build futuro puede no reproducir el mismo payload o consumir un artefacto inesperado |
| Alta | No hay CI ni matriz de pruebas automatizada | Las regresiones de build, instalación y desinstalación dependen de validación manual |
| Media | La compatibilidad entre Spark, PySpark, Python, Java y winutils se alinea por configuración, sin validación cruzada automática | Un cambio de versión puede producir un entorno incompatible |
| Media | La ruta activa de desinstalación está en Inno Setup mientras `uninstall-env.ps1` no está referenciado ni empaquetado | La lógica duplicada puede divergir; el script solo sirve como utilidad del repo |
| Media | No existe Repair/Modify en Agregar o quitar programas | D-017 cubre el reemplazo al volver a ejecutar Setup; Repair tipo ARP sigue fuera de contrato |
| Media | El `.exe` incluye Java, Spark y un CPython con los jars de PySpark; Inno lo comprime con LZMA | Compilar y distribuir el instalador sigue siendo lento y el artefacto supera 800 MiB |
| Media | Los logs se eliminan después de avanzar desde una instalación correcta | Hay menos evidencia disponible para diagnosticar problemas posteriores |
| Media | D-016 oculta los scripts de `{app}`, pero el `.exe` sigue conteniendo los `.ps1` y se pueden extraer con herramientas de Inno | No es una protección criptográfica del código de post-instalación |
| Media | El cierre tras fallo (D-014), la extracción a `{tmp}` (D-016), el reemplazo (D-017) y el nombre DataForge (D-018) están en el código y no se validaron con el `.exe` del producto | El Setup ya generado sigue usando el nombre anterior hasta recompilar |
| Baja | Las cadenas de interfaz están duplicadas entre Inno Setup y PowerShell | Un cambio puede dejar traducciones incoherentes |
| Baja | El instalador oficial de CPython se ejecuta en la máquina de build y puede dejar claves de desinstalación de ese prefijo | Es un efecto colateral del build, no del PC del usuario |

## Límites operativos vigentes

- El producto se diseña para el usuario actual y usa variables bajo `HKCU`.
- El runtime solo soporta ejecución local comprobada por una `SparkSession`.
- El payload (Java, Spark, winutils y CPython con PySpark) se materializa
  durante el build. La post-instalación no requiere red. Un `python -m pip`
  posterior sí puede necesitarla.
- `test-post-install.ps1` no ejecuta la limpieza final del wizard; usa los
  scripts del repo, no un `{tmp}` de Inno.
- El `.exe` ya generado no incluye D-016, D-017 ni D-018 hasta el próximo
  `build-installer.ps1` sin `-SkipCompile`.

## Próximas prioridades recomendadas

1. Recorrer el wizard gráfico del `.exe` nuevo: `{app}` sin `scripts/` ni
   `config/`; reemplazo de una copia previa (misma carpeta, `/DIR=` distinto
   y, si es posible, el otro privilegio); además `/SILENT`.
2. Definir una política de integridad para fuentes externas: versiones
   inmutables, hashes y verificación antes de extraer o empaquetar.
3. Decidir y documentar una única implementación canónica de desinstalación.
4. Incorporar PSScriptAnalyzer/Pester y un runner Windows cuando el proyecto
   requiera releases repetibles.
5. Definir Repair tipo Windows solo si hace falta como función de producto.

## Regla de mantenimiento

Al cerrar un cambio material, actualizar esta página solo con hechos
verificados: qué se probó, qué cambió, qué riesgo se eliminó o apareció y qué
continúa pendiente. Las decisiones duraderas se registran en
[Decisiones](DECISIONS.md); el comportamiento comprometido se actualiza en la
[Especificación](PROJECT_SPECIFICATION.md).

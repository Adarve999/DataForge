# Constitución de DataForge

Esta constitución define las restricciones duraderas del proyecto. Se aplica a
código, configuración, documentación, build y release. Cuando haya conflicto
entre velocidad de entrega y uno de estos principios, prevalece el principio.

## 1. Producto y plataforma

DataForge es un instalador comunitario de un runtime local de Apache Spark para
Windows x64. No es un producto de The Apache Software Foundation. No se
presentarán como soportadas plataformas, flujos de datos o capacidades de
aplicación que el repositorio no implemente y verifique. El nombre del
producto no incorporará marcas de Apache Spark, Hadoop, Python, Java ni
Eclipse.

## 2. Configuración única y trazable

`config/versions.json` es la fuente de verdad de versiones, nombre del producto
y detalles de descarga. Los scripts deben leerla y propagar sus valores; no se
deben introducir valores de versión paralelos.

Cualquier cambio de configuración debe ser trazable a su compatibilidad,
fuente de descarga y resultado de validación.

## 3. Aislamiento del runtime Python

El CPython privado vive bajo el directorio de instalación de DataForge.
El producto no debe registrar el lanzador `py.exe`, asociar extensiones ni
modificar una instalación de Python ajena (python.org, Microsoft Store u otra).

El instalador oficial de python.org, si se usa, solo puede ejecutarse en la
máquina de build para materializar el prefijo que Inno copia. La
desinstalación no debe borrar, reconfigurar ni tocar un CPython que no
pertenezca a esta instalación.

## 4. Efectos externos mínimos y reversibles

Las modificaciones de archivos, `HKCU\Environment`,
`HKCU\Software\Python\<producto>`, el kernelspec de usuario bajo
`%APPDATA%\jupyter\kernels`, `PATH` y accesos directos
deben ser:

- necesarias para que el producto funcione;
- explícitas en código y documentación;
- idempotentes cuando sea viable;
- removibles sin afectar recursos ajenos.

Todas las rutas que DataForge añade al `PATH` de usuario deben persistirse
como rutas absolutas bajo la instalación. Las referencias anidadas
`%VARIABLE%` pueden conservarse sin expandir en `cmd.exe`; al actualizar o
desinstalar se deben eliminar también esas formas heredadas. No se admite una
segunda copia en paralelo: el instalador reemplaza la instalación previa del
mismo `AppId` en el mismo directorio, o exige desinstalar si el ámbito de
privilegios no coincide. Mover una instalación no es un flujo soportado y
exige desinstalar y volver a instalar.

## 5. Build reproducible y controlado

`installer/build-installer.ps1` es la entrada soportada para preparar staging y
compilar el instalador. `DataForge.iss` debe recibir los defines generados
por ese flujo, no compilarse manualmente.

Las fuentes externas deben considerarse parte del riesgo de una entrega. No se
debe declarar un build reproducible mientras sus descargas no estén validadas
con evidencia suficiente.

## 6. Integridad del runtime

Una post-instalación solo termina correctamente después de:

1. comprobar que el CPython privado copiado en la instalación está presente;
2. configurar las variables de entorno necesarias;
3. verificar Java, winutils, Spark, `ipykernel` y una `SparkSession` local.

No se debe eliminar información de diagnóstico de una instalación fallida.
La limpieza automática tras éxito debe limitarse a archivos temporales de la
instalación.

## 7. Implementación mantenible

Los scripts PowerShell deben mantener modo estricto y errores explícitos. La
lógica compartida de rutas, logging, procesos y `PATH` pertenece a
`installer/scripts/common.ps1`; no se deben crear implementaciones paralelas
sin una razón documentada.

Los cambios en Inno Setup deben preservar la propagación de configuración, la
cancelación, el progreso y la limpieza segura. Las interfaces en español e
inglés deben mantenerse coherentes.

## 8. Verificación antes de afirmar soporte

Las afirmaciones sobre compatibilidad, comportamiento de instalación o release
deben basarse en código revisado y, cuando proceda, una ejecución verificable.
Una prueba manual o una inspección estática no se describirá como cobertura
automatizada.

## 9. Documentación como contrato vivo

Los documentos de `docs/` describen contratos y estado; el código y la
configuración aportan la evidencia ejecutable. Los cambios que afecten alcance,
arquitectura, versiones, efectos externos, pruebas o riesgos deben actualizar
la documentación relevante en el mismo cambio.

Los documentos distinguirán:

- **hecho observado**: confirmado por código o validación;
- **contrato**: comportamiento que el proyecto se compromete a conservar;
- **riesgo o propuesta**: asunto abierto que no debe venderse como capacidad.

## 10. Cambios a esta constitución

Modificar un principio exige una decisión explícita en
[Decisiones](DECISIONS.md), actualizar las reglas de Cursor relacionadas y
explicar el impacto sobre instalaciones existentes. Los cambios de formato o
redacción que no cambien el significado no requieren una nueva decisión.

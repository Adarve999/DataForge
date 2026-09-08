# Documentación de DataForge

DataForge es un instalador comunitario para Windows que prepara un runtime local
de Eclipse Temurin, Apache Spark, winutils de Apache Hadoop, CPython oficial
y PySpark. No es un producto de The Apache Software Foundation, ni una
librería Python, ni un generador de trabajos Spark.

## Índice

- [Especificación del producto](PROJECT_SPECIFICATION.md): contrato funcional,
  alcance, configuración y criterios de aceptación.
- [Arquitectura](ARCHITECTURE.md): componentes, responsabilidades y flujos de
  build, instalación, ejecución y desinstalación.
- [Constitución](CONSTITUTION.md): invariantes que no se deben violar.
- [Estado del proyecto](PROJECT_STATUS.md): fotografía factual de la versión
  revisada, cobertura conocida, riesgos y trabajo pendiente.
- [Desarrollo y release](DEVELOPMENT_AND_RELEASE.md): procedimiento de cambio,
  validación y publicación.
- [Decisiones](DECISIONS.md): decisiones arquitectónicas vigentes y formato
  para registrar las futuras.

## Jerarquía de fuentes de verdad

No todos los documentos tienen la misma autoridad. Ante una discrepancia,
prevalece la fuente situada más arriba y se debe corregir la documentación
afectada después de verificar el comportamiento.

1. El comportamiento ejecutable y los datos versionados:
   [`config/versions.json`](../config/versions.json),
   [`installer/`](../installer/) y sus scripts.
2. La especificación funcional y la constitución de este directorio.
3. El estado del proyecto y el registro de decisiones.
4. Las fichas generadas de la raíz:
   [`README.md`](../README.md) (descarga pública) y
   [`README_developers.md`](../README_developers.md) (build y proceso).
   Salen de `config/*.template.md` y el manifiesto; no son fuente de versiones.

Las versiones concretas, nombres de archivos descargados y URLs pertenecen a
`config/versions.json`. No deben copiarse como datos canónicos en Markdown; los
documentos describen el contrato y enlazan a la configuración.

## Orden de lectura recomendado

| Tarea | Leer primero |
| --- | --- |
| Entender el producto o modificar su alcance | [Especificación](PROJECT_SPECIFICATION.md) y [Constitución](CONSTITUTION.md) |
| Construir o modificar el instalador | [README de desarrollo](../README_developers.md), [Arquitectura](ARCHITECTURE.md), [Constitución](CONSTITUTION.md) y la regla de Cursor aplicable |
| Cambiar versiones, URLs o dependencias | [Especificación](PROJECT_SPECIFICATION.md), [Desarrollo y release](DEVELOPMENT_AND_RELEASE.md), `config/versions.json` y `config/Update-Readme.ps1` |
| Preparar una entrega | [Desarrollo y release](DEVELOPMENT_AND_RELEASE.md) y [Estado](PROJECT_STATUS.md) |
| Diagnosticar un comportamiento observado | [Arquitectura](ARCHITECTURE.md), [Estado](PROJECT_STATUS.md) y los logs conservados tras un fallo |

## Protocolo de actualización documental

1. Confirmar el comportamiento en código, configuración o una ejecución
   verificable antes de documentarlo como hecho.
2. Cuando cambie un contrato, arquitectura, efecto externo, versión, flujo de
   release o riesgo, actualizar el documento correspondiente en el mismo
   cambio.
3. Actualizar `PROJECT_STATUS.md` tras cambios funcionales verificados y
   registrar en `DECISIONS.md` las decisiones duraderas que impliquen
   alternativas o compromisos relevantes.
4. No declarar una función como soportada solo porque esté prevista; las
   propuestas, riesgos y hechos observados se mantienen diferenciados.
5. Si cambia el manifiesto o el texto de una ficha de la raíz, editar
   `config/*.template.md` y ejecutar `config/Update-Readme.ps1`. No editar
   `README.md` ni `README_developers.md` a mano.

Las reglas de [`.cursor/rules/`](../.cursor/rules/) y el
[`AGENTS.md`](../AGENTS.md) convierten este protocolo en contexto operativo para
Cursor Agent. Son una guía de trabajo, no un mecanismo de actualización
automática ni un sustituto de pruebas.

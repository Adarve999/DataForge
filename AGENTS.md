# DataForge — guía para agentes

## Contexto del producto

DataForge es un instalador comunitario Windows x64 para un runtime local de
Apache Spark. El nombre del producto no incorpora marcas de Apache Spark.
El repositorio contiene PowerShell, Inno Setup y CMD; no contiene una
aplicación Python ni lógica de negocio Spark.

## Fuentes de verdad

1. Versiones y URLs:
   [`config/versions.json`](config/versions.json).
2. Comportamiento ejecutable:
   [`installer/`](installer/), especialmente
   [`installer/scripts/common.ps1`](installer/scripts/common.ps1).
3. Contratos y estado:
   [`docs/README.md`](docs/README.md).
4. Fichas generadas de la raíz:
   [`README.md`](README.md) (descarga pública) y
   [`README_developers.md`](README_developers.md) (proceso de build).
   Se regeneran con [`config/Update-Readme.ps1`](config/Update-Readme.ps1).
5. Instrucciones cargadas por Cursor:
   [`.cursor/rules/`](.cursor/rules/).

No copies valores vivos de `versions.json` en documentación o scripts como una
segunda fuente canónica. Edita `config/*.template.md` y regenera; no edites
`README.md` ni `README_developers.md` a mano.

## Antes de modificar

| Tipo de cambio | Contexto que hay que leer |
| --- | --- |
| Versiones, URLs o dependencias | `config/versions.json`, `docs/PROJECT_SPECIFICATION.md`, `docs/DEVELOPMENT_AND_RELEASE.md` y `config/Update-Readme.ps1` |
| Scripts PowerShell | `docs/ARCHITECTURE.md`, `docs/CONSTITUTION.md` y `common.ps1` |
| Inno Setup o wizard | `docs/ARCHITECTURE.md`, `docs/CONSTITUTION.md` y ambos archivos `.iss` |
| Release o prueba | `docs/DEVELOPMENT_AND_RELEASE.md` y `docs/PROJECT_STATUS.md` |
| Alcance o principio de diseño | `docs/PROJECT_SPECIFICATION.md`, `docs/CONSTITUTION.md` y `docs/DECISIONS.md` |

## Invariantes resumidos

- Usar `build-installer.ps1` para construir; no compilar `DataForge.iss`
  directamente.
- Mantener el CPython privado bajo la instalación y no modificar un Python
  ajeno ni registrar el lanzador `py.exe`. El descubrimiento para VS Code usa
  una clave PEP 514 propia, no `PythonCore`.
- Persistir como rutas absolutas todas las entradas que DataForge añade al
  `PATH` y limpiar también las referencias heredadas `%VARIABLE%`.
- Detectar una instalación previa del mismo `AppId` y reemplazarla en la misma
  carpeta; no crear una segunda copia ni mezclar ámbitos de privilegios.
- Conservar la verificación de Java, Spark, winutils, `ipykernel` y una
  `SparkSession` local.
- Resolver CPython, PySpark e ipykernel en el build; la instalación en el PC no
  debe depender de PyPI.
- Tratar descargas, permisos, cancelación y desinstalación como cambios de alto
  impacto.

## Cierre de cambios

Tras verificar un cambio material, actualizar el documento relevante de
`docs/`, el estado factual y, si corresponde, el registro de decisiones. Si
cambiaron el manifiesto o las plantillas, regenerar las fichas de la raíz.
No afirmes que una prueba se ejecutó si solo se revisó el código.

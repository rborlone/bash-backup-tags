# CLAUDE.md

Colección de scripts de utilidad (bash) para operar clusters de Kubernetes y otras tareas. No es un repositorio git.

## Scripts

- `deploy-tags.sh` — Exporta las imágenes/tags de todos los Deployments de un cluster a un TSV y permite volver a aplicarlas.
  - `./deploy-tags.sh export [-c contexto] [-n namespace] [-o archivo]`
  - `./deploy-tags.sh apply -f archivo [-c contexto] [-n namespace] [--dry-run]`
  - Por defecto excluye namespaces de sistema (`SYSTEM_NAMESPACES`: kube-*, cert-manager, gatekeeper-system, calico, etc.) tanto en `export` como en `apply` (`[EXCL]`). `-x/--exclude ns` añade más (repetible); `--include-system` desactiva la exclusión.
  - Formato TSV: `namespace  deployment  tipo(container|init)  contenedor  imagen`; líneas con `#` son comentarios.
  - `apply` agrupa por Deployment (un solo `kubectl set image` = un rollout), omite los que no cambian (`[=]`) y los que no existen (`[SKIP]`), y sale con código ≠ 0 si hubo `[FAIL]`.
- `RevisionSpark.sh` — script previo, no documentado aquí.
- `goback/` — directorio vacío por ahora.

## Dependencias

- `bash`, `kubectl`, `jq` (todos instalados vía Homebrew / sistema en macOS).

## Convenciones

- Scripts en bash con `set -euo pipefail`, comentarios y mensajes en español.
- Opciones con flags cortos y largos (`-c/--context`, `-n/--namespace`, ...) y `usage()` leyendo la cabecera del script.
- Usar `jq` para parsear JSON de `kubectl`, no `jsonpath` complejos.
- Cuidar compatibilidad con macOS (BSD `sed`/`awk`/`date`): evitar flags exclusivos de GNU.

## Seguridad al trabajar aquí

- Nunca ejecutar `apply` ni comandos que modifiquen el cluster sin confirmación explícita del usuario; para pruebas usar `--dry-run` o datos simulados con `jq`.
- Validar sintaxis con `bash -n <script>` tras editar.
- Si `-c` no se indica, los scripts usan el contexto activo de kubectl: verificar con `kubectl config current-context`.

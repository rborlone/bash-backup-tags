#!/usr/bin/env bash
# Exporta las imágenes/tags de todos los Deployments de un cluster y permite volver a aplicarlas.
#
# Uso:
#   ./deploy-tags.sh export  [-c contexto] [-n namespace] [-o archivo] [-x ns]... [--include-system]
#   ./deploy-tags.sh apply   -f archivo [-c contexto] [-n namespace] [-x ns]... [--include-system] [--dry-run]
#
# Por defecto se excluyen los namespaces de sistema (kube-*, cert-manager, gatekeeper-system, ...).
#   -x/--exclude ns     excluye un namespace adicional (repetible)
#   --include-system    no excluye los namespaces de sistema
#
# Formato del archivo (TSV):
#   namespace  deployment  tipo(container|init)  contenedor  imagen

set -euo pipefail

CMD="${1:-}"; shift || true
CONTEXT=""
NAMESPACE=""
OUTFILE=""
INFILE=""
DRY_RUN=false
INCLUDE_SYSTEM=false
EXTRA_EXCLUDES=()

# Namespaces de sistema / infraestructura que no son de aplicación
SYSTEM_NAMESPACES=(
  kube-system kube-public kube-node-lease
  cert-manager gatekeeper-system
  calico-system tigera-operator
  app-routing-system aks-command
)

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--context)   CONTEXT="$2"; shift 2 ;;
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    -o|--output)    OUTFILE="$2"; shift 2 ;;
    -f|--file)      INFILE="$2"; shift 2 ;;
    -x|--exclude)   EXTRA_EXCLUDES+=("$2"); shift 2 ;;
    --include-system) INCLUDE_SYSTEM=true; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    -h|--help)      usage ;;
    *) echo "Opción desconocida: $1" >&2; usage ;;
  esac
done

KUBECTL=(kubectl)
[[ -n "$CONTEXT" ]] && KUBECTL+=(--context "$CONTEXT")

# Lista final de namespaces excluidos, separada por espacios
EXCLUDED=""
$INCLUDE_SYSTEM || EXCLUDED="${SYSTEM_NAMESPACES[*]}"
[[ ${#EXTRA_EXCLUDES[@]} -gt 0 ]] && EXCLUDED="$EXCLUDED ${EXTRA_EXCLUDES[*]}"
EXCLUDED="${EXCLUDED# }"

is_excluded() { [[ " $EXCLUDED " == *" $1 "* ]]; }

export_tags() {
  local ctx scope
  ctx="${CONTEXT:-$(kubectl config current-context)}"
  if [[ -n "$NAMESPACE" ]]; then scope=(-n "$NAMESPACE"); else scope=(-A); fi
  [[ -z "$OUTFILE" ]] && OUTFILE="deploy-tags_${ctx//[^A-Za-z0-9._-]/_}_$(date +%Y%m%d_%H%M%S).tsv"

  {
    echo -e "# context=${ctx} fecha=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [[ -n "$EXCLUDED" ]] && echo "# excluidos=${EXCLUDED}"
    echo -e "#namespace\tdeployment\ttipo\tcontenedor\timagen"
    "${KUBECTL[@]}" get deployments "${scope[@]}" -o json | jq -r --arg ex "$EXCLUDED" '
      ($ex | split(" ")) as $excl
      | .items[] as $d
      | select(($excl | index($d.metadata.namespace)) | not)
      | ( ($d.spec.template.spec.initContainers // [])[] | ["init", .name, .image] ),
        ( $d.spec.template.spec.containers[]             | ["container", .name, .image] )
      | [$d.metadata.namespace, $d.metadata.name] + . | @tsv'
  } > "$OUTFILE"

  local n
  n=$(grep -vc '^#' "$OUTFILE" || true)
  echo "Exportadas $n imágenes desde '$ctx' a: $OUTFILE"
}

apply_tags() {
  [[ -z "$INFILE" || ! -f "$INFILE" ]] && { echo "Debes indicar un archivo válido con -f" >&2; exit 1; }

  local ctx
  ctx="${CONTEXT:-$(kubectl config current-context)}"
  echo "Aplicando imágenes de '$INFILE' en el contexto '$ctx' $($DRY_RUN && echo '(DRY-RUN)')"

  local dry=()
  $DRY_RUN && dry=(--dry-run=server)

  # Agrupa por namespace/deployment para hacer un solo 'set image' (un solo rollout) por deployment
  local ok=0 skip=0 fail=0
  while IFS=$'\t' read -r ns deploy pairs; do
    [[ -n "$NAMESPACE" && "$ns" != "$NAMESPACE" ]] && continue
    if is_excluded "$ns"; then
      echo "  [EXCL] $ns/$deploy namespace excluido"; skip=$((skip+1)); continue
    fi

    if ! "${KUBECTL[@]}" -n "$ns" get deployment "$deploy" >/dev/null 2>&1; then
      echo "  [SKIP] $ns/$deploy no existe en el cluster"; skip=$((skip+1)); continue
    fi

    # Solo cambia si alguna imagen difiere de la actual
    local current wanted
    current=$("${KUBECTL[@]}" -n "$ns" get deployment "$deploy" -o json \
      | jq -r '[(.spec.template.spec.initContainers // [])[], .spec.template.spec.containers[]] | map("\(.name)=\(.image)") | sort | join(" ")')
    wanted=$(tr ' ' '\n' <<<"$pairs" | sort | paste -sd' ' -)
    if [[ "$current" == "$wanted" ]]; then
      echo "  [=]    $ns/$deploy sin cambios"; skip=$((skip+1)); continue
    fi

    # shellcheck disable=SC2086
    if "${KUBECTL[@]}" -n "$ns" set image "deployment/$deploy" $pairs "${dry[@]}" >/dev/null; then
      echo "  [OK]   $ns/$deploy -> $pairs"; ok=$((ok+1))
    else
      echo "  [FAIL] $ns/$deploy"; fail=$((fail+1))
    fi
  done < <(grep -v '^#' "$INFILE" | awk -F'\t' 'NF>=5 {
      key=$1 "\t" $2
      pairs[key] = (key in pairs ? pairs[key] " " : "") $4 "=" $5
    } END { for (k in pairs) print k "\t" pairs[k] }' | sort)

  echo "Resumen: $ok actualizados, $skip sin cambios/omitidos, $fail con error"
  [[ $fail -eq 0 ]]
}

case "$CMD" in
  export) export_tags ;;
  apply)  apply_tags ;;
  *) usage ;;
esac

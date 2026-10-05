# bash-backup-tags

Respaldo y restauración de las imágenes (tags) de los Deployments de un cluster de Kubernetes.

`deploy-tags.sh` exporta a un archivo TSV la imagen de cada contenedor (incluidos los `initContainers`) de todos los Deployments, y permite volver a aplicar ese archivo sobre el mismo cluster u otro. Sirve para:

- Guardar una "foto" de las versiones desplegadas antes de un cambio y poder volver atrás.
- Copiar las versiones de un ambiente a otro (por ejemplo, de preprod a dev).
- Comparar ambientes con un `diff` entre dos exportaciones.

## Requisitos

- `bash`
- `kubectl` con acceso al cluster (usa el contexto activo si no se indica `-c`)
- `jq`

En macOS: `brew install kubectl jq`.

## Uso

```bash
./deploy-tags.sh export [-c contexto] [-n namespace] [-o archivo] [-x ns]... [--include-system]
./deploy-tags.sh apply  -f archivo [-c contexto] [-n namespace] [-x ns]... [--include-system] [--dry-run]
```

| Opción | Descripción |
|---|---|
| `-c, --context` | Contexto de kubectl. Si se omite, se usa el activo (`kubectl config current-context`). |
| `-n, --namespace` | Limita la operación a un namespace. Por defecto, todos. |
| `-o, --output` | Archivo de salida de `export`. Por defecto `deploy-tags_<contexto>_<fecha>.tsv`. |
| `-f, --file` | Archivo TSV a aplicar (obligatorio en `apply`). |
| `-x, --exclude` | Excluye un namespace adicional. Se puede repetir. |
| `--include-system` | No excluye los namespaces de sistema. |
| `--dry-run` | En `apply`, valida contra el servidor (`--dry-run=server`) sin modificar nada. |
| `-h, --help` | Muestra la ayuda. |

### Exportar

```bash
# Todo el cluster del contexto activo
./deploy-tags.sh export

# Un contexto y namespace concretos, a un archivo elegido
./deploy-tags.sh export -c aks-dev -n mi-app -o respaldo.tsv
```

### Aplicar

Prueba siempre primero con `--dry-run`:

```bash
./deploy-tags.sh apply -f respaldo.tsv -c aks-dev --dry-run
./deploy-tags.sh apply -f respaldo.tsv -c aks-dev
```

El comando `apply`:

- Agrupa las imágenes por Deployment y ejecuta un solo `kubectl set image` por cada uno, así cada Deployment hace un único rollout.
- Omite los Deployments cuyas imágenes ya coinciden (`[=]`), los que no existen en el cluster (`[SKIP]`) y los de namespaces excluidos (`[EXCL]`).
- Muestra `[OK]` o `[FAIL]` por Deployment, termina con un resumen y sale con código distinto de 0 si hubo algún error.

## Namespaces excluidos

Por defecto, tanto `export` como `apply` ignoran los namespaces de sistema o infraestructura:

```
kube-system kube-public kube-node-lease
cert-manager gatekeeper-system
calico-system tigera-operator
app-routing-system aks-command
```

Para excluir más namespaces usa `-x`. Para incluir también los de sistema usa `--include-system`. La lista está en la variable `SYSTEM_NAMESPACES` del script.

## Formato del archivo

TSV separado por tabuladores. Las líneas que empiezan con `#` son comentarios:

```
# context=aks-dev fecha=2026-10-04T15:33:50Z
# excluidos=kube-system kube-public ...
#namespace	deployment	tipo	contenedor	imagen
mi-app	api	init	migraciones	registry.example.com/api-migrations:1.4.2
mi-app	api	container	api	registry.example.com/api:1.4.2
mi-app	web	container	nginx	registry.example.com/web:2.0.1
```

`tipo` vale `container` o `init`. El archivo se puede editar a mano antes de aplicarlo, por ejemplo para quitar Deployments o cambiar tags.

> Los archivos `*.tsv` están en `.gitignore` porque contienen datos de los clusters.

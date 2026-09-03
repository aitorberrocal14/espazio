#!/usr/bin/env bash
# Aplica las migraciones en orden sobre la base indicada.
#   esquema/aplicar.sh <base>            aplica
#   esquema/aplicar.sh <base> revertir   revierte en orden inverso
# Conexión por las variables de libpq (PGHOST, PGPORT, PGUSER).
set -euo pipefail
BASE="${1:?uso: aplicar.sh <base> [revertir]}"
MODO="${2:-aplicar}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/migraciones"

if [ "$MODO" = "revertir" ]; then
  mapfile -t ARCHIVOS < <(ls "$DIR"/*.revertir.sql | sort -r)
else
  mapfile -t ARCHIVOS < <(ls "$DIR"/*.sql | grep -v '\.revertir\.sql$' | sort)
fi

for f in "${ARCHIVOS[@]}"; do
  psql --dbname="$BASE" --set=ON_ERROR_STOP=1 --quiet --file="$f"
done

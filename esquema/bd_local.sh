#!/usr/bin/env bash
# Levanta un clúster PostgreSQL local para desarrollo y para la suite de tests.
#   esquema/bd_local.sh arrancar | parar | estado
# No es despliegue: es lo mínimo para que los tests corran contra un Postgres real.
set -euo pipefail
PGDATA="${ESPAZIO_PGDATA:-/var/lib/postgresql/espazio}"
PUERTO="${ESPAZIO_PGPORT:-5433}"
SOCKET="${ESPAZIO_PGSOCKET:-/var/run/postgresql}"
BIN="$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)"

case "${1:-arrancar}" in
  arrancar)
    mkdir -p "$SOCKET"; chown postgres:postgres "$SOCKET"
    if [ ! -s "$PGDATA/PG_VERSION" ]; then
      mkdir -p "$PGDATA"; chown postgres:postgres "$PGDATA"; chmod 700 "$PGDATA"
      su postgres -c "$BIN/initdb -D '$PGDATA' -U postgres --auth=trust -E UTF8 --locale=C" >/dev/null
    fi
    su postgres -c "$BIN/pg_ctl -D '$PGDATA' -o '-p $PUERTO -k $SOCKET' -l '$PGDATA/servidor.log' -w start" >/dev/null
    echo "PGHOST=$SOCKET PGPORT=$PUERTO PGUSER=postgres" ;;
  parar)  su postgres -c "$BIN/pg_ctl -D '$PGDATA' -w stop" >/dev/null || true ;;
  estado) su postgres -c "$BIN/pg_ctl -D '$PGDATA' status" ;;
  *) echo "uso: bd_local.sh arrancar|parar|estado" >&2; exit 2 ;;
esac

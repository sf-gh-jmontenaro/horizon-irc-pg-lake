#!/bin/bash
# Adapted from pg_lake/docker/scripts/entrypoint-pgduck-server.sh (v3.6.0).
# No static storage secrets: pg_lake passes Horizon-vended credentials per table.
set -euo pipefail
trap "exit 0" SIGINT SIGTERM

PGBASEDIR=${PGBASEDIR:-/home/postgres}
PG_MAJOR=${PG_MAJOR:-18}

mkdir -p ${PGBASEDIR}/pgduck_socket_dir ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/base/pgsql_tmp
sudo chown -R postgres:postgres ${PGBASEDIR}/pgduck_socket_dir ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/base/pgsql_tmp
sudo chmod 700 ${PGBASEDIR}/pgduck_socket_dir ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/base/pgsql_tmp

exec ${PGBASEDIR}/pgsql-${PG_MAJOR}/bin/pgduck_server \
  --cache_dir ~/cache \
  --unix_socket_directory ~/pgduck_socket_dir \
  --unix_socket_group postgres \
  --port 5332

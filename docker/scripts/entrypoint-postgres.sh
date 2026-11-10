#!/bin/bash
# Adapted from pg_lake/docker/scripts/entrypoint-postgres.sh (v3.6.0).
set -euo pipefail
trap "exit 0" SIGINT SIGTERM

PGBASEDIR=${PGBASEDIR:-/home/postgres}
PG_MAJOR=${PG_MAJOR:-18}
DATA=${PGBASEDIR}/pgsql-${PG_MAJOR}/data

mkdir -p ${DATA}/base/pgsql_tmp
sudo chown -R postgres:postgres ${DATA}/base/pgsql_tmp
sudo chmod 700 ${DATA}/base/pgsql_tmp

# Demo only: trust auth. The port is published on 127.0.0.1 only (see docker-compose.yml).
cat > ${DATA}/pg_hba.conf <<EOF
local all all trust
host  all all 0.0.0.0/0 trust
host  all all ::/0 trust
EOF

if ! grep -q "irc-demo settings" ${DATA}/postgresql.conf; then
  cat >> ${DATA}/postgresql.conf <<EOF
# irc-demo settings
listen_addresses = '*'
port = 5432
shared_preload_libraries = 'pg_extension_base'
pg_lake_engine.host = 'host=${PGBASEDIR}/pgduck_socket_dir port=5332'
EOF
fi

${PGBASEDIR}/pgsql-${PG_MAJOR}/bin/pg_ctl -D ${DATA} start -l ${DATA}/logfile -w
${PGBASEDIR}/pgsql-${PG_MAJOR}/bin/psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pg_lake CASCADE;"

tail -F ${DATA}/logfile

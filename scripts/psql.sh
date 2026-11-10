#!/usr/bin/env bash
# Runs a SQL file against the local pg_lake container, passing Horizon settings from .env.
# Usage: scripts/psql.sh postgres/01_attach.sql   (or no args for an interactive shell)
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

ARGS=(-v ON_ERROR_STOP=1
      -v "catalog_url=https://${SNOWFLAKE_ACCOUNT_HOST}/polaris/api/catalog"
      -v "pat=${HORIZON_PAT}"
      -v "ods_catalog_uri=${ODS_CATALOG_URI:-}"
      -v "ods_catalog=${ODS_CATALOG:-}"
      -v "ods_scope=${ODS_SCOPE:-}"
      -v "ods_pat=${ODS_PAT:-}")
if [[ $# -gt 0 ]]; then
  docker exec -i irc_demo_pg_lake psql -U postgres "${ARGS[@]}" -f - < "$1"
else
  docker exec -it irc_demo_pg_lake psql -U postgres
fi

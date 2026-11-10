#!/usr/bin/env bash
# End-to-end walkthrough. Assumes images are built (scripts/build_images.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
SNOW=(snow sql ${SNOW_CONNECTION:+-c "$SNOW_CONNECTION"})
pause() { [[ -n "${NO_PAUSE:-}" ]] || read -rp $'\n-- press enter: '"$1"' --'; }

pause "1. Provider: create Snowflake-managed Iceberg tables"
"${SNOW[@]}" -f snowflake/01_setup.sql

pause "2. Onboard a consumer (role + service user + PAT)"
[[ -f .env ]] && grep -q HORIZON_PAT .env || bash scripts/create_pat.sh

pause "3. Start the client's local Postgres + pg_lake"
docker compose -f docker/docker-compose.yml up -d --wait

pause "4. Attach the tables from Horizon IRC"
bash scripts/psql.sh postgres/01_attach.sql

pause "5. Query in place, join local data, add local indexes/constraints"
bash scripts/psql.sh postgres/02_queries.sql

pause "6. Provider publishes new data and a schema change"
"${SNOW[@]}" -f snowflake/03_updates.sql

pause "7. Consumer sees it on the next query"
bash scripts/psql.sh postgres/03_after_updates.sql

pause "8. Open Data Sharing: external consumer + share + listing"
grep -q ODS_PAT .env || bash scripts/create_open_sharing.sh

pause "9. Re-point pg_lake at the listing's catalog as an external consumer"
bash scripts/psql.sh postgres/04_attach_open_sharing.sql

#!/usr/bin/env bash
# Runs snowflake/02_consumer.sql and stores the one-time PAT in .env (gitignored).
set -euo pipefail
cd "$(dirname "$0")/.."
CONN="${SNOW_CONNECTION:-}"
CONN_ARGS=()
[[ -n "$CONN" ]] && CONN_ARGS=(-c "$CONN")

OUT=$(snow sql "${CONN_ARGS[@]}" --format json -f snowflake/02_consumer.sql)
PAT=$(printf '%s' "$OUT" | python3 -c '
import sys, json
for result in json.load(sys.stdin):
    for row in (result or []):
        if "token_secret" in row:
            print(row["token_secret"]); sys.exit(0)
sys.exit("no token_secret in output")')

ACCOUNT=$(snow sql "${CONN_ARGS[@]}" --format json \
  -q "SELECT LOWER(REPLACE(CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME(), '_', '-')) AS A" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["A"])')

touch .env
grep -v -E '^(SNOWFLAKE_ACCOUNT_HOST|HORIZON_PAT)=' .env > .env.tmp || true
{
  cat .env.tmp
  echo "SNOWFLAKE_ACCOUNT_HOST=${ACCOUNT}.snowflakecomputing.com"
  echo "HORIZON_PAT=${PAT}"
} > .env
rm -f .env.tmp
chmod 600 .env
echo "Wrote SNOWFLAKE_ACCOUNT_HOST and HORIZON_PAT to .env"

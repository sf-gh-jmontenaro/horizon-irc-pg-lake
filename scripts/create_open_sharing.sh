#!/usr/bin/env bash
# Runs snowflake/04_open_sharing.sql, then stores the external consumer's PAT and
# catalog connection values in .env (gitignored). Secrets are never printed.
set -euo pipefail
cd "$(dirname "$0")/.."
CONN_ARGS=()
[[ -n "${SNOW_CONNECTION:-}" ]] && CONN_ARGS=(-c "$SNOW_CONNECTION")

OUT=$(snow sql "${CONN_ARGS[@]}" --format json -f snowflake/04_open_sharing.sql)

printf '%s' "$OUT" | python3 -c '
import sys, json, re
results = json.load(sys.stdin)
env = {}
for result in results:
    for row in (result or []):
        for k, v in row.items():
            lk = k.lower()
            if lk == "token_secret":
                env["ODS_PAT"] = v
            elif isinstance(v, str) and v.lstrip().startswith("{") and "catalog_uri" in v:
                d = json.loads(v)
                env.update({"ODS_CATALOG": d["catalog"], "ODS_CATALOG_URI": d["catalog_uri"],
                            "ODS_SCOPE": d["scope"], "ODS_OAUTH_TOKEN_URI": d["oauth_token_uri"]})
            elif lk in ("catalog", "catalog_uri", "scope", "oauth_token_uri"):
                env["ODS_" + lk.upper()] = v
missing = [k for k in ("ODS_PAT", "ODS_CATALOG", "ODS_CATALOG_URI", "ODS_SCOPE", "ODS_OAUTH_TOKEN_URI") if k not in env]
if missing:
    # Show result shapes (not values) to debug parsing.
    for r in results:
        print("result columns:", sorted((r or [{}])[0].keys()) if r else [], file=sys.stderr)
    sys.exit("missing from output: " + ", ".join(missing))
with open(".env") as f:
    keep = [l for l in f if not l.startswith("ODS_")]
with open(".env", "w") as f:
    f.writelines(keep)
    for k, v in env.items():
        f.write(f"{k}={v}\n")
for k, v in env.items():
    print(k, "=", "<redacted>" if k == "ODS_PAT" else v)
'

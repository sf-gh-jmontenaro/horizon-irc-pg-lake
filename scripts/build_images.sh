#!/usr/bin/env bash
# Builds pg_lake + pgduck_server images from the official repo at a pinned release.
# Needs ~16 GB of Docker memory; the first build takes a long time (DuckDB compile).
set -euo pipefail
cd "$(dirname "$0")/../docker"

PG_LAKE_REF="${PG_LAKE_REF:-v3.6.0}"
PG_MAJOR="${PG_MAJOR:-18}"
ARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"

rm -rf pg_lake_src
git clone -q --depth 1 --branch "$PG_LAKE_REF" https://github.com/Snowflake-Labs/pg_lake.git pg_lake_src
# The Dockerfile clones pg_lake itself using ENV PG_LAKE_REF (defaults to main); pin it.
sed -i.bak "s/^ENV PG_LAKE_REF=.*/ENV PG_LAKE_REF=${PG_LAKE_REF}/" pg_lake_src/docker/Dockerfile

for target in pg_lake_postgres pgduck_server; do
  tag=$([[ $target == pg_lake_postgres ]] && echo pg_lake || echo pgduck-server)
  docker buildx build \
    --platform "linux/${ARCH}" \
    --target "$target" \
    --build-arg PG_MAJOR="$PG_MAJOR" \
    -t "${tag}:${PG_LAKE_REF}-pg${PG_MAJOR}" \
    --load --progress=plain \
    -f pg_lake_src/docker/Dockerfile pg_lake_src/docker
done
echo "Built pg_lake:${PG_LAKE_REF}-pg${PG_MAJOR} and pgduck-server:${PG_LAKE_REF}-pg${PG_MAJOR}"

# Horizon IRC → local Postgres (pg_lake), zero-copy

Snowflake-managed Iceberg tables on **Snowflake storage**, read in place by a **self-hosted
Postgres running [pg_lake](https://github.com/Snowflake-Labs/pg_lake)** through the
**Horizon Iceberg REST Catalog**. There's no loader and no copy. The client's Postgres
reads the provider's Parquet files directly, using short-lived storage credentials that
Horizon vends for each table.

```
Snowflake (provider)                         Client machine (Docker)
┌──────────────────────────────┐             ┌───────────────────────────────┐
│ Iceberg v2 tables            │  OAuth(PAT) │ Postgres 18 + pg_lake v3.6.0  │
│ EXTERNAL_VOLUME=             │◄────────────┤  catalog = 'rest' (horizon)   │
│   SNOWFLAKE_MANAGED          │  loadTable  │  read_only attached tables    │
│ Horizon IRC /polaris/api/... ├────────────►│  + local heap tables, MVs,    │
│ role IRC_DEMO_CONSUMER (RO)  │ vended S3   │    indexes, PK/FK             │
└──────────────────────────────┘  creds      └───────────────────────────────┘
```

## Verified in this demo

| Check | Result |
|---|---|
| Horizon vends credentials for tables on Snowflake storage | Yes. `loadTable` returns scoped, temporary S3 credentials for the table prefix |
| pg_lake attaches tables without defining columns | Yes, columns and types come from the catalog. Lowercase names resolve to Snowflake's uppercase |
| Row counts match Snowflake | 500 / 130,500 / 300 |
| Join Iceberg tables with local heap tables | Yes |
| Local indexes, constraints | On a materialized view or native table (Index Scan, sub-ms) |
| New rows / updates published in Snowflake | Visible on the next Postgres query, with no refresh step |
| Column added in Snowflake | **Queries fail** ("Schema mismatch … field count 8 vs 7") until the consumer re-attaches the table |
| Consumer can write or drop | No, HTTP 403 |

## Run it

Prerequisites: the `snow` CLI with a connection that can use ACCOUNTADMIN, plus Docker with about 16 GB of memory.

```bash
bash scripts/build_images.sh                 # one-time, long build (DuckDB compile) from pg_lake v3.6.0
export SNOW_CONNECTION=<your connection>
bash scripts/demo.sh                         # NO_PAUSE=1 to run straight through
```

Step by step:

| Step | Command |
|---|---|
| Provider tables + seed data | `snow sql -f snowflake/01_setup.sql` |
| Onboard a consumer (role, service user, PAT → `.env`) | `bash scripts/create_pat.sh` |
| Start the client Postgres | `docker compose -f docker/docker-compose.yml up -d --wait` |
| Attach the tables from Horizon | `bash scripts/psql.sh postgres/01_attach.sql` |
| Query, join, local indexes/constraints | `bash scripts/psql.sh postgres/02_queries.sql` |
| Provider publishes new data and adds a column | `snow sql -f snowflake/03_updates.sql` |
| Consumer sees the changes | `bash scripts/psql.sh postgres/03_after_updates.sql` |
| Interactive psql | `bash scripts/psql.sh` |
| Tear down | `snow sql -f snowflake/99_teardown.sql` and `docker compose -f docker/docker-compose.yml down -v` |

## How the connection works

```sql
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_host = 'https://<org>-<account>.snowflakecomputing.com/polaris/api/catalog';
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_auth_type = 'horizon';
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_client_secret = '<PAT>';
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_scope = 'session:role:IRC_DEMO_CONSUMER';
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_enable_vended_credentials = on;

CREATE TABLE market_data.daily_prices () USING iceberg
  WITH (catalog = 'rest', read_only = true, catalog_name = 'IRC_DEMO_DB', lowercase_column_names = true);
```

Notes:
- **Use the built-in `rest` catalog with `auth_type = 'horizon'`.** A `CREATE SERVER` catalog
  sends credentials as HTTP Basic auth, which Horizon rejects (HTTP 400). Horizon expects the
  PAT as `client_secret` in the form body. The built-in catalog is configured by a superuser
  and shared by every database user, so it's one Snowflake identity per Postgres instance.
- Use a hyphenated account host (`org-account-name`). Underscores in hostnames can break TLS validation.
- The PAT sits in `postgresql.auto.conf` inside the container. Treat it like a database password.

## Talking points

**Onboarding (provider):** publish datasets as Snowflake-managed Iceberg (v2). Per client,
create a read-only role, a `TYPE = SERVICE` user, a PAT restricted to that role, and a network
policy for the client's egress IPs. (This demo relaxes the network-policy requirement through
an authentication policy. Don't do that in production.)

**Onboarding (client):** install pg_lake (no official prebuilt image yet), set five settings,
and run one `CREATE TABLE … USING iceberg` per dataset. Columns are inferred from the catalog.

**Timeliness:** each Snowflake commit is a new snapshot, and the next Postgres statement reads it.
There are no load windows. Within one statement, every table reads one catalog version.
`REPEATABLE READ` pins a transaction to a snapshot.

**Schema evolution:** an added column breaks queries on the attached table until the
consumer drops and re-attaches it, and `DROP … CASCADE` also drops dependent views and MVs.
Providers need a change-notification contract, or clients need a re-attach job.

**Client customizations:** attached tables are read-only and can't carry indexes or
constraints. The pattern is to query in place for scans and aggregates, and to materialize
hot subsets into native tables or MVs for indexes, PK/FK and point lookups. Clients can
also freely join in their own heap tables.

**Limitations seen in pg_lake v3.6.0 or its docs:**
- No Iceberg v3 deletion vectors or nanosecond timestamps. Keep shared tables at v2 with `TIMESTAMP_*(6)`.
- Unsupported types include `geography`, `geometry` and `variant`.
- External-engine reads of Snowflake-managed storage carry per-request storage fees, and
  network latency and egress depend on where the client runs.
- Masking and row access policies weren't tested. Snowflake documents enforcing them for
  external engines only for specific engines (Spark), so share only data the role may see in full.

**Other RDBMS (MySQL/MariaDB, SQL Server, Oracle):** not tested here. None has pg_lake-style
Iceberg REST attach. Realistic path: keep Iceberg as the single source and turn the existing
loader into an incremental Iceberg reader that writes into each target.

**Raw file delivery:** Iceberg data files are Parquet, so raw delivery could be scoped
read access to the same files. But raw files skip the snapshot and delete semantics, and
the catalog's access control. Prefer catalog-mediated reads, and use bulk Parquet exports
(`COPY INTO @stage`) for backfills.

## Layout

```
snowflake/   01_setup.sql  02_consumer.sql  03_updates.sql  99_teardown.sql
docker/      docker-compose.yml  scripts/entrypoint-*.sh
postgres/    01_attach.sql  02_queries.sql  03_after_updates.sql
scripts/     build_images.sh  create_pat.sh  psql.sh  demo.sh
```

---

_Built with the help of [Snowflake Cortex Code](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code)._

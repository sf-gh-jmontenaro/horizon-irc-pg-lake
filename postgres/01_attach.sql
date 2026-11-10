-- Consumer side: attach Snowflake-managed Iceberg tables from Horizon IRC.
-- Run via scripts/psql.sh, which passes :catalog_url and :pat from .env.
-- Superuser-only settings (stored in postgresql.auto.conf inside the container).

ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_host = :'catalog_url';
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_auth_type = 'horizon';   -- PAT goes in the OAuth form body
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_client_secret = :'pat';
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_scope = 'session:role:IRC_DEMO_CONSUMER';
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_enable_vended_credentials = on;
SELECT pg_reload_conf();

-- Mirror the Snowflake schema; lowercase names resolve to Snowflake's uppercase identifiers.
CREATE SCHEMA IF NOT EXISTS market_data;

DROP TABLE IF EXISTS market_data.securities, market_data.daily_prices, market_data.corporate_actions;

CREATE TABLE market_data.securities () USING iceberg
  WITH (catalog = 'rest', read_only = true, catalog_name = 'IRC_DEMO_DB',
        lowercase_column_names = true);
CREATE TABLE market_data.daily_prices () USING iceberg
  WITH (catalog = 'rest', read_only = true, catalog_name = 'IRC_DEMO_DB',
        lowercase_column_names = true);
CREATE TABLE market_data.corporate_actions () USING iceberg
  WITH (catalog = 'rest', read_only = true, catalog_name = 'IRC_DEMO_DB',
        lowercase_column_names = true);

\d market_data.daily_prices

SELECT 'securities' AS t, count(*) FROM market_data.securities
UNION ALL SELECT 'daily_prices', count(*) FROM market_data.daily_prices
UNION ALL SELECT 'corporate_actions', count(*) FROM market_data.corporate_actions;

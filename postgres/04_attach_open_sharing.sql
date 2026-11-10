-- Consumer side, Open Data Sharing: attach the listing's catalog as an external consumer.
-- Run via scripts/psql.sh after scripts/create_open_sharing.sh has filled ODS_* in .env.
-- pg_lake has one built-in REST catalog, so this replaces the Horizon-user settings
-- from 01_attach.sql (tables attached there stop resolving until it is re-run).

ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_host = :'ods_catalog_uri';
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_auth_type = 'horizon';   -- PAT in the OAuth form body
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_client_secret = :'ods_pat';
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_scope = :'ods_scope';    -- session:role:external
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_enable_vended_credentials = on;
SELECT pg_reload_conf();

CREATE SCHEMA IF NOT EXISTS shared_market_data;
DROP TABLE IF EXISTS shared_market_data.securities, shared_market_data.daily_prices,
                     shared_market_data.corporate_actions CASCADE;

-- catalog_name is the listing's catalog identifier; namespace and table names
-- resolve to the provider's uppercase identifiers.
CREATE TABLE shared_market_data.securities () USING iceberg
  WITH (catalog = 'rest', read_only = true, catalog_name = :'ods_catalog',
        catalog_namespace = 'MARKET_DATA', lowercase_column_names = true);
CREATE TABLE shared_market_data.daily_prices () USING iceberg
  WITH (catalog = 'rest', read_only = true, catalog_name = :'ods_catalog',
        catalog_namespace = 'MARKET_DATA', lowercase_column_names = true);
CREATE TABLE shared_market_data.corporate_actions () USING iceberg
  WITH (catalog = 'rest', read_only = true, catalog_name = :'ods_catalog',
        catalog_namespace = 'MARKET_DATA', lowercase_column_names = true);

SELECT 'securities' AS t, count(*) FROM shared_market_data.securities
UNION ALL SELECT 'daily_prices', count(*) FROM shared_market_data.daily_prices
UNION ALL SELECT 'corporate_actions', count(*) FROM shared_market_data.corporate_actions;

SELECT s.sector, round(avg(p.close_px), 2) AS avg_close, sum(p.volume) AS volume
FROM shared_market_data.daily_prices p
JOIN shared_market_data.securities s USING (security_id)
WHERE p.price_date >= current_date - 30
GROUP BY s.sector ORDER BY volume DESC;

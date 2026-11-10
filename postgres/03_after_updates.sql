-- Consumer re-check after snowflake/03_updates.sql.

-- New rows: visible on the next query, no refresh or load step.
SELECT max(price_date) AS latest_day, count(*) AS rows FROM market_data.daily_prices;

-- Schema evolution: an attached table's columns are fixed when it is created. After the
-- provider adds a column, queries fail with "Schema mismatch ... field count 8 vs 7"
-- until the consumer re-attaches. Dependent local objects must be rebuilt as well.
DROP TABLE market_data.securities CASCADE;   -- also drops public.latest_prices
CREATE TABLE market_data.securities () USING iceberg
  WITH (catalog = 'rest', read_only = true, catalog_name = 'IRC_DEMO_DB',
        lowercase_column_names = true);

SELECT security_id, ticker, isin, issuer_name FROM market_data.securities
WHERE security_id IN (41, 42, 43) ORDER BY security_id;

-- Rebuild the local, indexed copy (in practice: on the client's own schedule).
CREATE MATERIALIZED VIEW public.latest_prices AS
SELECT p.security_id, s.ticker, s.isin, s.sector, p.price_date, p.close_px, p.volume
FROM market_data.daily_prices p
JOIN market_data.securities s USING (security_id)
WHERE p.price_date >= current_date - 30;
CREATE UNIQUE INDEX latest_prices_pk  ON public.latest_prices (security_id, price_date);
CREATE INDEX        latest_prices_tkr ON public.latest_prices (ticker, price_date DESC);

SELECT ticker, isin, price_date, close_px FROM public.latest_prices
WHERE ticker = 'TKR0042' ORDER BY price_date DESC LIMIT 2;

-- Consumer-side queries directly against the attached Iceberg tables (no copy).
\timing on

-- 1. Analytics straight off Snowflake-managed Iceberg (DuckDB executes the scan).
SELECT s.sector,
       count(DISTINCT s.security_id)          AS securities,
       round(avg(p.close_px), 2)              AS avg_close,
       sum(p.volume)                          AS total_volume
FROM market_data.daily_prices p
JOIN market_data.securities  s USING (security_id)
WHERE p.price_date >= current_date - 30
GROUP BY s.sector
ORDER BY total_volume DESC;

-- 2. Join remote Iceberg with a client-owned local heap table (e.g. a portfolio).
CREATE TABLE IF NOT EXISTS public.my_portfolio (
    security_id int PRIMARY KEY,
    shares      numeric(18,2) NOT NULL CHECK (shares > 0)
);
TRUNCATE public.my_portfolio;
INSERT INTO public.my_portfolio VALUES (1, 1000), (42, 250), (137, 5000), (499, 75);

SELECT s.ticker, pf.shares, p.close_px, round(pf.shares * p.close_px, 2) AS market_value
FROM public.my_portfolio pf
JOIN market_data.securities s USING (security_id)
JOIN market_data.daily_prices p USING (security_id)
WHERE p.price_date = (SELECT max(price_date) FROM market_data.daily_prices)
ORDER BY market_value DESC;

-- 3. Client customizations. Attached Iceberg tables are read-only and cannot carry
--    indexes or constraints, so materialize the hot subset locally and index that.
DROP MATERIALIZED VIEW IF EXISTS public.latest_prices;
CREATE MATERIALIZED VIEW public.latest_prices AS
SELECT p.security_id, s.ticker, s.sector, p.price_date, p.close_px, p.volume
FROM market_data.daily_prices p
JOIN market_data.securities s USING (security_id)
WHERE p.price_date >= current_date - 30;

CREATE UNIQUE INDEX latest_prices_pk  ON public.latest_prices (security_id, price_date);
CREATE INDEX        latest_prices_tkr ON public.latest_prices (ticker, price_date DESC);

-- Native table with PK/FK constraints, seeded from Iceberg.
DROP TABLE IF EXISTS public.security_master CASCADE;
CREATE TABLE public.security_master (
    security_id int PRIMARY KEY,
    ticker      text UNIQUE NOT NULL,
    sector      text NOT NULL
);
INSERT INTO public.security_master
SELECT security_id, ticker, sector FROM market_data.securities;
ALTER TABLE public.my_portfolio
  DROP CONSTRAINT IF EXISTS my_portfolio_security_fk,
  ADD CONSTRAINT my_portfolio_security_fk FOREIGN KEY (security_id) REFERENCES public.security_master;

-- Indexed point lookup on the local copy.
EXPLAIN (COSTS OFF) SELECT * FROM public.latest_prices WHERE ticker = 'TKR0042' ORDER BY price_date DESC LIMIT 1;
SELECT * FROM public.latest_prices WHERE ticker = 'TKR0042' ORDER BY price_date DESC LIMIT 1;

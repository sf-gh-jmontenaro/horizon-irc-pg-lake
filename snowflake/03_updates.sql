-- Provider publishes a new day of prices, corrects a record, and evolves the schema.
-- No action is needed on the consumer: the next query in Postgres reads the new snapshot.

USE ROLE IRC_DEMO_ADMIN;
USE WAREHOUSE IRC_DEMO_WH;
USE SCHEMA IRC_DEMO_DB.MARKET_DATA;

-- New trading day (today).
INSERT INTO DAILY_PRICES
SELECT SECURITY_ID, CURRENT_DATE(),
       ROUND(CLOSE_PX * 1.001, 4), ROUND(CLOSE_PX * 1.02, 4), ROUND(CLOSE_PX * 0.98, 4),
       ROUND(CLOSE_PX * (1 + UNIFORM(-0.03::FLOAT, 0.03::FLOAT, RANDOM())), 4),
       UNIFORM(10000, 5000000, RANDOM()),
       CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(6)
FROM DAILY_PRICES
WHERE PRICE_DATE = (SELECT MAX(PRICE_DATE) FROM DAILY_PRICES)
  AND PRICE_DATE < CURRENT_DATE();

-- Data correction (rewrites affected files; Iceberg v2 has no deletion vectors).
UPDATE SECURITIES SET ISSUER_NAME = 'Issuer 42 Holdings plc' WHERE SECURITY_ID = 42;

-- Schema evolution: new column, backfilled.
ALTER ICEBERG TABLE SECURITIES ADD COLUMN IF NOT EXISTS ISIN STRING;
UPDATE SECURITIES SET ISIN = 'XS' || LPAD(SECURITY_ID, 10, '0') WHERE ISIN IS NULL;

SELECT MAX(PRICE_DATE), COUNT(*) FROM DAILY_PRICES;

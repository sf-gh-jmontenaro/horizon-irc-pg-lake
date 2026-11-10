-- Open Data Sharing: share the same Iceberg tables with a non-Snowflake consumer
-- via SHARE + EXTERNAL LISTING, instead of a user/role in the provider account.
-- Run as ACCOUNTADMIN (or a role with CREATE EXTERNAL CONSUMER, CREATE SHARE, CREATE LISTING).

USE ROLE ACCOUNTADMIN;

-- Restricted identity for the outside party, bound to the provider's region.
CREATE EXTERNAL CONSUMER IF NOT EXISTS IRC_DEMO_EXT_CONSUMER;

-- Share: only Snowflake-managed Iceberg tables are visible to external consumers.
CREATE SHARE IF NOT EXISTS IRC_DEMO_SHARE;
GRANT USAGE ON DATABASE IRC_DEMO_DB TO SHARE IRC_DEMO_SHARE;
GRANT USAGE ON SCHEMA IRC_DEMO_DB.MARKET_DATA TO SHARE IRC_DEMO_SHARE;
GRANT SELECT ON TABLE IRC_DEMO_DB.MARKET_DATA.SECURITIES        TO SHARE IRC_DEMO_SHARE;
GRANT SELECT ON TABLE IRC_DEMO_DB.MARKET_DATA.DAILY_PRICES      TO SHARE IRC_DEMO_SHARE;
GRANT SELECT ON TABLE IRC_DEMO_DB.MARKET_DATA.CORPORATE_ACTIONS TO SHARE IRC_DEMO_SHARE;

-- Listing exposes the share as an Iceberg REST catalog named by catalog_identifier.
CREATE EXTERNAL LISTING IF NOT EXISTS IRC_DEMO_LISTING SHARE IRC_DEMO_SHARE AS
$$
title: "Market data (open sharing demo)"
description: "Snowflake-managed Iceberg tables shared with non-Snowflake consumers"
open_sharing:
  catalog_identifier: "irc-demo-market-data"
listing_terms:
  type: "OFFLINE"
external_targets:
  access:
    - external_consumers: [IRC_DEMO_EXT_CONSUMER]
$$;

DESC LISTING IRC_DEMO_LISTING;

-- PAT secret is returned once; scripts/create_open_sharing.sh writes it to .env.
ALTER EXTERNAL CONSUMER IRC_DEMO_EXT_CONSUMER ADD PAT IRC_DEMO_EXT_PAT;

-- catalog, catalog_uri, scope, oauth_token_uri for the consumer.
CALL SYSTEM$GET_LISTING_URL_FOR_EXTERNAL_CONSUMER('IRC_DEMO_LISTING', 'IRC_DEMO_EXT_CONSUMER');

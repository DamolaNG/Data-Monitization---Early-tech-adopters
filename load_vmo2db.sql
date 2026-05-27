-- Ingest early_tech_adopter_dataset CSVs into VMO2db.
-- Run from psql connected to VMO2db:
--   \i load_vmo2db.sql
-- \copy is client-side, so paths are relative to where you launched psql.
-- Launch psql from the project root:
--   psql -h 127.0.0.1 -p 5431 -d VMO2db -f load_vmo2db.sql

BEGIN;

DROP TABLE IF EXISTS sku_views;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS profiles;
DROP TABLE IF EXISTS product_catalog;

CREATE TABLE product_catalog (
    sku           TEXT PRIMARY KEY,
    product_name  TEXT NOT NULL,
    category      TEXT NOT NULL,
    launch_date   DATE NOT NULL
);

CREATE TABLE profiles (
    user_id              TEXT NOT NULL,
    snapshot_date        DATE NOT NULL,
    prefers_new_releases BOOLEAN NOT NULL,
    trade_in_member      BOOLEAN NOT NULL,
    PRIMARY KEY (user_id, snapshot_date)
);

CREATE TABLE orders (
    user_id   TEXT        NOT NULL,
    order_ts  TIMESTAMP   NOT NULL,
    sku       TEXT        NOT NULL,
    price     NUMERIC(10,2) NOT NULL
);

CREATE TABLE sku_views (
    user_id   TEXT      NOT NULL,
    event_ts  TIMESTAMP NOT NULL,
    sku       TEXT      NOT NULL
);

\copy product_catalog (sku, product_name, category, launch_date) FROM 'early_tech_adopter_dataset/product_catalog.csv' WITH (FORMAT csv, HEADER true);
\copy profiles (user_id, snapshot_date, prefers_new_releases, trade_in_member) FROM 'early_tech_adopter_dataset/profiles.csv' WITH (FORMAT csv, HEADER true);
\copy orders (user_id, order_ts, sku, price) FROM 'early_tech_adopter_dataset/orders.csv' WITH (FORMAT csv, HEADER true);
\copy sku_views (user_id, event_ts, sku) FROM 'early_tech_adopter_dataset/sku_views.csv' WITH (FORMAT csv, HEADER true);

COMMIT;

SELECT 'product_catalog' AS table_name, COUNT(*) AS rows FROM product_catalog
UNION ALL SELECT 'profiles',  COUNT(*) FROM profiles
UNION ALL SELECT 'orders',    COUNT(*) FROM orders
UNION ALL SELECT 'sku_views', COUNT(*) FROM sku_views;

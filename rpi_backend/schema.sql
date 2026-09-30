-- Gasoline station database schema (MySQL)
--
-- Run this once on the Raspberry Pi to create the database and table:
--   mysql -u root -p < schema.sql
--
-- The app keeps exactly ONE row (id = 1) that always holds the current
-- prices. Updates overwrite that row rather than inserting history rows,
-- which keeps app.py's read/write logic simple (no "get latest" queries).

CREATE DATABASE IF NOT EXISTS gasoline_station
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE gasoline_station;

CREATE TABLE IF NOT EXISTS fuel_prices (
  id INT PRIMARY KEY,
  diesel DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  unleaded DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  gasoline DECIMAL(4,2) NOT NULL DEFAULT 0.00,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    ON UPDATE CURRENT_TIMESTAMP
);

-- Seed the single row if it doesn't exist yet. Safe to re-run.
INSERT INTO fuel_prices (id, diesel, unleaded, gasoline)
VALUES (1, 0.00, 0.00, 0.00)
ON DUPLICATE KEY UPDATE id = id;

-- --- Recommended: a dedicated DB user instead of using root -------------
-- Uncomment and edit the password, then run the block below as root:
--
-- CREATE USER IF NOT EXISTS 'gasstation'@'localhost' IDENTIFIED BY 'CHANGE_ME';
-- GRANT SELECT, INSERT, UPDATE ON gasoline_station.* TO 'gasstation'@'localhost';
-- FLUSH PRIVILEGES;

"""
MySQL access for the gasoline station backend.

Uses `mysql-connector-python` (the official Oracle-maintained MySQL driver)
rather than a heavier ORM, since the schema is a single row. Opens a fresh
connection per call rather than pooling — at the request volume this app
sees (a handful of price reads/writes per user session), connection setup
overhead is negligible and this keeps the code simple and avoids stale
connection issues if MySQL restarts.
"""

import logging

import mysql.connector
from mysql.connector import Error as MySQLError

import config

logger = logging.getLogger(__name__)


def _connect():
    return mysql.connector.connect(**config.MYSQL_CONFIG)


def get_prices() -> dict:
    """
    Reads the current prices row. Returns
    {'diesel': float, 'unleaded': float, 'gasoline': float} or None if the
    database is unreachable or the row is missing (caller should treat
    None as "database disconnected").
    """
    try:
        conn = _connect()
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute(
                "SELECT diesel, unleaded, gasoline FROM fuel_prices WHERE id = 1"
            )
            row = cursor.fetchone()
            cursor.close()
            if row is None:
                return None
            return {
                "diesel": float(row["diesel"]),
                "unleaded": float(row["unleaded"]),
                "gasoline": float(row["gasoline"]),
            }
        finally:
            conn.close()
    except MySQLError:
        logger.exception("Failed to read prices from MySQL")
        return None


def set_price(fuel_type: str, price: float) -> bool:
    """
    Updates a single fuel type's price (fuel_type is one of 'diesel',
    'unleaded', 'gasoline' — validated by the caller before this is
    called, since it's interpolated into the column name). Returns True
    on success, False on any database error.
    """
    if fuel_type not in ("diesel", "unleaded", "gasoline"):
        raise ValueError(f"Invalid fuel_type: {fuel_type}")

    try:
        conn = _connect()
        try:
            cursor = conn.cursor()
            # fuel_type is restricted to the whitelist above, so this is
            # safe from SQL injection despite the f-string; the price
            # value itself is still parameterized.
            cursor.execute(
                f"UPDATE fuel_prices SET {fuel_type} = %s WHERE id = 1",
                (price,),
            )
            conn.commit()
            cursor.close()
            return True
        finally:
            conn.close()
    except MySQLError:
        logger.exception("Failed to write %s price to MySQL", fuel_type)
        return False


def check_connection() -> bool:
    """Quick reachability check used by GET /api/status."""
    try:
        conn = _connect()
        conn.close()
        return True
    except MySQLError:
        return False

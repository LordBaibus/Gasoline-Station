"""
Gasoline station Flask backend — runs on the Raspberry Pi.

Replaces the old ESP32 firmware's REST API. This process is the single
local server: it owns the MySQL connection AND drives the three TM1637
displays directly over GPIO, in the same request/response cycle — when
the app sets a price, this process writes it to MySQL and pushes it to
the physical display before returning, so a 200 response means both
"saved" and "shown on the pump" succeeded (or the response says which
one didn't).

Run directly for development:
    python app.py

Run in production with gunicorn (single worker — see the note above
DisplayController about GPIO handles being opened once per process):
    gunicorn -w 1 -b 0.0.0.0:5000 app:app
"""

import logging
import time

from flask import Flask, jsonify, request

import config
import db
from displays import controller as display_controller

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

_START_TIME = time.time()

VALID_FUEL_TYPES = ("diesel", "unleaded", "gasoline")


@app.route("/api/status", methods=["GET"])
def get_status():
    """
    Returns the current snapshot: server reachability (implicit — you got
    a response), database connectivity, current prices, and per-display
    write status. Shape mirrors the old ESP32 contract but drops `slots`
    entirely (no IR sensors in this architecture) and renames
    `esp32_connected` to `server_connected` / adds `db_connected`.
    """
    prices = db.get_prices()
    db_connected = prices is not None

    if not db_connected:
        # Database is down — report zeroed prices rather than fabricating
        # plausible-looking numbers, same philosophy as the old firmware's
        # StationStatus.disconnected().
        prices = {"diesel": 0.0, "unleaded": 0.0, "gasoline": 0.0}

    return jsonify(
        {
            "server_connected": True,
            "db_connected": db_connected,
            "uptime_ms": int((time.time() - _START_TIME) * 1000),
            "prices": prices,
            "displays": display_controller.status(),
        }
    )


@app.route("/api/prices", methods=["POST"])
def set_price():
    """
    Body: {"fuel_type": "diesel" | "unleaded" | "gasoline", "price": 65.75}

    Writes the new price to MySQL, then writes it to the matching TM1637
    display, synchronously, in that order. Response reports both outcomes
    so the app can tell the user precisely what happened if one half
    fails (e.g. saved to DB but the display didn't take the write).
    """
    body = request.get_json(silent=True) or {}
    fuel_type = body.get("fuel_type")
    price = body.get("price")

    if fuel_type not in VALID_FUEL_TYPES:
        return (
            jsonify(
                {
                    "error": f"fuel_type must be one of {VALID_FUEL_TYPES}",
                }
            ),
            400,
        )

    try:
        price = float(price)
    except (TypeError, ValueError):
        return jsonify({"error": "price must be a number"}), 400

    if price < 0 or price > 99.99:
        return jsonify({"error": "price must be between 0.00 and 99.99"}), 400

    price = round(price, 2)

    db_ok = db.set_price(fuel_type, price)
    display_ok = display_controller.write_price(fuel_type, price)

    status_code = 200 if (db_ok and display_ok) else 207  # 207: partial success

    return (
        jsonify(
            {
                "fuel_type": fuel_type,
                "price": price,
                "db_saved": db_ok,
                "display_updated": display_ok,
            }
        ),
        status_code,
    )


if __name__ == "__main__":
    app.run(host=config.HOST, port=config.PORT, debug=False)

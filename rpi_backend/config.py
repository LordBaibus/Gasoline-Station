"""
Central configuration for the gasoline station Flask backend.

Edit the values below to match your Raspberry Pi's wiring and MySQL
credentials. Keeping everything in one file makes it easy to find when
re-wiring the TM1637 displays or moving to a different MySQL user.
"""

import os

# --- MySQL connection ------------------------------------------------------
# Prefer environment variables in production (e.g. set them in the systemd
# unit file) so the password isn't committed to source control. Falls back
# to the literal defaults below for quick local testing.
MYSQL_CONFIG = {
    "host": os.environ.get("GASSTATION_DB_HOST", "localhost"),
    "user": os.environ.get("GASSTATION_DB_USER", "gasstation"),
    "password": os.environ.get("GASSTATION_DB_PASSWORD", "CHANGE_ME"),
    "database": os.environ.get("GASSTATION_DB_NAME", "gasoline_station"),
}

# --- TM1637 GPIO wiring ------------------------------------------------------
# BCM pin numbers. Each display needs its own CLK + DIO pair; DIO pins
# cannot be shared because each TM1637 needs to be addressed independently.
# chip_path is the Linux gpiod character device for the Pi's main GPIO
# bank — "/dev/gpiochip4" on a Raspberry Pi 5, "/dev/gpiochip0" on
# earlier Pi models (Pi 4, Pi 3, Zero 2 W, etc). Check yours with:
#   ls /dev/gpiochip*
#   gpioinfo   (from libgpiod-tools; shows which chip has your BCM pins)
GPIO_CHIP_PATH = os.environ.get("GASSTATION_GPIO_CHIP", "/dev/gpiochip0")

DISPLAY_PINS = {
    "diesel": {"clk": 23, "dio": 24},
    "unleaded": {"clk": 25, "dio": 26},
    "gasoline": {"clk": 27, "dio": 22},
}

# Display brightness, 0 (dim) to 7 (max).
DISPLAY_BRIGHTNESS = 4

# If no TM1637 hardware is attached (e.g. developing on a laptop), set this
# to True to skip GPIO calls entirely — the API still works and reports
# every display as "disconnected" instead of crashing on import.
GPIO_SIMULATION_MODE = os.environ.get("GASSTATION_SIMULATE_GPIO", "0") == "1"

# --- Server ------------------------------------------------------------
HOST = "0.0.0.0"
PORT = 5000

"""
TM1637 display control for the three fuel-price seven-segment displays.

Uses the `python-tm1637` package, which talks to the displays through the
modern Linux gpiod character-device interface (via `lgpio`/`gpiod` under
the hood) rather than the deprecated `RPi.GPIO` library — this matters on
a Raspberry Pi 5, where RPi.GPIO no longer works at all, and is the
forward-compatible choice on older Pis too.

TM1637 is a write-only protocol: there is no signal that comes back from
the display to confirm it received the data. So "connected" here means
"the last write to this display's GPIO pins completed without raising an
exception" — the same honest caveat the previous ESP32 firmware's status
JSON already documented, now enforced on the Python side instead.
"""

import logging

import config

logger = logging.getLogger(__name__)

try:
    import tm1637
except ImportError:  # pragma: no cover - only hit if the package is missing
    tm1637 = None
    logger.warning(
        "python-tm1637 is not installed; run `pip install python-tm1637`. "
        "Falling back to simulation mode for all displays."
    )


class DisplayController:
    """Owns the three TM1637 handles and tracks per-display write status."""

    def __init__(self):
        self._simulate = config.GPIO_SIMULATION_MODE or tm1637 is None
        self._displays = {}
        # 'connected' | 'disconnected' — updated after every write attempt.
        self._status = {name: "disconnected" for name in config.DISPLAY_PINS}

        if self._simulate:
            logger.info("DisplayController running in simulation mode (no GPIO).")
            return

        for name, pins in config.DISPLAY_PINS.items():
            try:
                display = tm1637.TM1637(
                    clk=pins["clk"],
                    dio=pins["dio"],
                    chip_path=config.GPIO_CHIP_PATH,
                )
                display.brightness(config.DISPLAY_BRIGHTNESS)
                self._displays[name] = display
            except Exception:
                logger.exception("Failed to initialize TM1637 display '%s'", name)
                self._displays[name] = None

    def write_price(self, name: str, price: float) -> bool:
        """
        Write a price (e.g. 65.75) to the given display ('diesel',
        'unleaded', or 'gasoline'). Shows it as a 4-digit number with the
        decimal point lit between the 2nd and 3rd digit, e.g. "6575" with
        a dot after position 1 reads as "65.75".

        Returns True if the write succeeded (or simulation mode is on),
        False otherwise. Updates internal status either way, which
        GET /api/status reads from.
        """
        if self._simulate:
            self._status[name] = "connected"
            logger.info("[simulated] %s display -> %.2f", name, price)
            return True

        display = self._displays.get(name)
        if display is None:
            self._status[name] = "disconnected"
            return False

        try:
            # Encode 65.75 as the integer 6575 with a decimal point after
            # the 2nd digit (index 1). python-tm1637's `.number()` handles
            # whole numbers; for a fixed 2-decimal price with a visible
            # point, `.write()` with raw segment data via `.encode_string()`
            # style helpers is more reliable across package versions, so we
            # build the digit list explicitly.
            clamped = max(0.0, min(99.99, price))
            whole = int(clamped)
            frac = round((clamped - whole) * 100)
            if frac == 100:  # rounding edge case, e.g. 65.995 -> 66.00
                whole += 1
                frac = 0
            digits = f"{whole:02d}{frac:02d}"

            segments = display.encode_string(digits)
            # Light the decimal point on the 2nd digit (index 1) by
            # setting its DP bit (0x80).
            segments[1] |= 0x80
            display.write(segments)

            self._status[name] = "connected"
            return True
        except Exception:
            logger.exception("Failed writing price to '%s' display", name)
            self._status[name] = "disconnected"
            return False

    def write_all(self, diesel: float, unleaded: float, gasoline: float) -> dict:
        """Writes all three prices and returns the resulting status dict."""
        self.write_price("diesel", diesel)
        self.write_price("unleaded", unleaded)
        self.write_price("gasoline", gasoline)
        return self.status()

    def status(self) -> dict:
        """Current per-display connection status, e.g.
        {'diesel': 'connected', 'unleaded': 'connected', 'gasoline': 'disconnected'}
        """
        return dict(self._status)


# Single shared instance used by app.py — TM1637 GPIO handles should only
# be opened once per process, not per-request.
controller = DisplayController()

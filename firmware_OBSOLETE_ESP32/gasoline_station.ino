/*
 * ============================================================================
 *  MINIATURE GASOLINE STATION — ESP32 Firmware
 * ============================================================================
 *  Board:      ESP32 Dev Module
 *  Role:       WiFi Access Point + REST API server
 *  Displays:   3x TM1637 4-digit 7-segment (Diesel, Unleaded, Gasoline)
 *  Sensors:    4x Digital IR obstacle sensors (Slot 1-4 occupancy)
 *  Storage:    Preferences (NVS) — prices persist across power loss
 *
 *  Companion:  Flutter app connects to this AP, polls GET /api/status
 *              every ~1.5s, and pushes price changes via POST /api/prices
 *
 *  Libraries required (Arduino IDE > Tools > Manage Libraries):
 *    - TM1637Display   by Avishay Orpaz  (search "TM1637")
 *    - ArduinoJson     by Benoit Blanchon (v6.x or v7.x)
 *    - ESPAsyncWebServer + AsyncTCP (via Library Manager or GitHub, see notes)
 *
 *  NOTE ON WEB SERVER LIBRARY:
 *    This sketch uses ESPAsyncWebServer (async, non-blocking) because the
 *    IR sensors and TM1637 refresh need to run smoothly *while* the app is
 *    polling — the built-in synchronous WebServer.h would stall sensor
 *    reads during HTTP handling. If ESPAsyncWebServer is unavailable in
 *    your environment, see the fallback note at the bottom of this file.
 * ============================================================================
 */

#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <TM1637Display.h>

// ============================================================================
//  CONFIGURATION
// ============================================================================

// --- WiFi Access Point credentials ---
// The phone running the Flutter app connects directly to this AP.
const char* AP_SSID     = "GasStation_ESP32";
const char* AP_PASSWORD = "station1234";   // min 8 chars required by WiFi lib
IPAddress AP_LOCAL_IP(192, 168, 4, 1);
IPAddress AP_GATEWAY(192, 168, 4, 1);
IPAddress AP_SUBNET(255, 255, 255, 0);

// --- TM1637 pin assignments (see pin diagram in project notes) ---
// Each display needs its own CLK/DIO pair — no bus sharing on this chip.
#define DIESEL_CLK    18
#define DIESEL_DIO    19
#define UNLEADED_CLK  22
#define UNLEADED_DIO  23
#define GASOLINE_CLK  25
#define GASOLINE_DIO  26

// --- IR sensor pins (digital, active states depend on module — see NOTE) ---
// Most cheap IR obstacle modules pull the OUT pin LOW when an object is
// detected (active-low). If your specific module is active-high, flip
// IR_ACTIVE_STATE below — do not rewire, just change this one constant.
#define IR_SLOT_1_PIN  32
#define IR_SLOT_2_PIN  33
#define IR_SLOT_3_PIN  27
#define IR_SLOT_4_PIN  14
const int IR_ACTIVE_STATE = LOW;   // LOW = object detected (occupied). Set to HIGH if your module is active-high.

// --- Faulty-sensor heuristic tuning ---
// A sensor is flagged "faulty" if it hasn't changed state in this window
// WHILE at least one other sensor has toggled. This is a software guess,
// not a hardware self-test — see the doc comment above readIrSensors().
const unsigned long STUCK_THRESHOLD_MS = 5UL * 60UL * 1000UL;  // 5 minutes

// --- Price display formatting ---
// TM1637 has no arbitrary decimal placement — we show price as an integer
// with a decimal point segment lit after the 2nd digit, e.g. 72.50 -> "7250"
// with DP after position 2. Prices are stored internally as float pesos.
const float DEFAULT_DIESEL_PRICE   = 58.50f;
const float DEFAULT_UNLEADED_PRICE = 65.75f;
const float DEFAULT_GASOLINE_PRICE = 68.90f;
const float MIN_PRICE = 0.00f;
const float MAX_PRICE = 999.99f;   // 4-digit display ceiling (9999 -> 99.99... wait see note)
// NOTE: with format DDD.DD folded into 4 digits as DDDD (2 decimal implied),
// max representable is 99.99 if we want 2 whole digits + 2 decimal digits.
// Philippine fuel prices (as of writing) comfortably fit in this range.
// If prices exceed 99.99, the display will show truncated/wrapped digits —
// validated server-side in setPrice() below.

// ============================================================================
//  GLOBAL STATE
// ============================================================================

AsyncWebServer server(80);
Preferences prefs;

TM1637Display dieselDisplay(DIESEL_CLK, DIESEL_DIO);
TM1637Display unleadedDisplay(UNLEADED_CLK, UNLEADED_DIO);
TM1637Display gasolineDisplay(GASOLINE_CLK, GASOLINE_DIO);

float dieselPrice, unleadedPrice, gasolinePrice;

struct IrSensorState {
  int pin;
  bool occupied;          // current debounced reading
  bool lastRawState;      // last raw digitalRead value (for stuck detection)
  unsigned long lastChangeMs;  // millis() timestamp of last state change
  bool faulty;
};

IrSensorState irSensors[4];
unsigned long lastGlobalToggleMs = 0;  // tracks if ANY sensor toggled recently

// ============================================================================
//  FORWARD DECLARATIONS
// ============================================================================
void loadPricesFromNvs();
void savePricesToNvs();
void updateAllDisplays();
void updateDisplay(TM1637Display &disp, float price);
void initIrSensors();
void readIrSensors();
void setupRoutes();
String buildStatusJson();
bool setPrice(const String &fuelType, float newPrice, String &errorMsg);

// ============================================================================
//  SETUP
// ============================================================================
void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\n[BOOT] Miniature Gasoline Station starting...");

  // --- Load persisted prices (falls back to defaults on first boot) ---
  loadPricesFromNvs();

  // --- Init TM1637 displays ---
  dieselDisplay.setBrightness(0x0f);   // max brightness (0x00-0x0f)
  unleadedDisplay.setBrightness(0x0f);
  gasolineDisplay.setBrightness(0x0f);
  updateAllDisplays();

  // --- Init IR sensors ---
  initIrSensors();

  // --- Start WiFi Access Point ---
  WiFi.mode(WIFI_AP);
  WiFi.softAPConfig(AP_LOCAL_IP, AP_GATEWAY, AP_SUBNET);
  bool apOk = WiFi.softAP(AP_SSID, AP_PASSWORD);
  Serial.printf("[WIFI] AP '%s' started: %s | IP: %s\n",
                AP_SSID, apOk ? "OK" : "FAILED",
                WiFi.softAPIP().toString().c_str());

  // --- REST routes ---
  setupRoutes();
  server.begin();
  Serial.println("[HTTP] Server started on port 80");
  Serial.println("[BOOT] Ready.\n");
}

// ============================================================================
//  LOOP
// ============================================================================
void loop() {
  readIrSensors();
  // AsyncWebServer handles requests in the background — no server.handleClient()
  // call needed here, unlike the synchronous WebServer.h library.
  delay(50);  // light debounce/poll cadence for IR reads; keeps loop responsive
}

// ============================================================================
//  NVS PRICE PERSISTENCE
// ============================================================================
void loadPricesFromNvs() {
  prefs.begin("gasstation", false);  // namespace "gasstation", read-write
  dieselPrice   = prefs.getFloat("diesel",   DEFAULT_DIESEL_PRICE);
  unleadedPrice = prefs.getFloat("unleaded", DEFAULT_UNLEADED_PRICE);
  gasolinePrice = prefs.getFloat("gasoline", DEFAULT_GASOLINE_PRICE);
  prefs.end();
  Serial.printf("[NVS] Loaded prices — Diesel: %.2f, Unleaded: %.2f, Gasoline: %.2f\n",
                dieselPrice, unleadedPrice, gasolinePrice);
}

void savePricesToNvs() {
  prefs.begin("gasstation", false);
  prefs.putFloat("diesel", dieselPrice);
  prefs.putFloat("unleaded", unleadedPrice);
  prefs.putFloat("gasoline", gasolinePrice);
  prefs.end();
  Serial.println("[NVS] Prices saved to flash.");
}

// ============================================================================
//  TM1637 DISPLAY UPDATES
// ============================================================================
// Encodes a price like 72.50 into "7250" with the decimal point lit after
// the 2nd digit (i.e., between digit index 1 and 2, zero-indexed).
void updateDisplay(TM1637Display &disp, float price) {
  if (price < 0) price = 0;
  if (price > 99.99f) price = 99.99f;  // clamp to what 4 digits + implied 2dp can show

  int wholePart = (int)price;
  int decPart = (int)round((price - wholePart) * 100.0f);
  if (decPart >= 100) { decPart = 0; wholePart += 1; }  // rounding carry
  int displayValue = wholePart * 100 + decPart;

  // showNumberDecEx(value, dot_mask, leading_zeros, length, start_pos)
  // dot_mask: bit for each digit position, 0x80 = digit 0 (leftmost) dot on.
  // We want the dot after digit index 1 (0-indexed), which lights digit 1's DP.
  // Segment bit layout per TM1637Display lib: dot for position N = (0x80 >> N).
  uint8_t dotMask = 0x80 >> 1;  // dot after the 2nd digit from the left
  disp.showNumberDecEx(displayValue, dotMask, true, 4, 0);
}

void updateAllDisplays() {
  updateDisplay(dieselDisplay, dieselPrice);
  updateDisplay(unleadedDisplay, unleadedPrice);
  updateDisplay(gasolineDisplay, gasolinePrice);
}

// ============================================================================
//  IR SENSOR HANDLING
// ============================================================================
void initIrSensors() {
  int pins[4] = { IR_SLOT_1_PIN, IR_SLOT_2_PIN, IR_SLOT_3_PIN, IR_SLOT_4_PIN };
  for (int i = 0; i < 4; i++) {
    irSensors[i].pin = pins[i];
    pinMode(irSensors[i].pin, INPUT);
    bool raw = (digitalRead(irSensors[i].pin) == IR_ACTIVE_STATE);
    irSensors[i].occupied = raw;
    irSensors[i].lastRawState = raw;
    irSensors[i].lastChangeMs = millis();
    irSensors[i].faulty = false;
  }
  lastGlobalToggleMs = millis();
}

/*
 * FAULTY-SENSOR DETECTION — HEURISTIC, NOT A HARDWARE SELF-TEST.
 * ----------------------------------------------------------------
 * A digital IR obstacle sensor only reports HIGH or LOW — there's no
 * built-in "I am broken" signal. We approximate a fault condition as:
 *
 *   "This sensor's raw reading has not changed in STUCK_THRESHOLD_MS,
 *    WHILE at least one other sensor in the group DID change in that
 *    same window."
 *
 * Rationale: if all 4 sensors are silent, it's plausible the whole lot
 * is simply empty overnight — not evidence of a fault. But if sensors
 * 1, 2, and 4 are toggling normally as cars come and go, and sensor 3
 * has been frozen at the same value the entire time, that's a strong
 * signal something is wrong with sensor 3 specifically (disconnected
 * wire, dead emitter/receiver, stuck debris, etc).
 *
 * LIMITATIONS (please read before trusting this in production):
 *   - A sensor that is stuck-but-plausible (e.g. permanently reads
 *     "unoccupied" in a slot nobody ever uses) will NOT be caught.
 *   - This does not verify wiring continuity or power delivery —
 *     "disconnected" (no signal / floating pin) vs "faulty" (stuck
 *     reading) are both reported through this same heuristic since a
 *     floating INPUT pin without a pull resistor can read erratically
 *     rather than cleanly HIGH or LOW. For more reliable disconnect
 *     detection, wire a pull-down resistor on each IR OUT line and
 *     treat "always LOW, sensor's own group also idle" as disconnected
 *     rather than faulty — left as a hardware upgrade note.
 *   - Threshold (5 min default) is a starting point — tune to your
 *     expected traffic pattern.
 */
void readIrSensors() {
  unsigned long now = millis();
  bool anyToggledThisPass = false;

  // First pass: read raw states, detect toggles, update debounced occupancy
  for (int i = 0; i < 4; i++) {
    bool raw = (digitalRead(irSensors[i].pin) == IR_ACTIVE_STATE);
    if (raw != irSensors[i].lastRawState) {
      irSensors[i].lastRawState = raw;
      irSensors[i].occupied = raw;
      irSensors[i].lastChangeMs = now;
      anyToggledThisPass = true;
    }
  }

  if (anyToggledThisPass) {
    lastGlobalToggleMs = now;
  }

  // Second pass: apply the faulty heuristic using group context
  bool groupHasRecentActivity = (now - lastGlobalToggleMs) < STUCK_THRESHOLD_MS;
  for (int i = 0; i < 4; i++) {
    bool thisSensorStuck = (now - irSensors[i].lastChangeMs) >= STUCK_THRESHOLD_MS;
    // Only flag faulty if THIS sensor is stuck AND siblings show activity
    // (i.e., don't flag everything faulty just because the lot is empty).
    irSensors[i].faulty = thisSensorStuck && groupHasRecentActivity;
  }
}

// ============================================================================
//  PRICE VALIDATION + SETTING
// ============================================================================
bool setPrice(const String &fuelType, float newPrice, String &errorMsg) {
  if (isnan(newPrice) || newPrice < MIN_PRICE || newPrice > 99.99f) {
    errorMsg = "Price must be between 0.00 and 99.99";
    return false;
  }
  if (fuelType == "diesel") {
    dieselPrice = newPrice;
    updateDisplay(dieselDisplay, dieselPrice);
  } else if (fuelType == "unleaded") {
    unleadedPrice = newPrice;
    updateDisplay(unleadedDisplay, unleadedPrice);
  } else if (fuelType == "gasoline") {
    gasolinePrice = newPrice;
    updateDisplay(gasolineDisplay, gasolinePrice);
  } else {
    errorMsg = "Unknown fuel type: " + fuelType;
    return false;
  }
  savePricesToNvs();
  return true;
}

// ============================================================================
//  JSON STATUS BUILDER
// ============================================================================
String buildStatusJson() {
  JsonDocument doc;  // ArduinoJson v7 auto-sizing document

  doc["esp32_connected"] = true;  // if this response is returned at all, we're connected
  doc["uptime_ms"] = millis();

  JsonObject prices = doc["prices"].to<JsonObject>();
  prices["diesel"] = dieselPrice;
  prices["unleaded"] = unleadedPrice;
  prices["gasoline"] = gasolinePrice;

  // Display "connected" status: we can't read back from TM1637 (write-only
  // protocol), so "connected" here means "the ESP32 successfully issued a
  // write command to this display's pins during setup/last update" — i.e.
  // firmware-level presence, not a hardware ACK. See app-side note.
  JsonObject displays = doc["displays"].to<JsonObject>();
  displays["diesel"] = "connected";
  displays["unleaded"] = "connected";
  displays["gasoline"] = "connected";

  JsonArray slots = doc["slots"].to<JsonArray>();
  const char* slotNames[4] = { "Slot 1", "Slot 2", "Slot 3", "Slot 4" };
  for (int i = 0; i < 4; i++) {
    JsonObject slot = slots.add<JsonObject>();
    slot["id"] = i + 1;
    slot["name"] = slotNames[i];
    slot["occupied"] = irSensors[i].occupied;
    if (irSensors[i].faulty) {
      slot["sensor_status"] = "faulty";
    } else {
      slot["sensor_status"] = "connected";
    }
  }

  String output;
  serializeJson(doc, output);
  return output;
}

// ============================================================================
//  HTTP ROUTES
// ============================================================================
void setupRoutes() {
  // CORS preflight helper (harmless to include even on same-origin app use)
  auto addCors = [](AsyncWebServerResponse *response) {
    response->addHeader("Access-Control-Allow-Origin", "*");
    response->addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    response->addHeader("Access-Control-Allow-Headers", "Content-Type");
  };

  // --- GET /api/status ---
  // Full snapshot: prices, display status, slot occupancy, sensor health.
  // Polled by the app every ~1.5s.
  server.on("/api/status", HTTP_GET, [addCors](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response = request->beginResponse(
        200, "application/json", buildStatusJson());
    addCors(response);
    request->send(response);
  });

  // --- POST /api/prices ---
  // Body: { "fuelType": "diesel" | "unleaded" | "gasoline", "price": 72.50 }
  server.on("/api/prices", HTTP_POST,
    [addCors](AsyncWebServerRequest *request) {
      // handled in body callback below
    },
    nullptr,
    [addCors](AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
      JsonDocument doc;
      DeserializationError err = deserializeJson(doc, data, len);

      if (err) {
        JsonDocument errDoc;
        errDoc["success"] = false;
        errDoc["error"] = "Invalid JSON body";
        String out;
        serializeJson(errDoc, out);
        auto *res = request->beginResponse(400, "application/json", out);
        addCors(res);
        request->send(res);
        return;
      }

      String fuelType = doc["fuelType"] | "";
      float price = doc["price"] | -1.0f;

      String errorMsg;
      bool ok = setPrice(fuelType, price, errorMsg);

      JsonDocument resDoc;
      resDoc["success"] = ok;
      if (!ok) resDoc["error"] = errorMsg;
      else {
        JsonObject prices = resDoc["prices"].to<JsonObject>();
        prices["diesel"] = dieselPrice;
        prices["unleaded"] = unleadedPrice;
        prices["gasoline"] = gasolinePrice;
      }
      String out;
      serializeJson(resDoc, out);
      auto *res = request->beginResponse(ok ? 200 : 400, "application/json", out);
      addCors(res);
      request->send(res);
    }
  );

  // --- OPTIONS handler for CORS preflight on /api/prices ---
  server.on("/api/prices", HTTP_OPTIONS, [addCors](AsyncWebServerRequest *request) {
    auto *response = request->beginResponse(204);
    addCors(response);
    request->send(response);
  });

  // --- 404 fallback ---
  server.onNotFound([addCors](AsyncWebServerRequest *request) {
    auto *response = request->beginResponse(404, "application/json", "{\"error\":\"Not found\"}");
    addCors(response);
    request->send(response);
  });
}

/*
 * ============================================================================
 *  FALLBACK NOTE — if ESPAsyncWebServer / AsyncTCP won't install:
 * ============================================================================
 *  These two libraries are not in the default Arduino Library Manager index
 *  under those exact names on every IDE version — if Manage Libraries can't
 *  find them, install manually from GitHub (Sketch > Include Library > Add
 *  .ZIP Library) from the me-no-dev/ESPAsyncWebServer and me-no-dev/AsyncTCP
 *  repositories (or their actively maintained forks — search "ESPAsyncWebServer
 *  ESP32" for the current recommended fork, as the original repo has had
 *  several community forks over time).
 *
 *  If you'd rather avoid async libraries entirely, this sketch can be ported
 *  to the built-in synchronous WebServer.h with minor changes: replace
 *  AsyncWebServer with WebServer, change route handlers to the
 *  server.on(path, method, []() {...}) signature (no AsyncWebServerRequest*
 *  parameter — use server.arg("plain") for POST bodies instead), and add
 *  server.handleClient(); inside loop(). Ask me and I'll write that variant
 *  if your library install fails.
 * ============================================================================
 */

// =============================================================
// CrashTech VLSI-2026 — Challenge 4: Press Right (ESP32 side)
//
// Receives a 16-bit raw-tick count from the FPGA via UART and
// evaluates how close the user stopped at 10.00 s (1000 ticks
// of 10 ms each).
//
// Pin assignments (strictly within 12-14, 25-27, 32-35):
//   GPIO 33  — UART RX from FPGA ARDUINO_IO[1] (9600 8N1)
//   GPIO 26  — I2C SDA (SSD1306 OLED)
//   GPIO 27  — I2C SCL (SSD1306 OLED)
//   GPIO 14  — Buzzer (PWM via tone())
//   GPIO 12  — Feedback LED 0  (lit for delta < 1000)
//   GPIO 13  — Feedback LED 1  (lit for delta <  500)
//   GPIO 25  — Feedback LED 2  (lit for delta <  100)
//
// UART framing (sent by FPGA):
//   Byte 0 — count_bin[7:0]  (low byte, LSB first)
//   Byte 1 — count_bin[15:8] (high byte)
//   Reconstructed: count = (byte1 << 8) | byte0
//
// Win condition: abs(count - 1000) <= 10  (±100 ms)
// =============================================================

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// ---- Pin definitions ----------------------------------------
static constexpr int PIN_UART_RX = 33;
static constexpr int PIN_SDA     = 26;
static constexpr int PIN_SCL     = 27;
static constexpr int PIN_BUZZER  = 14;
static constexpr int PIN_LED0    = 12;   // proximity LED — closest
static constexpr int PIN_LED1    = 13;
static constexpr int PIN_LED2    = 25;   // proximity LED — widest band

// ---- Game parameters ----------------------------------------
static constexpr uint16_t TARGET_COUNT = 1000;  // 10.00 s
static constexpr uint16_t WIN_MARGIN   = 10;    // ±10 ticks = ±100 ms

// ---- OLED ---------------------------------------------------
static constexpr int SCREEN_W    = 128;
static constexpr int SCREEN_H    = 64;
static constexpr int OLED_ADDR   = 0x3C;

static Adafruit_SSD1306 oled(SCREEN_W, SCREEN_H, &Wire, -1);
static bool             oledOk = false;

// ---- UART receive state machine -----------------------------
enum class RxState : uint8_t { WAIT_LO, WAIT_HI };
static RxState  rxState = RxState::WAIT_LO;
static uint8_t  rxLo    = 0;

// ---- Non-blocking melody player -----------------------------
struct ToneNote {
    uint16_t freq_hz;
    uint16_t duration_ms;
};

static const ToneNote WIN_MELODY[] = {
    { 523,  150 },   // C5
    { 659,  150 },   // E5
    { 784,  150 },   // G5
    { 1047, 350 },   // C6
    { 0,    0   }    // sentinel — end of melody
};

static uint8_t  melodyIdx    = 0;
static uint32_t melodyStart  = 0;
static bool     melodyActive = false;

// ---- Forward declarations -----------------------------------
static void onPacketReceived(uint16_t count);
static void updateOled(uint16_t count, bool winner, uint16_t delta);
static void setLeds(uint16_t delta);
static void startWinMelody();
static void updateMelody();

// =============================================================
void setup() {
    Serial.begin(115200);
    Serial.println("[press_right] booting...");

    // UART2 from FPGA — RX only, no TX pin assigned
    Serial2.begin(9600, SERIAL_8N1, PIN_UART_RX, -1);

    // I2C for OLED (non-default pins)
    Wire.begin(PIN_SDA, PIN_SCL);

    // Buzzer
    pinMode(PIN_BUZZER, OUTPUT);
    digitalWrite(PIN_BUZZER, LOW);

    // Feedback LEDs
    pinMode(PIN_LED0, OUTPUT);  digitalWrite(PIN_LED0, LOW);
    pinMode(PIN_LED1, OUTPUT);  digitalWrite(PIN_LED1, LOW);
    pinMode(PIN_LED2, OUTPUT);  digitalWrite(PIN_LED2, LOW);

    // OLED init
    oledOk = oled.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR);
    if (!oledOk) {
        Serial.println("[!] OLED init failed — check SDA=26, SCL=27");
    } else {
        oled.clearDisplay();
        oled.setTextColor(SSD1306_WHITE);
        oled.setTextSize(2);
        oled.setCursor(16, 10);
        oled.print("PRESS");
        oled.setCursor(22, 34);
        oled.print("RIGHT");
        oled.display();
    }

    Serial.println("[press_right] ready — waiting for FPGA packet");
}

// =============================================================
void loop() {
    // -- Non-blocking UART receive state machine ---------------
    while (Serial2.available() > 0) {
        const uint8_t b = static_cast<uint8_t>(Serial2.read());

        switch (rxState) {
            case RxState::WAIT_LO:
                rxLo    = b;
                rxState = RxState::WAIT_HI;
                break;

            case RxState::WAIT_HI: {
                const uint16_t count =
                    (static_cast<uint16_t>(b) << 8) | rxLo;
                rxState = RxState::WAIT_LO;   // ready for next packet
                onPacketReceived(count);
                break;
            }
        }
    }

    // -- Advance non-blocking melody ---------------------------
    updateMelody();
}

// =============================================================
// onPacketReceived — called once per complete 16-bit UART packet
// =============================================================
static void onPacketReceived(const uint16_t count) {
    const uint16_t delta =
        (count >= TARGET_COUNT) ? (count - TARGET_COUNT)
                                 : (TARGET_COUNT - count);
    const bool winner = (delta <= WIN_MARGIN);

    Serial.printf("[RX] count=%u  delta=%u  %s\n",
                  count, delta, winner ? "WINNER" : "MISSED");

    updateOled(count, winner, delta);
    setLeds(delta);

    if (winner) {
        startWinMelody();
    }
}

// =============================================================
// updateOled — renders time, verdict and delta on 128×64 display
// =============================================================
static void updateOled(const uint16_t count,
                       const bool     winner,
                       const uint16_t delta) {
    if (!oledOk) return;

    // Decode centiseconds → seconds + sub-seconds
    const uint16_t sec_int  = count / 100u;
    const uint16_t sec_frac = count % 100u;

    char timeBuf[12];
    snprintf(timeBuf, sizeof(timeBuf), "%u.%02us", sec_int, sec_frac);

    char deltaBuf[24];
    snprintf(deltaBuf, sizeof(deltaBuf), "delta:%u ticks", delta);

    oled.clearDisplay();

    // Row 0 (y=0): time in size-2 font  — e.g. "10.05s"
    oled.setTextSize(2);
    oled.setCursor(0, 0);
    oled.print(timeBuf);

    // Row 1 (y=22): verdict in size-2 font — "WINNER" / "MISSED"
    oled.setTextSize(2);
    oled.setCursor(0, 22);
    oled.print(winner ? "WINNER" : "MISSED");

    // Row 2 (y=50): delta in size-1 font
    oled.setTextSize(1);
    oled.setCursor(0, 50);
    oled.print(deltaBuf);

    oled.display();
}

// =============================================================
// setLeds — maps proximity delta to 0-3 LEDs
//   delta < 100  → 3 LEDs (within ±1 second, very close)
//   delta < 500  → 2 LEDs
//   delta < 1000 → 1 LED
//   delta ≥ 1000 → 0 LEDs
// =============================================================
static void setLeds(const uint16_t delta) {
    const int n = (delta < 100u)  ? 3 :
                  (delta < 500u)  ? 2 :
                  (delta < 1000u) ? 1 : 0;

    digitalWrite(PIN_LED0, n >= 1 ? HIGH : LOW);
    digitalWrite(PIN_LED1, n >= 2 ? HIGH : LOW);
    digitalWrite(PIN_LED2, n >= 3 ? HIGH : LOW);
}

// =============================================================
// Non-blocking melody player — call updateMelody() every loop()
// =============================================================
static void startWinMelody() {
    melodyIdx   = 0;
    melodyStart = millis();
    melodyActive = true;
    tone(PIN_BUZZER, WIN_MELODY[0].freq_hz);
}

static void updateMelody() {
    if (!melodyActive) return;

    const uint32_t now = millis();
    if (now - melodyStart < WIN_MELODY[melodyIdx].duration_ms) return;

    // Current note finished
    noTone(PIN_BUZZER);
    melodyIdx++;

    if (WIN_MELODY[melodyIdx].freq_hz == 0) {
        // Sentinel reached — melody complete
        melodyActive = false;
        melodyIdx    = 0;
        return;
    }

    // Start next note
    melodyStart = now;
    tone(PIN_BUZZER, WIN_MELODY[melodyIdx].freq_hz);
}

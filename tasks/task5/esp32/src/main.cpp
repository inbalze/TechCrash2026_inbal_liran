// =============================================================
// CrashTech VLSI-2026 — Challenge 5: FPGA Volt-Meter (ESP32 side)
//
// Receives a 5-byte framed millivolt reading from the FPGA over
// UART and renders it as "X.XXV" on an SSD1306 OLED display.
//
// Frame format (5 bytes from FPGA):
//   [0x55][0xAA][VAL_H][VAL_L][CRC8]
//   VAL  = 16-bit millivolt value (0–3300)
//   CRC8 = XOR of bytes 0..3
//
// Pin assignments (only from allowed set 12-14, 25-27, 32-35):
//   GPIO 33 — UART RX from FPGA ARDUINO_IO[1] (115200, 8N1)
//   GPIO 26 — I2C SDA (SSD1306 OLED)
//   GPIO 27 — I2C SCL (SSD1306 OLED)
// =============================================================

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// ---- Pin definitions ----------------------------------------
static constexpr int PIN_UART_RX = 33;
static constexpr int PIN_SDA     = 26;
static constexpr int PIN_SCL     = 27;

// ---- OLED ---------------------------------------------------
static constexpr int SCREEN_W  = 128;
static constexpr int SCREEN_H  = 64;
static constexpr int OLED_ADDR = 0x3C;

static Adafruit_SSD1306 oled(SCREEN_W, SCREEN_H, &Wire, -1);
static bool             oledOk = false;

// ---- Frame parser -------------------------------------------
static constexpr int     FRAME_LEN = 5;
static constexpr uint8_t SYNC1     = 0x55;
static constexpr uint8_t SYNC2     = 0xAA;

enum class RxState : uint8_t {
    WAIT_SYNC1,
    WAIT_SYNC2,
    RECV_DATA      // collecting bytes 2..4
};

static RxState rxState = RxState::WAIT_SYNC1;
static uint8_t rxBuf[FRAME_LEN];
static int     rxCount = 0;   // bytes received in RECV_DATA phase

// ---- Display state ------------------------------------------
static uint16_t lastMv    = 0xFFFF;  // force first render
static bool     newReading = false;

// ---- Forward declarations -----------------------------------
static void onFrameReceived(const uint8_t* buf);
static void renderVoltage(uint16_t mv);

// =============================================================
void setup() {
    Serial.begin(115200);
    Serial.println("[volt_meter] boot");

    // UART2: RX-only from FPGA
    Serial2.begin(115200, SERIAL_8N1, PIN_UART_RX, -1);

    // I2C + OLED
    Wire.begin(PIN_SDA, PIN_SCL);
    Wire.setClock(400000);

    oledOk = oled.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR);
    if (!oledOk) {
        Serial.println("[!] OLED init failed — check SDA=26, SCL=27");
    } else {
        oled.clearDisplay();
        oled.setTextColor(SSD1306_WHITE);
        oled.setTextSize(1);
        oled.setCursor(28, 28);
        oled.print("Waiting...");
        oled.display();
    }
}

// =============================================================
void loop() {
    // ---- Non-blocking UART frame parser ----------------------
    while (Serial2.available() > 0) {
        const uint8_t b = static_cast<uint8_t>(Serial2.read());

        switch (rxState) {

            case RxState::WAIT_SYNC1:
                if (b == SYNC1) {
                    rxBuf[0] = b;
                    rxState  = RxState::WAIT_SYNC2;
                }
                break;

            case RxState::WAIT_SYNC2:
                if (b == SYNC2) {
                    rxBuf[1] = b;
                    rxCount  = 0;
                    rxState  = RxState::RECV_DATA;
                } else if (b == SYNC1) {
                    // Could be start of a new valid frame — stay in WAIT_SYNC2
                    rxBuf[0] = b;
                } else {
                    rxState = RxState::WAIT_SYNC1;
                }
                break;

            case RxState::RECV_DATA:
                rxBuf[2 + rxCount] = b;
                rxCount++;
                if (rxCount == FRAME_LEN - 2) {  // bytes 2..4 collected
                    rxState = RxState::WAIT_SYNC1;
                    onFrameReceived(rxBuf);
                }
                break;
        }
    }

    // ---- Non-blocking OLED update ----------------------------
    if (newReading) {
        newReading = false;
        renderVoltage(lastMv);
    }
}

// =============================================================
// onFrameReceived — verify CRC, extract millivolt value
// =============================================================
static void onFrameReceived(const uint8_t* buf) {
    // CRC check: XOR of bytes 0..3 must equal byte 4
    const uint8_t calcCrc = buf[0] ^ buf[1] ^ buf[2] ^ buf[3];
    if (calcCrc != buf[4]) {
        Serial.printf("[UART] CRC err: calc=0x%02X got=0x%02X\n",
                      calcCrc, buf[4]);
        return;
    }

    const uint16_t mv = (static_cast<uint16_t>(buf[2]) << 8) | buf[3];

    // Clamp to valid range
    if (mv > 3300u) return;

    // Only update display if value changed (avoids flicker on identical frames)
    if (mv != lastMv) {
        lastMv     = mv;
        newReading = true;
    }
}

// =============================================================
// renderVoltage — clear backbuffer, draw centred voltage string,
//                 flush to display in one shot (no flicker)
// =============================================================
static void renderVoltage(const uint16_t mv) {
    if (!oledOk) return;

    // Format: "X.XXV"  — always 5 characters
    char voltStr[8];
    const uint16_t v_int  = mv / 1000u;
    const uint16_t v_frac = mv % 1000u;
    snprintf(voltStr, sizeof(voltStr), "%u.%02uV",
             v_int, v_frac / 10u);   // tenths + hundredths only (2 decimal places)

    // textSize=3 → each char is 18×24 px; "X.XXV" = 5 chars × 18 = 90 px wide
    static constexpr int TEXT_SIZE = 3;
    static constexpr int CHAR_W    = 6 * TEXT_SIZE;   // 18 px per char
    static constexpr int CHAR_H    = 8 * TEXT_SIZE;   // 24 px per char
    const int strLen = strlen(voltStr);
    const int x = (SCREEN_W - strLen * CHAR_W) / 2;
    const int y = (SCREEN_H - CHAR_H) / 2;

    oled.clearDisplay();

    // Voltage value — large, centred
    oled.setTextSize(TEXT_SIZE);
    oled.setTextColor(SSD1306_WHITE);
    oled.setCursor(x, y);
    oled.print(voltStr);

    // Small bar graph at bottom (2 px per LED equivalent, 10 segments of ~330 mV)
    static constexpr int BAR_Y    = SCREEN_H - 6;
    static constexpr int BAR_H    = 4;
    static constexpr int BAR_MAXW = SCREEN_W - 4;

    const int barW = static_cast<int>(
        static_cast<uint32_t>(mv) * BAR_MAXW / 3300u);
    oled.fillRect(2, BAR_Y, barW, BAR_H, SSD1306_WHITE);
    oled.drawRect(2, BAR_Y, BAR_MAXW, BAR_H, SSD1306_WHITE);

    // Flush backbuffer to display in one I2C burst
    oled.display();

    Serial.printf("[OLED] %s  (%u mV)\n", voltStr, mv);
}

// =============================================================
// CrashTech VLSI-2026 — Challenge 3: Speed Loopback (Task 3)
// ESP32 ultra-low-latency firmware — 4.16 Mbps variant
//
// Protocol:
//   FPGA → ESP32 : 4-byte header (N, little-endian) + N random bytes
//   ESP32 → FPGA : 1 byte checksum = (Σ all N bytes) & 0xFF
//
// Critical path:
//   Last byte received → checksum written to UART TX FIFO
//   OLED updates happen AFTER the checksum is already on the wire.
//
// Pin assignments (all within authorised set [12,13,14,25,26,27,32,33,34,35]):
//   GPIO 32 — UART2 TX → FPGA ARDUINO_IO[0] (PIN_AB5)
//   GPIO 33 — UART2 RX ← FPGA ARDUINO_IO[1] (PIN_AB6)
//   GPIO 26 — I2C SDA (SSD1306 OLED)
//   GPIO 27 — I2C SCL (SSD1306 OLED)
//
// Baud rate: 4,166,666 bps
//   FPGA BIT_PERIOD = 50,000,000 / 12 = 4,166,666 bps
//   ESP32 APB = 80 MHz → divider ≈ 19.2 → actual ~4,169,000 bps (error < 0.06%)
//
// RX buffer: 8192 bytes (set before begin()) so the 10,000-byte stream
//   is safely absorbed even with brief scheduling jitter.
// =============================================================

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// ---- Pin definitions (authorised ESP32 GPIO subset) ---------
static constexpr int     PIN_FPGA_TX  = 32;      // ESP32 TX → FPGA RX
static constexpr int     PIN_FPGA_RX  = 33;      // ESP32 RX ← FPGA TX
static constexpr int     PIN_OLED_SDA = 26;
static constexpr int     PIN_OLED_SCL = 27;

// ---- UART parameters ----------------------------------------
static constexpr uint32_t FPGA_BAUD   = 4166666;
static constexpr size_t   RX_BUF_SIZE = 8192;    // must be > 10,000-byte stream

// ---- OLED ---------------------------------------------------
static constexpr int SCREEN_W  = 128;
static constexpr int SCREEN_H  = 64;
static constexpr int OLED_ADDR = 0x3C;

static Adafruit_SSD1306 oled(SCREEN_W, SCREEN_H, &Wire, -1);
static bool             oledOk = false;

static HardwareSerial FpgaSerial(2);   // UART2

// ---- Forward declarations -----------------------------------
static void oledStatus(const char* line1, const char* line2,
                       const char* line3, const char* line4);

// =============================================================
void setup() {
    // Debug UART on USB (independent of the FPGA UART)
    Serial.begin(115200);
    Serial.println("[speed_loopback] 4.16 Mbps boot");

    // Enlarge SW RX buffer BEFORE calling begin() — critical for burst absorption
    FpgaSerial.setRxBufferSize(RX_BUF_SIZE);
    FpgaSerial.begin(FPGA_BAUD, SERIAL_8N1, PIN_FPGA_RX, PIN_FPGA_TX);

    // OLED
    Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);
    Wire.setClock(400000);
    oledOk = oled.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR);
    if (!oledOk) {
        Serial.println("[!] OLED init failed");
    } else {
        oledStatus("Speed Loopback", "4.16 Mbps", "Waiting for FPGA...", "");
    }
}

// =============================================================
void loop() {
    // ==========================================================
    // PHASE 1: Wait for 4-byte header (tight spin — no delay)
    //   The header arrives at 4.16 Mbps; 4 bytes = 9.6 µs.
    //   Busy-wait is correct here: no sleep.
    // ==========================================================
    while (FpgaSerial.available() < 4) { /* spin */ }

    const uint32_t N =
          static_cast<uint32_t>(FpgaSerial.read())
        | static_cast<uint32_t>(FpgaSerial.read()) << 8
        | static_cast<uint32_t>(FpgaSerial.read()) << 16
        | static_cast<uint32_t>(FpgaSerial.read()) << 24;

    Serial.printf("[RX] header: N=%u\n", N);

    // ==========================================================
    // PHASE 2: Ingest N bytes and accumulate checksum
    //
    // Loop structure: outer while() spins until all bytes are
    // consumed; inner while() drains all bytes currently in the
    // HW FIFO in a burst to maximise throughput.
    //
    // No I/O, no OLED, no Serial.printf in this hot path.
    // ==========================================================
    uint32_t sum      = 0;
    uint32_t received = 0;

    while (received < N) {
        int avail = FpgaSerial.available();
        // Drain everything currently buffered
        while (avail > 0 && received < N) {
            sum += static_cast<uint8_t>(FpgaSerial.read());
            ++received;
            --avail;
        }
        // If nothing available yet, spin tightly (no yield/delay)
        // at 240 MHz the CPU outruns the UART by ~50× per byte
    }

    // ==========================================================
    // PHASE 3: Send checksum IMMEDIATELY — turnaround is critical
    //
    // FpgaSerial.write() places the byte directly into the HW TX
    // FIFO and returns in one instruction.  The byte starts
    // transmitting within the next bit clock (~240 ns).
    // flush() blocks until the byte is physically shifted out
    // (2.4 µs), which is fine — the timer stops at FPGA RX edge.
    // ==========================================================
    const uint8_t checksum = static_cast<uint8_t>(sum & 0xFF);
    FpgaSerial.write(checksum);
    FpgaSerial.flush();     // ensure byte is fully transmitted

    // ==========================================================
    // PHASE 4: Post-run display (does NOT affect FPGA timer)
    // ==========================================================
    Serial.printf("[TX] N=%u  sum=0x%08X  checksum=0x%02X\n",
                  N, sum, checksum);

    char line2[24], line3[24], line4[24];
    snprintf(line2, sizeof(line2), "N = %u", N);
    snprintf(line3, sizeof(line3), "CRC: 0x%02X", checksum);
    oledStatus("Speed Loopback OK", line2, line3, "4.16 Mbps");

    // Brief pause before accepting the next run
    delay(1500);
}

// =============================================================
// oledStatus — draw up to 4 lines, flush once
// =============================================================
static void oledStatus(const char* line1, const char* line2,
                       const char* line3, const char* line4) {
    if (!oledOk) return;

    oled.clearDisplay();
    oled.setTextSize(1);
    oled.setTextColor(SSD1306_WHITE);

    oled.setCursor(0,  0); oled.println(line1);
    oled.setCursor(0, 16); oled.println(line2);
    oled.setCursor(0, 32); oled.println(line3);
    oled.setCursor(0, 48); oled.println(line4);

    oled.display();
}

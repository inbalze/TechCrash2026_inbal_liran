// =============================================================
// CrashTech VLSI-2026 — Challenge 6: Frequency Detector (ESP32)  v2
//
// Role: sine-wave generator and UART burst transmitter.
//
// Loop behaviour (repeats ~every 42 ms):
//   1. Read potentiometer on GPIO34 (ADC1_CH6, 12-bit, 0–4095).
//   2. Apply Exponential Moving Average (alpha=0.1) to smooth ADC jitter.
//   3. Map smoothed ADC value linearly to target frequency: 100–2000 Hz.
//   4. Generate 256 signed 8-bit samples of a sine wave:
//        x[i] = (int8_t)(sin(2π · f · i / 8000) × 127)
//      using a fixed sample rate of 8000 Hz.
//   5. Burst all 256 bytes to the FPGA via UART2 TX at 115200 baud.
//      FPGA UART RX is now on JP1 GPIO[0] = PIN_V10.
//   6. flush() — blocks until the last stop-bit is transmitted
//      (~22.2 ms), guaranteeing a clean end-of-burst.
//   7. delay(20) — 20 ms of silence = FPGA frame-sync gap (2 ms
//      threshold on FPGA → always triggers with this gap). ✓
//
// Total burst period ≈ 22 ms (TX) + 20 ms (gap) = 42 ms.
//
// EMA filter (alpha = 0.1):
//   ema_val = 0.1 × adc_raw + 0.9 × ema_val
//   Time constant τ ≈ 9 loop periods ≈ 380 ms. Eliminates ADC jitter
//   without introducing audible lag when the pot is turned slowly.
//
// Pin assignments (all within authorised set [12-14, 25-27, 32-35]):
//   GPIO 34 — ADC1_CH6 input (potentiometer wiper, input-only pin)
//   GPIO 32 — UART2 TX → FPGA JP1 GPIO[0] (PIN_V10)
//
// Frequency math verification:
//   crossings in 256 samples ≈ 2 × N_cycles = 2 × (256 × f / 8000)
//   FPGA computes: F = crossings × 8000 / 512
//   Round-trip: F = [2 × 256 × f / 8000] × 8000 / 512 = f ✓
//   At 1000 Hz: 64 crossings → 64 × 8000 / 512 = 1000 Hz ✓
//   At 2000 Hz: 128 crossings → 128 × 8000 / 512 = 2000 Hz ✓
// =============================================================

#include <Arduino.h>
#include <math.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// ---- Pin definitions (authorised GPIO subset) ---------------
static constexpr int      PIN_ADC     = 34;     // ADC1_CH6, input-only GPIO
static constexpr int      PIN_FPGA_TX = 32;     // UART2 TX → FPGA JP1 GPIO[0] (PIN_V10)
static constexpr int      PIN_SDA     = 26;     // I2C SDA → SSD1306 OLED
static constexpr int      PIN_SCL     = 27;     // I2C SCL → SSD1306 OLED

// ---- OLED (SSD1306 128×64, I2C 0x3C) ----------------------
static Adafruit_SSD1306 oled(128, 64, &Wire, -1);
static int oled_freq_last = -1;  // only redraw when value changes

// ---- EMA filter state --------------------------------------
// Persistent across loop() calls. Initialised to mid-scale so the
// first burst is at a reasonable frequency rather than 100 Hz.
static float ema_val = 2047.5f;     // mid-scale (≈ 1050 Hz initial target)
static constexpr float EMA_ALPHA = 0.1f;  // low-pass; τ ≈ 9 loop periods ≈ 380 ms

// ---- DSP & UART parameters ----------------------------------
static constexpr uint32_t UART_BAUD   = 115200;
static constexpr int      SAMPLE_RATE = 8000;   // Hz (fixed)
static constexpr int      NUM_SAMPLES = 256;    // samples per burst
static constexpr int      FREQ_MIN    = 100;    // Hz (pot min)
static constexpr int      FREQ_MAX    = 2000;   // Hz (pot max)
static constexpr int      BURST_GAP   = 20;     // ms idle after burst

static HardwareSerial FpgaSerial(2);            // UART2

// ---- Sample buffer (static to avoid stack pressure) ---------
static int8_t samples[NUM_SAMPLES];

// =============================================================
void setup() {
    Serial.begin(115200);
    Serial.println("[freq_detector] boot");

    // ADC: GPIO34 is ADC1_CH6.
    // 12-bit width (0–4095), 11 dB attenuation = full 0–3.3 V range.
    analogSetWidth(12);
    analogSetPinAttenuation(PIN_ADC, ADC_11db);

    // UART2: TX-only. -1 for RX pin means no RX GPIO is allocated.
    FpgaSerial.begin(UART_BAUD, SERIAL_8N1, /*RX=*/-1, PIN_FPGA_TX);

    // OLED: SSD1306 128×64 via I2C
    Wire.begin(PIN_SDA, PIN_SCL);
    if (!oled.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
        Serial.println("[OLED] SSD1306 init failed");
    } else {
        oled.clearDisplay();
        oled.setTextColor(SSD1306_WHITE);
        oled.setTextSize(2);
        oled.setCursor(4, 10);
        oled.print("Freq Det");
        oled.setTextSize(1);
        oled.setCursor(4, 50);
        oled.print("Waiting...");
        oled.display();
        Serial.println("[OLED] OK");
    }
}

// =============================================================
void loop() {
    // ---- 1. Read potentiometer --------------------------------
    const int adc_raw = analogRead(PIN_ADC);

    // ---- 2. EMA low-pass filter (α = 0.1) --------------------
    // Smooths jitter from the 12-bit SAR ADC.  A single raw-ADC
    // spike of ±200 LSB (≈ ±93 Hz) is attenuated to < ±1 Hz after
    // ~10 loop periods (420 ms).
    ema_val = EMA_ALPHA * (float)adc_raw + (1.0f - EMA_ALPHA) * ema_val;
    const int adc_smooth = (int)(ema_val + 0.5f);  // round to nearest int

    // ---- 3. Map smoothed ADC to target frequency (linear) ----
    // adc_smooth ∈ [0, 4095] → freq_hz ∈ [FREQ_MIN, FREQ_MAX]
    // Use 32-bit intermediate to avoid overflow.
    int freq_hz = FREQ_MIN +
                  (int)((int32_t)adc_smooth * (FREQ_MAX - FREQ_MIN) / 4095);

    // Clamp (defensive against EMA transiently exceeding rails)
    if (freq_hz < FREQ_MIN) freq_hz = FREQ_MIN;
    if (freq_hz > FREQ_MAX) freq_hz = FREQ_MAX;

    // ---- 3. Generate 256-sample sine wave --------------------
    // x[i] = round(127 × sin(2π × f × i / Fs))
    // Cast to int8_t is safe: sinf() ∈ [-1, 1], scaled to [-127, 127],
    // which is within int8_t range [-128, 127].
    const float phase_inc = 2.0f * (float)M_PI * (float)freq_hz
                            / (float)SAMPLE_RATE;

    for (int i = 0; i < NUM_SAMPLES; i++) {
        const float s = sinf((float)i * phase_inc);
        samples[i] = (int8_t)(s * 127.0f);
    }

    // ---- 4. Burst: write all 256 bytes to HW TX FIFO ---------
    // write() copies data to the UART TX buffer and returns
    // immediately. Transmission proceeds asynchronously via the
    // hardware UART peripheral.
    FpgaSerial.write(reinterpret_cast<const uint8_t*>(samples),
                     static_cast<size_t>(NUM_SAMPLES));

    // ---- 5. Wait for last bit to leave the wire ---------------
    // flush() blocks until the TX shift register empties (~22.2 ms
    // for 256 × 10 bits at 115200 baud). This ensures the burst
    // is complete before the gap begins.
    FpgaSerial.flush();

    Serial.printf("[TX] freq=%4d Hz  adc_raw=%4d  ema=%.1f\n",
                  freq_hz, adc_raw, ema_val);

    // ---- 6. Update OLED (only when freq changes) -------------
    // Runs during the idle gap so it does NOT delay the UART burst.
    // Bar graph: each of 10 segments = 190 Hz (100–2000 Hz range).
    if (freq_hz != oled_freq_last) {
        oled_freq_last = freq_hz;

        oled.clearDisplay();

        // ---- Large frequency label ----
        oled.setTextSize(3);
        oled.setTextColor(SSD1306_WHITE);
        char buf[8];
        snprintf(buf, sizeof(buf), "%4d", freq_hz);
        // centre the 4-digit + space string: 4 chars × 18px = 72px, offset = (128-72)/2 = 28
        oled.setCursor(10, 8);
        oled.print(buf);

        // ---- "Hz" label ----
        oled.setTextSize(2);
        oled.setCursor(90, 14);
        oled.print("Hz");

        // ---- Horizontal bar graph ----
        // Maps 100–2000 Hz → 0–118 px wide bar
        const int bar_w = (int)((long)(freq_hz - FREQ_MIN) * 118 / (FREQ_MAX - FREQ_MIN));
        if (bar_w > 0) oled.fillRect(5, 46, bar_w, 10, SSD1306_WHITE);
        oled.drawRect(4, 45, 120, 12, SSD1306_WHITE);  // outline

        // ---- "100" and "2000" range labels ----
        oled.setTextSize(1);
        oled.setCursor(4, 58);
        oled.print("100");
        oled.setCursor(100, 58);
        oled.print("2000");

        oled.display();
    }

    // ---- 6. Idle gap — FPGA frame-sync pulse -----------------
    // 20 ms >> FPGA idle threshold (2 ms) → always fires. ✓
    // Total loop period ≈ 22 ms (TX) + 20 ms (gap) = 42 ms.
    delay(BURST_GAP);
}

// =============================================================
// CrashTech VLSI-2026 — Challenge 6: Frequency Detector (ESP32)
//
// Role: sine-wave generator and UART burst transmitter.
//
// Loop behaviour (repeats ~every 42 ms):
//   1. Read potentiometer on GPIO34 (ADC1_CH6, 12-bit, 0–4095).
//   2. Map ADC value linearly to a target frequency: 100–2000 Hz.
//   3. Generate 256 signed 8-bit samples of a sine wave:
//        x[i] = (int8_t)(sin(2π · f · i / 8000) × 127)
//      using a fixed sample rate of 8000 Hz.
//   4. Burst all 256 bytes to the FPGA via UART2 TX at 115200 baud.
//   5. flush() — blocks until the last stop-bit is transmitted
//      (~22.2 ms), guaranteeing a clean end-of-burst.
//   6. delay(20) — 20 ms of silence = FPGA frame-sync gap (2 ms
//      threshold on FPGA → always triggers with this gap). ✓
//
// Total burst period ≈ 22 ms (TX) + 20 ms (gap) = 42 ms.
//
// Pin assignments (all within authorised set [12-14, 25-27, 32-35]):
//   GPIO 34 — ADC1_CH6 input (potentiometer wiper, input-only pin)
//   GPIO 32 — UART2 TX → FPGA ARDUINO_IO[0] (PIN_AB5)
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

// ---- Pin definitions (authorised GPIO subset) ---------------
static constexpr int      PIN_ADC     = 34;     // ADC1_CH6, input-only GPIO
static constexpr int      PIN_FPGA_TX = 32;     // UART2 TX → FPGA ARDUINO_IO[0]

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

    Serial.printf("[freq_detector] UART2 TX on GPIO%d at %u baud\n",
                  PIN_FPGA_TX, UART_BAUD);
}

// =============================================================
void loop() {
    // ---- 1. Read potentiometer --------------------------------
    const int adc_raw = analogRead(PIN_ADC);

    // ---- 2. Map ADC to target frequency (linear) -------------
    // adc_raw ∈ [0, 4095] → freq_hz ∈ [FREQ_MIN, FREQ_MAX]
    // Use 32-bit intermediate to avoid overflow.
    int freq_hz = FREQ_MIN +
                  (int)((int32_t)adc_raw * (FREQ_MAX - FREQ_MIN) / 4095);

    // Clamp (defensive against ADC noise at rail)
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

    Serial.printf("[TX] freq=%4d Hz  adc=%4d\n", freq_hz, adc_raw);

    // ---- 6. Idle gap — FPGA frame-sync pulse -----------------
    // 20 ms >> FPGA idle threshold (2 ms) → always fires. ✓
    // Total loop period ≈ 22 ms (TX) + 20 ms (gap) = 42 ms.
    delay(BURST_GAP);
}

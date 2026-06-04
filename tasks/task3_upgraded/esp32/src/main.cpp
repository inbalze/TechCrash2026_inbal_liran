// =============================================================
// CrashTech VLSI-2026 — Challenge 3 Upgraded: Parallel Bus
// ESP32 ISR-driven parallel-bus ingestion + UART checksum return
//
// Protocol:
//   FPGA → ESP32 : 4-byte header (N, little-endian) + N random bytes
//                  via 8-bit parallel bus + WR strobe (ARDUINO_IO[10])
//   ESP32 → FPGA : 1 byte checksum = (Σ all N data bytes) & 0xFF
//                  via UART2 TX at 115200 baud
//
// Throughput estimate:
//   FPGA drives 16 cycles/byte at 50 MHz = 320 ns/byte
//   10,004 bytes × 320 ns ≈ 3.2 ms TX
//   ESP32 ISR latency (IRAM, no Wi-Fi): ~150-200 ns  → safe within 240 ns WR window
//
// Pin assignments (all within authorised set [12,13,14,25,26,27,32,33,34,35]):
//
//   GPIO12  D0  ← FPGA IO[2]  PIN_AB7   GPIO_IN_REG[12]
//   GPIO13  D1  ← FPGA IO[3]  PIN_AB8   GPIO_IN_REG[13]
//   GPIO14  D2  ← FPGA IO[4]  PIN_AB9   GPIO_IN_REG[14]
//   GPIO25  D3  ← FPGA IO[5]  PIN_Y10   GPIO_IN_REG[25]
//   GPIO26  D4  ← FPGA IO[6]  PIN_AA11  GPIO_IN_REG[26]
//   GPIO27  D5  ← FPGA IO[7]  PIN_AA12  GPIO_IN_REG[27]
//   GPIO34  D6  ← FPGA IO[8]  PIN_AB17  GPIO_IN1_REG[2]  (input-only pin)
//   GPIO35  D7  ← FPGA IO[9]  PIN_AA17  GPIO_IN1_REG[3]  (input-only pin)
//   GPIO32  WR  ← FPGA IO[10] PIN_AB19  interrupt source (rising edge)
//   GPIO33  TX  → FPGA IO[0]  PIN_AB5   UART2 TX @ 115200 baud
//
// Byte reconstruction from scattered GPIO registers:
//   lo = REG_READ(GPIO_IN_REG):   GPIO12-14 at bits 12-14, GPIO25-27 at bits 25-27
//   hi = REG_READ(GPIO_IN1_REG):  GPIO34 at bit 2, GPIO35 at bit 3
//
//   byte = ((lo >> 12) & 0x07)          // D0,D1,D2 → bits 0,1,2
//        | (((lo >> 25) & 0x07) << 3)   // D3,D4,D5 → bits 3,4,5
//        | (((hi >>  2) & 0x03) << 6)   // D6,D7    → bits 6,7
// =============================================================

#include <Arduino.h>
#include "soc/gpio_reg.h"   // GPIO_IN_REG, GPIO_IN1_REG
#include "driver/gpio.h"    // gpio_config, gpio_set_intr_type, ...

// ---- Pin definitions ----
#define PIN_D0   12
#define PIN_D1   13
#define PIN_D2   14
#define PIN_D3   25
#define PIN_D4   26
#define PIN_D5   27
#define PIN_D6   34   // input-only GPIO — no interrupt, no output
#define PIN_D7   35   // input-only GPIO — no interrupt, no output
#define PIN_WR   32   // WR strobe: rising edge triggers ISR
#define PIN_TX   33   // UART2 TX → FPGA ARDUINO_IO[0]

// ---- Protocol constants ----
#define N_HEADER    4
#define N_DATA      10000
#define N_TOTAL     (N_HEADER + N_DATA)   // 10004

// ---- ISR state (DRAM_ATTR: accessible from IRAM ISR on either core) ----
static volatile uint32_t DRAM_ATTR byte_count = 0;  // bytes received so far
static volatile uint32_t DRAM_ATTR data_sum   = 0;  // running checksum (data only)
static volatile bool     DRAM_ATTR run_done   = false;

// =============================================================
// WR Rising-Edge ISR  (IRAM_ATTR: runs from internal RAM)
//
// Reads both GPIO input registers immediately after interrupt
// fires, reconstructs the byte, and accumulates the checksum.
//
// Timing budget:
//   FPGA holds WR=1 for 240 ns (12 × 20 ns).
//   ISR entry (IRAM, no Wi-Fi): ~150-200 ns from WR rising edge.
//   REG_READ × 2: ~8-16 ns (1-2 cycles @ 240 MHz).
//   Total read latency: ~160-220 ns < 240 ns window. ✓
// =============================================================
static void IRAM_ATTR wr_isr_handler(void* /*arg*/) {
    // Read GPIO input registers as early as possible
    const uint32_t lo = REG_READ(GPIO_IN_REG);   // GPIO 0-31
    const uint32_t hi = REG_READ(GPIO_IN1_REG);  // GPIO 32-39

    // Reconstruct byte:
    //   D0(GPIO12), D1(GPIO13), D2(GPIO14) → bits 0-2  (lo[14:12])
    //   D3(GPIO25), D4(GPIO26), D5(GPIO27) → bits 3-5  (lo[27:25])
    //   D6(GPIO34), D7(GPIO35)             → bits 6-7  (hi[3:2])
    const uint8_t b = (uint8_t)(
        ((lo >> 12) & 0x07u)           // D0, D1, D2
      | (((lo >> 25) & 0x07u) << 3)    // D3, D4, D5
      | (((hi >>  2) & 0x03u) << 6)    // D6, D7
    );

    const uint32_t cnt = byte_count;

    // First N_HEADER bytes are the length header — receive but don't checksum
    if (cnt >= N_HEADER) {
        data_sum = data_sum + b;
        if (cnt == N_TOTAL - 1) {
            run_done = true;   // all bytes received
        }
    }

    byte_count = cnt + 1;
}

// ---- Configure all data + WR pins as digital inputs ----
static void configure_inputs() {
    const gpio_num_t pins[] = {
        (gpio_num_t)PIN_D0, (gpio_num_t)PIN_D1, (gpio_num_t)PIN_D2,
        (gpio_num_t)PIN_D3, (gpio_num_t)PIN_D4, (gpio_num_t)PIN_D5,
        (gpio_num_t)PIN_D6, (gpio_num_t)PIN_D7,
        (gpio_num_t)PIN_WR
    };
    const int n = sizeof(pins) / sizeof(pins[0]);

    for (int i = 0; i < n; i++) {
        gpio_config_t cfg = {};
        cfg.pin_bit_mask = 1ULL << (uint8_t)pins[i];
        cfg.mode         = GPIO_MODE_INPUT;
        cfg.pull_up_en   = GPIO_PULLUP_DISABLE;
        cfg.pull_down_en = GPIO_PULLDOWN_DISABLE;
        cfg.intr_type    = GPIO_INTR_DISABLE;  // ISR added separately for WR
        gpio_config(&cfg);
    }
}

void setup() {
    Serial.begin(115200);
    Serial.println("[par_loopback] boot");

    // Configure all bus input pins
    configure_inputs();

    // Configure UART2 TX-only (no RX pin needed)
    Serial2.begin(115200, SERIAL_8N1, /*RX=*/ -1, PIN_TX);

    // Install GPIO ISR service with IRAM flag for minimum latency.
    // ESP_INTR_FLAG_IRAM: ISR can run even when flash cache is disabled.
    gpio_install_isr_service(ESP_INTR_FLAG_IRAM);

    // Attach rising-edge interrupt to WR pin
    gpio_set_intr_type((gpio_num_t)PIN_WR, GPIO_INTR_POSEDGE);
    gpio_isr_handler_add((gpio_num_t)PIN_WR, wr_isr_handler, nullptr);

    Serial.println("[par_loopback] ISR installed — press KEY[0] on FPGA to start");
}

void loop() {
    // ---- Reset ISR state for a new run ----
    // Disable interrupt during reset to prevent a mid-reset ISR firing
    gpio_intr_disable((gpio_num_t)PIN_WR);
    byte_count = 0;
    data_sum   = 0;
    run_done   = false;
    // Compiler barrier: prevent the compiler reordering stores past enable
    __asm__ __volatile__("" ::: "memory");
    gpio_intr_enable((gpio_num_t)PIN_WR);

    // ---- Wait for all N_TOTAL bytes (tight spin, ISR-driven) ----
    // No Serial, no delay, no OLED in this hot path.
    while (!run_done) {
        // Tight spin — ISR will set run_done when byte_count == N_TOTAL-1
        __asm__ __volatile__("nop");
    }

    // ---- Send 1-byte checksum back to FPGA ----
    const uint8_t checksum = (uint8_t)(data_sum & 0xFFu);
    Serial2.write(checksum);
    Serial2.flush();   // block until byte is fully transmitted

    // ---- Debug print (happens after UART TX is already on the wire) ----
    Serial.printf("[done] bytes=%u  sum=0x%08X  crc=0x%02X\n",
                  (unsigned)byte_count, (unsigned)data_sum, checksum);

    // Small pause: FPGA stays in S_DONE displaying the result.
    // KEY[0] must be pressed again to start a new run.
    delay(200);
}

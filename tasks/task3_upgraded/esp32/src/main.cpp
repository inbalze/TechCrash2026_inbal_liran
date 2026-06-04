// CrashTech VLSI-2026 - Challenge 3 Upgraded
// ESP32 receiver for 8-bit FPGA parallel bus + UART checksum return.

#include <Arduino.h>
#include "driver/gpio.h"
#include "soc/gpio_reg.h"

#define PIN_D0   21
#define PIN_D1   22
#define PIN_D2   23
#define PIN_D3   25
#define PIN_D4   26
#define PIN_D5   27
#define PIN_D6   34
#define PIN_D7   35
#define PIN_WR   32
#define PIN_TX   33

#define N_HEADER 4u
#define N_DATA   10000u
#define N_TOTAL  (N_HEADER + N_DATA)

static volatile uint32_t DRAM_ATTR byte_count = 0;
static volatile uint32_t DRAM_ATTR data_sum = 0;
static volatile bool DRAM_ATTR run_done = false;

static inline void arm_receiver() {
    gpio_intr_disable((gpio_num_t)PIN_WR);
    byte_count = 0;
    data_sum = 0;
    run_done = false;
    __asm__ __volatile__("" ::: "memory");
    gpio_intr_enable((gpio_num_t)PIN_WR);
}

static void IRAM_ATTR wr_isr_handler(void* /*arg*/) {
    if (run_done) {
        return;
    }

    const uint32_t gpio0 = REG_READ(GPIO_IN_REG);
    const uint32_t gpio1 = REG_READ(GPIO_IN1_REG);
    const uint8_t value = (uint8_t)(
        ((gpio0 >> 21) & 0x07u) |
        (((gpio0 >> 25) & 0x07u) << 3) |
        (((gpio1 >> 2)  & 0x03u) << 6)
    );

    const uint32_t count = byte_count;
    if (count >= N_HEADER) {
        data_sum += value;
        if (count == N_TOTAL - 1u) {
            run_done = true;
        }
    }

    byte_count = count + 1u;
}

static void configure_input_pin(uint8_t pin, gpio_int_type_t interrupt_type) {
    gpio_config_t cfg = {};
    cfg.pin_bit_mask = 1ULL << pin;
    cfg.mode = GPIO_MODE_INPUT;
    cfg.pull_up_en = GPIO_PULLUP_DISABLE;
    cfg.pull_down_en = (pin == PIN_WR) ? GPIO_PULLDOWN_ENABLE : GPIO_PULLDOWN_DISABLE;
    cfg.intr_type = interrupt_type;
    gpio_config(&cfg);
}

void setup() {
    configure_input_pin(PIN_D0, GPIO_INTR_DISABLE);
    configure_input_pin(PIN_D1, GPIO_INTR_DISABLE);
    configure_input_pin(PIN_D2, GPIO_INTR_DISABLE);
    configure_input_pin(PIN_D3, GPIO_INTR_DISABLE);
    configure_input_pin(PIN_D4, GPIO_INTR_DISABLE);
    configure_input_pin(PIN_D5, GPIO_INTR_DISABLE);
    configure_input_pin(PIN_D6, GPIO_INTR_DISABLE);
    configure_input_pin(PIN_D7, GPIO_INTR_DISABLE);
    configure_input_pin(PIN_WR, GPIO_INTR_POSEDGE);

    Serial2.begin(57600, SERIAL_8N1, -1, PIN_TX);

    gpio_install_isr_service(ESP_INTR_FLAG_IRAM);
    gpio_isr_handler_add((gpio_num_t)PIN_WR, wr_isr_handler, nullptr);
}

void loop() {
    arm_receiver();

    uint32_t last_count = 0;
    uint32_t last_progress_ms = millis();

    while (!run_done) {
        const uint32_t current_count = byte_count;
        if (current_count != last_count) {
            last_count = current_count;
            last_progress_ms = millis();
        } else if (current_count > 0 && (millis() - last_progress_ms) > 500u) {
            arm_receiver();
            last_count = 0;
            last_progress_ms = millis();
        }

        yield();
    }

    gpio_intr_disable((gpio_num_t)PIN_WR);
    const uint8_t checksum = (uint8_t)(data_sum & 0xFFu);
    Serial2.write(checksum);
    Serial2.flush();
}
// CrashTech VLSI-2026 - Challenge 3 Bare-Metal Optimization
// ESP32 receiver using bare-metal polling strategy for extreme transfer speed.

#include <Arduino.h>
#include "driver/gpio.h"
#include "soc/gpio_reg.h"
#include "esp_task_wdt.h"

// Pin definitions
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

// Helper to read Tensilica CPU cycle counter (ccount)
static inline uint32_t get_ccount() {
    uint32_t ccount;
    __asm__ __volatile__("rsr %0, ccount" : "=r"(ccount));
    return ccount;
}

static void configure_input_pin(uint8_t pin) {
    gpio_config_t cfg = {};
    cfg.pin_bit_mask = 1ULL << pin;
    cfg.mode = GPIO_MODE_INPUT;
    cfg.pull_up_en = GPIO_PULLUP_DISABLE;
    cfg.pull_down_en = (pin == PIN_WR) ? GPIO_PULLDOWN_ENABLE : GPIO_PULLDOWN_DISABLE;
    cfg.intr_type = GPIO_INTR_DISABLE; // Disable all interrupts
    gpio_config(&cfg);
}

void setup() {
    configure_input_pin(PIN_D0);
    configure_input_pin(PIN_D1);
    configure_input_pin(PIN_D2);
    configure_input_pin(PIN_D3);
    configure_input_pin(PIN_D4);
    configure_input_pin(PIN_D5);
    configure_input_pin(PIN_D6);
    configure_input_pin(PIN_D7);
    configure_input_pin(PIN_WR);

    Serial2.begin(57600, SERIAL_8N1, -1, PIN_TX);

    // Unsubscribe the current task (loopTask) from Task Watchdog monitoring.
    // This allows us to run a tight polling loop indefinitely without triggering resets.
    esp_task_wdt_delete(NULL);
}

void loop() {
    // 1. Wait for the WR pin to go LOW first (ensuring we don't catch a stale high state)
    while (REG_READ(GPIO_IN1_REG) & (1u << 0)) {
        // Tight poll
    }

    // 2. Wait for the first rising edge of PIN_WR
    // Save the read value directly to gpio1 to capture D6-D7 at the moment of the rising edge.
    uint32_t gpio1 = 0;
    while (!((gpio1 = REG_READ(GPIO_IN1_REG)) & (1u << 0))) {
        // Tight poll
    }

    // 3. Start high-speed parallel reception. Lock the core.
    portDISABLE_INTERRUPTS();

    uint32_t checksum = 0;
    bool transmission_failed = false;

    // Phase 1: Read N_HEADER (4) bytes and ignore them (discards header)
    for (uint32_t i = 0; i < N_HEADER; ++i) {
        // Read only GPIO_IN_REG (we already have gpio1 from wait loop / previous iteration)
        const uint32_t gpio0 = REG_READ(GPIO_IN_REG);

        // Wait for WR to go LOW (falling edge) with 1 ms timeout
        uint32_t start_c = get_ccount();
        while (REG_READ(GPIO_IN1_REG) & (1u << 0)) {
            if (get_ccount() - start_c > 240000u) { // 1 ms timeout (240k cycles @ 240MHz)
                transmission_failed = true;
                break;
            }
        }
        if (transmission_failed) {
            break;
        }

        // Wait for WR to go HIGH again (rising edge) with 1 ms timeout
        // Save the read value directly to gpio1 to capture D6-D7 for the next iteration.
        start_c = get_ccount();
        while (!((gpio1 = REG_READ(GPIO_IN1_REG)) & (1u << 0))) {
            if (get_ccount() - start_c > 240000u) { // 1 ms timeout
                transmission_failed = true;
                break;
            }
        }
        if (transmission_failed) {
            break;
        }
    }

    // Phase 2: Read N_DATA (10,000) bytes and accumulate checksum
    if (!transmission_failed) {
        for (uint32_t i = 0; i < N_DATA; ++i) {
            // Read only GPIO_IN_REG (we already have gpio1 and WR is HIGH)
            const uint32_t gpio0 = REG_READ(GPIO_IN_REG);

            // Wait for WR to go LOW (falling edge) with 1 ms timeout
            uint32_t start_c = get_ccount();
            while (REG_READ(GPIO_IN1_REG) & (1u << 0)) {
                if (get_ccount() - start_c > 240000u) { // 1 ms timeout
                    transmission_failed = true;
                    break;
                }
            }
            if (transmission_failed) {
                break;
            }

            // Shift and mask the GPIO registers to reconstruct the 8-bit value
            const uint8_t value = (uint8_t)(
                ((gpio0 >> 21) & 0x07u) |
                ((gpio0 >> 22) & 0x38u) |
                ((gpio1 << 4)  & 0xC0u)
            );

            checksum += value;

            // Wait for WR to go HIGH again (rising edge) with 1 ms timeout.
            // Save the read value directly to gpio1 to capture D6-D7 for the next iteration.
            // Do NOT wait on the very last byte of the transfer.
            if (i < N_DATA - 1) {
                start_c = get_ccount();
                while (!((gpio1 = REG_READ(GPIO_IN1_REG)) & (1u << 0))) {
                    if (get_ccount() - start_c > 240000u) { // 1 ms timeout
                        transmission_failed = true;
                        break;
                    }
                }
                if (transmission_failed) {
                    break;
                }
            }
        }
    }

    // 4. Transmission complete or timed out. Unlock the core.
    portENABLE_INTERRUPTS();

    if (!transmission_failed) {
        // Send the calculated checksum (sum & 0xFF) via Serial2
        Serial2.write((uint8_t)(checksum & 0xFFu));
        Serial2.flush();
        // Delay to prevent immediate restart before FPGA returns to IDLE state
        delay(100);
    } else {
        // In case of timeout (e.g. startup glitch), sleep briefly before retrying
        delay(10);
    }
}
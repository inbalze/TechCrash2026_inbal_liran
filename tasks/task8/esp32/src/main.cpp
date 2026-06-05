#include <Arduino.h>

#define RXD2 16
#define TXD2 17
#define PIN_BUZZER 26
#define PIN_LED 2

enum RxState { WAIT_HIGH, WAIT_LOW };
RxState rx_state = WAIT_HIGH;
uint8_t high_byte = 0;
unsigned long last_byte_time = 0;

void setup() {
    Serial.begin(115200);
    Serial.println("[ESP32] Bridge + Buzzer started. RX Pin: 16, TX Pin: 17");
    Serial2.begin(9600, SERIAL_8N1, RXD2, TXD2);
    pinMode(PIN_BUZZER, OUTPUT);
    digitalWrite(PIN_BUZZER, LOW);
    pinMode(PIN_LED, OUTPUT);
    digitalWrite(PIN_LED, LOW);
}

void loop() {
    while (Serial2.available() > 0) {
        unsigned long now = millis();
        if (now - last_byte_time > 5) {
            rx_state = WAIT_HIGH;
        }
        last_byte_time = now;

        uint8_t b = Serial2.read();
        
        // Forward to USB serial for PC logging
        Serial.write(b);

        // Parse packet
        if (rx_state == WAIT_HIGH) {
            if ((b & 0xF0) == 0) {
                high_byte = b;
                rx_state = WAIT_LOW;
            }
        } else {
            uint8_t low_byte = b;
            rx_state = WAIT_HIGH;

            uint16_t val = (high_byte << 8) | low_byte;
            bool key0_pressed = (val & 0x01) != 0;

            // Toggle onboard LED on every parsed packet as a diagnostic indicator
            static bool led_state = false;
            led_state = !led_state;
            digitalWrite(PIN_LED, led_state ? HIGH : LOW);

            if (key0_pressed) {
                tone(PIN_BUZZER, 1000); // Play 1 kHz tone
            } else {
                noTone(PIN_BUZZER);
            }
        }
    }
}

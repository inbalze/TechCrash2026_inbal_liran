#include <Arduino.h>

static const uint8_t BUZZER_PIN = 26;
static const uint32_t BUZZ_MS = 90;
static const uint32_t RX_PULSE_MS = 25;

static bool has_high_byte = false;
static uint8_t high_byte = 0;
static bool key0_prev = false;
static uint32_t buzzer_off_at = 0;
static uint32_t bytes_rx = 0;
static uint32_t packets_rx = 0;
static uint32_t key0_edges = 0;
static uint32_t last_stats_ms = 0;
static uint32_t last_rx_pulse_ms = 0;

void setup() {
    Serial.begin(115200);
    Serial2.begin(9600, SERIAL_8N1, 17, 16);

    pinMode(BUZZER_PIN, OUTPUT);
    digitalWrite(BUZZER_PIN, LOW);

    digitalWrite(BUZZER_PIN, HIGH);
    delay(80);
    digitalWrite(BUZZER_PIN, LOW);
    delay(60);
    digitalWrite(BUZZER_PIN, HIGH);
    delay(80);
    digitalWrite(BUZZER_PIN, LOW);
    
    delay(100);

    Serial.println("DBG: ESP bridge+buzzer debug start");
}

void loop() {
    while (Serial2.available()) {
        uint8_t byte = Serial2.read();
        Serial.write(byte);
        bytes_rx++;

        uint32_t now = millis();
        if (now - last_rx_pulse_ms >= 1000) {
            digitalWrite(BUZZER_PIN, HIGH);
            buzzer_off_at = now + RX_PULSE_MS;
            last_rx_pulse_ms = now;
        }

        if (!has_high_byte) {
            high_byte = byte;
            has_high_byte = true;
        } else {
            uint16_t payload = (static_cast<uint16_t>(high_byte) << 8) | byte;
            bool key0_now = (payload & 0x0001u) != 0;
            packets_rx++;

            if (key0_now && !key0_prev) {
                digitalWrite(BUZZER_PIN, HIGH);
                buzzer_off_at = millis() + BUZZ_MS;
                key0_edges++;
            }
            key0_prev = key0_now;
            has_high_byte = false;
        }
    }

    if (buzzer_off_at != 0 && static_cast<int32_t>(millis() - buzzer_off_at) >= 0) {
        digitalWrite(BUZZER_PIN, LOW);
        buzzer_off_at = 0;
    }

    uint32_t now = millis();
    if (now - last_stats_ms >= 1000) {
        last_stats_ms = now;
        Serial.print("DBG rx_bytes=");
        Serial.print(bytes_rx);
        Serial.print(" rx_packets=");
        Serial.print(packets_rx);
        Serial.print(" key0_edges=");
        Serial.println(key0_edges);
    }

    delay(1);
}

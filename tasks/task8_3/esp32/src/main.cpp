#include <Arduino.h>

void setup() {
    Serial.begin(115200);
    Serial.println("ESP32 multi-pin listener started");
    Serial1.begin(9600, SERIAL_8N1, 33, -1);
    Serial2.begin(9600, SERIAL_8N1, 16, -1);
}

void loop() {
    while (Serial1.available() > 0) {
        Serial.write(Serial1.read());
    }
    while (Serial2.available() > 0) {
        Serial.write(Serial2.read());
    }
}

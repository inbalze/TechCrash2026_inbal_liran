#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET    -1
#define SCREEN_ADDRESS 0x3C

// Pin Definitions
#define RX_PIN 35
#define SDA_PIN 26
#define SCL_PIN 27

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
HardwareSerial FpgaSerial(2);

// Game States
enum GameState {
    STATE_START,
    STATE_PLAYING,
    STATE_GAMEOVER
};

GameState current_state = STATE_START;

// Bird Physics
float bird_y = 32.0;
float bird_vy = 0.0;
const float GRAVITY = 0.25;
const float JUMP_IMPULSE = -2.8;
const int BIRD_X = 25;
const int BIRD_WIDTH = 8;
const int BIRD_HEIGHT = 6;

// Pipe parameters
float pipe_x = 128.0;
int pipe_gap_y = 20; // Y coordinate of the middle of the gap
int score = 0;

// Difficulty mappings (0x00 to 0x0F)
uint8_t current_difficulty = 0x00;

// Game parameters based on difficulty
float get_pipe_speed() {
    // Speed ranges from 1.0 (diff 0) to 4.0 (diff 15)
    return 1.0 + (current_difficulty * 0.2);
}

int get_gap_size() {
    // Gap size ranges from 28 (diff 0) to 13 (diff 15)
    return 28 - (current_difficulty * 1);
}

void reset_game() {
    bird_y = 24.0;
    bird_vy = 0.0;
    pipe_x = 128.0;
    pipe_gap_y = 20 + random(0, 24); // gap center between Y=20 and Y=44
    score = 0;
}

void setup() {
    Serial.begin(115200);
    
    Wire.begin(SDA_PIN, SCL_PIN, 400000);
    if(!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
        for(;;);
    }
    
    display.clearDisplay();
    display.display();
    
    // UART RX mapped to GPIO 33
    FpgaSerial.begin(115200, SERIAL_8N1, RX_PIN, 12);
    
    reset_game();
}

void update_physics() {
    // Apply gravity
    bird_vy += GRAVITY;
    bird_y += bird_vy;
    
    // Scroll pipe
    pipe_x -= get_pipe_speed();
    
    // Reset pipe when off screen
    if (pipe_x < -12) {
        pipe_x = 128.0;
        pipe_gap_y = 15 + random(0, 30); // Center of gap between 15 and 45
        score++;
    }
}

void check_collisions() {
    // Ceiling / floor collision
    if (bird_y < 0) {
        bird_y = 0;
        bird_vy = 0;
    }
    if (bird_y > (SCREEN_HEIGHT - BIRD_HEIGHT)) {
        current_state = STATE_GAMEOVER;
    }

    // Pipe collision
    int gap = get_gap_size();
    int pipe_top_bottom = pipe_gap_y - (gap / 2);
    int pipe_bottom_top = pipe_gap_y + (gap / 2);
    
    // Bird bounding box
    int bx1 = BIRD_X;
    int bx2 = BIRD_X + BIRD_WIDTH;
    int by1 = (int)bird_y;
    int by2 = (int)bird_y + BIRD_HEIGHT;
    
    // Pipe bounding box (pipe width is 12)
    int px1 = (int)pipe_x;
    int px2 = (int)pipe_x + 12;
    
    // Collision check if bird is horizontally aligned with pipe
    if (bx2 > px1 && bx1 < px2) {
        if (by1 < pipe_top_bottom || by2 > pipe_bottom_top) {
            current_state = STATE_GAMEOVER;
        }
    }
}

void draw_game() {
    display.clearDisplay();
    
    if (current_state == STATE_START) {
        display.setTextSize(2);
        display.setTextColor(SSD1306_WHITE);
        display.setCursor(4, 5);
        display.println("FLAPPY BIRD");
        
        display.setTextSize(1);
        display.setCursor(10, 30);
        display.printf("Difficulty: %d", current_difficulty);
        
        display.setCursor(10, 45);
        display.println("Press KEY0 to Flap");
        
    } else if (current_state == STATE_PLAYING) {
        // Draw Bird
        display.fillRect(BIRD_X, (int)bird_y, BIRD_WIDTH, BIRD_HEIGHT, SSD1306_WHITE);
        
        // Draw Pipes
        int gap = get_gap_size();
        int pipe_top_height = pipe_gap_y - (gap / 2);
        int pipe_bottom_y = pipe_gap_y + (gap / 2);
        
        // Top pipe
        display.fillRect((int)pipe_x, 0, 12, pipe_top_height, SSD1306_WHITE);
        // Bottom pipe
        display.fillRect((int)pipe_x, pipe_bottom_y, 12, SCREEN_HEIGHT - pipe_bottom_y, SSD1306_WHITE);
        
        // Draw Score
        display.setTextSize(1);
        display.setTextColor(SSD1306_WHITE);
        display.setCursor(2, 2);
        display.printf("Score: %d", score);
        display.setCursor(80, 2);
        display.printf("Diff: %d", current_difficulty);
        
    } else if (current_state == STATE_GAMEOVER) {
        display.setTextSize(2);
        display.setTextColor(SSD1306_WHITE);
        display.setCursor(10, 5);
        display.println("GAME OVER");
        
        display.setTextSize(1);
        display.setCursor(20, 30);
        display.printf("Final Score: %d", score);
        
        display.setCursor(15, 48);
        display.println("Press KEY0 to Play");
    }
    
    display.display();
}

void loop() {
    // 1. Process UART non-blocking
    while (FpgaSerial.available()) {
        uint8_t rx_byte = FpgaSerial.read();
        if (rx_byte == 0xFF) {
            if (current_state == STATE_START) {
                current_state = STATE_PLAYING;
                reset_game();
                bird_vy = JUMP_IMPULSE;
            } else if (current_state == STATE_PLAYING) {
                bird_vy = JUMP_IMPULSE;
            } else if (current_state == STATE_GAMEOVER) {
                current_state = STATE_PLAYING;
                reset_game();
            }
        } else if (rx_byte <= 0x0F) {
            current_difficulty = rx_byte;
        }
    }

    // 2. State Machine Update & Physics
    if (current_state == STATE_PLAYING) {
        update_physics();
        check_collisions();
    }

    // 3. Render OLED
    draw_game();

    // 4. Frame rate control (approx 60 FPS -> 16ms delay)
    delay(16);
}

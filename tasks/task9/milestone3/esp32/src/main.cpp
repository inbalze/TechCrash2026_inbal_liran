// =============================================================================
// Task 9 — Milestone 3: Neural Flappy Bird + FPGA Inference Co-Processor
//
// New in Milestone 3 vs Milestone 2:
//   • SW[9] HIGH → FPGA Inference Mode (was: solo-bird view in M2)
//   • On mode transition HIGH:
//       1. OLED blinks "INF" / "INFERENCE MODE" indicator
//       2. Game resets to single best-ever-bird slot
//       3. Best-ever network weights streamed to FPGA over UART
//       4. Each game frame: 4 telemetry bytes sent to FPGA, 1-byte decision
//          returned; internal C++ NN is NOT used in inference mode
//   • On mode transition LOW → returns to training mode (full 30-bird swarm)
//   • OLED HUD always shows current mode: "MODE: TRAINING" or "MODE: FPGA INF"
//
// UART Wire Protocol (full specification):
//
//   WEIGHT STREAM  (ESP32 → FPGA, once per mode transition HIGH)
//     Byte  0    : 0xA5              sync header
//     Bytes 1-2  : w0[0]  Q7.8 MSB-first  (round(float × 256), int16_t)
//     Bytes 3-4  : w0[1]  Q7.8  ...  row-major [hidden][input]
//     Bytes 5-6  : w0[2]  Q7.8
//     Bytes 7-8  : w0[3]  Q7.8
//     Bytes 9-10 : w0[4]  Q7.8
//     Bytes 11-12: w0[5]  Q7.8
//     Bytes 13-14: w0[6]  Q7.8
//     Bytes 15-16: w0[7]  Q7.8
//     Bytes 17-18: w0[8]  Q7.8
//     Bytes 19-20: w0[9]  Q7.8
//     Bytes 21-22: w0[10] Q7.8
//     Bytes 23-24: w0[11] Q7.8
//     Bytes 25-26: w0[12] Q7.8
//     Bytes 27-28: w0[13] Q7.8
//     Bytes 29-30: w0[14] Q7.8
//     Bytes 31-32: w0[15] Q7.8
//     Bytes 33-34: b0[0]  Q7.8
//     Bytes 35-36: b0[1]  Q7.8
//     Bytes 37-38: b0[2]  Q7.8
//     Bytes 39-40: b0[3]  Q7.8
//     Bytes 41-42: w1[0]  Q7.8
//     Bytes 43-44: w1[1]  Q7.8
//     Bytes 45-46: w1[2]  Q7.8
//     Bytes 47-48: w1[3]  Q7.8
//     Bytes 49-50: b1[0]  Q7.8
//     Total: 51 bytes
//
//   TELEMETRY FRAME  (ESP32 → FPGA, once per game frame in inference mode)
//     Byte 0: 0xBB              sync header
//     Byte 1: bird_y_norm       signed 8-bit Q0.7  (round(float × 128))
//     Byte 2: bird_vy_norm      signed 8-bit Q0.7
//     Byte 3: dx_norm           signed 8-bit Q0.7
//     Byte 4: dy_norm           signed 8-bit Q0.7
//     Total: 5 bytes
//
//   INFERENCE RESPONSE  (FPGA → ESP32, immediately after each telemetry frame)
//     Byte 0: 0x01  FLAP
//          or 0x00  NO FLAP
//
//   LEGACY CONTROL BYTES  (FPGA → ESP32, unchanged from Milestone 2)
//     0xFE = Pause / Resume (KEY[0])
//     0xFD = Enter Inference Mode (SW[9] HIGH) — was "Solo ON" in M2
//     0xFC = Exit Inference Mode  (SW[9] LOW)  — was "Solo OFF" in M2
//     0xFB = Reset Simulation (KEY[1])
//     0x00-0x0F = Difficulty override (SW[3:0])
// =============================================================================

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "NeuralNetwork.h"

// ─── Pin definitions ──────────────────────────────────────────────────────────
#define SDA_PIN        26
#define SCL_PIN        27
// UART to FPGA:
//   ESP32 TX (GPIO16) → FPGA ARDUINO_IO[0] / PIN_AB5  (weight + telemetry stream)
//   ESP32 RX (GPIO35) ← FPGA UART_TX / PIN_AB6        (commands + inference reply)
//   GPIO35 matches the physical wire soldered during Milestone 2.
#define UART_TX_PIN    16
#define UART_RX_PIN    35

// ─── OLED ─────────────────────────────────────────────────────────────────────
#define SCREEN_WIDTH   128
#define SCREEN_HEIGHT  64
#define OLED_RESET     -1
#define OLED_ADDR      0x3C

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
HardwareSerial    FpgaSerial(2);

// ─── Simulation constants ─────────────────────────────────────────────────────
#define POP_SIZE       30
#define ELITE_COUNT    4
#define MUTATION_STD   0.12f
#define PIPE_WIDTH     10
#define GRAVITY        0.22f
#define JUMP_IMPULSE  -2.6f
#define BIRD_X         20
#define BIRD_W         8
#define BIRD_H         6
#define FRAME_MS       20       // ~50 FPS

// ─── Q7.8 fixed-point conversion helper (float → int16_t, ×256) ──────────────
// Used when streaming weights to FPGA.
static inline int16_t f_to_q78(float f) {
    int32_t v = (int32_t)roundf(f * 256.0f);
    if (v >  32767) v =  32767;
    if (v < -32768) v = -32768;
    return (int16_t)v;
}

// Q0.7 fixed-point conversion helper (float → int8_t, ×128)
// Used when sending telemetry inputs to FPGA.
static inline int8_t f_to_q07(float f) {
    int32_t v = (int32_t)roundf(f * 128.0f);
    if (v >  127) v =  127;
    if (v < -128) v = -128;
    return (int8_t)v;
}

// ─── World ────────────────────────────────────────────────────────────────────
struct Pipe { float x; int gap_y; };
static Pipe pipes[2];

// ─── Dynamic difficulty ───────────────────────────────────────────────────────
static float   pipe_speed = 1.4f;
static int     gap_size   = 26;
static uint8_t current_difficulty      = 0x00;
static bool    user_override_difficulty = false;

static void update_difficulty_params() {
    pipe_speed = 1.4f + (current_difficulty * 0.12f);
    gap_size   = 26 - current_difficulty;
}

// ─── Per-bird state ───────────────────────────────────────────────────────────
struct Bird {
    float y, vy;
    bool  alive;
    int   fitness;
    int   pipes_passed;
    NeuralNetwork nn;
};
static Bird birds[POP_SIZE];

// ─── Global sim state ─────────────────────────────────────────────────────────
static int  alive_count = POP_SIZE;
static int  generation  = 1;
static int  best_ever   = 0;
static int  world_score = 0;
static bool sim_paused  = false;

// ─── Inference mode state ─────────────────────────────────────────────────────
static bool inf_mode    = false;    // true = FPGA inference mode active

// ─── Best-ever bird network (persisted across generations) ───────────────────
static NeuralNetwork best_ever_nn;

// ─── Sorted rank buffer ───────────────────────────────────────────────────────
static int rank[POP_SIZE];

// ─── Clamp helper ─────────────────────────────────────────────────────────────
static inline float clamp(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

// ─── Find the best alive bird index (-1 if none) ─────────────────────────────
static int best_alive_idx() {
    int best = -1;
    for (int i = 0; i < POP_SIZE; i++) {
        if (!birds[i].alive) continue;
        if (best == -1 || birds[i].fitness > birds[best].fitness) best = i;
    }
    return best;
}

static uint32_t generation_seed = 0;

// ─── World helpers ────────────────────────────────────────────────────────────
static int next_gap_y() {
    return 14 + random(0, 37);
}

static void init_world() {
    randomSeed(generation_seed);
    pipes[0].x = 140.0f;              pipes[0].gap_y = next_gap_y();
    pipes[1].x = 140.0f + 70.0f;     pipes[1].gap_y = next_gap_y();
}

static const Pipe* nearest_pipe() {
    const Pipe* best = &pipes[0];
    for (int p = 1; p < 2; p++) {
        float dx_b = pipes[p == 0 ? 1 : 0].x - (BIRD_X + BIRD_W);
        float dx_c = pipes[p].x - (BIRD_X + BIRD_W);
        if (dx_c >= -(float)PIPE_WIDTH && (dx_b < -(float)PIPE_WIDTH || dx_c < dx_b))
            best = &pipes[p];
    }
    return best;
}

static void advance_pipes() {
    for (int p = 0; p < 2; p++) {
        float old_x = pipes[p].x;
        pipes[p].x -= pipe_speed;

        if (old_x + PIPE_WIDTH >= BIRD_X && pipes[p].x + PIPE_WIDTH < BIRD_X) {
            world_score++;
        }

        if (pipes[p].x < -(float)PIPE_WIDTH) {
            pipes[p].x     = 128.0f + 50.0f;
            pipes[p].gap_y = next_gap_y();
        }
    }
}

static bool collides(const Bird& b) {
    if (b.y < 0 || b.y + BIRD_H > SCREEN_HEIGHT) return true;
    int bx1 = BIRD_X, bx2 = BIRD_X + BIRD_W;
    int by1 = (int)b.y, by2 = (int)b.y + BIRD_H;
    for (int p = 0; p < 2; p++) {
        int px1 = (int)pipes[p].x, px2 = px1 + PIPE_WIDTH;
        int top = pipes[p].gap_y - gap_size / 2;
        int bot = pipes[p].gap_y + gap_size / 2;
        if (bx2 > px1 && bx1 < px2) {
            if (by1 < top || by2 > bot) return true;
        }
    }
    return false;
}

// ─── GA epoch ─────────────────────────────────────────────────────────────────
static void sort_by_fitness() {
    for (int i = 0; i < POP_SIZE; i++) rank[i] = i;
    for (int i = 1; i < POP_SIZE; i++) {
        int key = rank[i], j = i - 1;
        while (j >= 0 && birds[rank[j]].fitness < birds[key].fitness) {
            rank[j + 1] = rank[j]; j--;
        }
        rank[j + 1] = key;
    }
}

static void run_epoch() {
    // Track best-ever score AND best-ever network
    for (int i = 0; i < POP_SIZE; i++) {
        if (birds[i].pipes_passed > best_ever) {
            best_ever = birds[i].pipes_passed;
            best_ever_nn.copyFrom(birds[i].nn);
        }
    }

    sort_by_fitness();

    static NeuralNetwork next_gen[POP_SIZE];
    for (int i = 0; i < ELITE_COUNT && i < POP_SIZE; i++)
        next_gen[i].copyFrom(birds[rank[i]].nn);
    for (int i = ELITE_COUNT; i < POP_SIZE; i++) {
        next_gen[i].copyFrom(birds[rank[i % ELITE_COUNT]].nn);
        next_gen[i].mutate(MUTATION_STD);
    }

    generation++;
    generation_seed = esp_random();

    if (!user_override_difficulty) {
        current_difficulty = (generation - 1) % 16;
    }
    update_difficulty_params();

    init_world();
    world_score = 0;

    for (int i = 0; i < POP_SIZE; i++) {
        birds[i].nn.copyFrom(next_gen[i]);
        birds[i].y = 28.0f; birds[i].vy = 0.0f;
        birds[i].alive = true; birds[i].fitness = 0; birds[i].pipes_passed = 0;
    }
    alive_count = POP_SIZE;
}

// ─── Custom bird sprite ───────────────────────────────────────────────────────
void draw_flappy_bird(int x, int y, bool is_black = false) {
    uint16_t color = is_black ? SSD1306_BLACK : SSD1306_WHITE;
    display.fillRoundRect(x + 1, y + 1, 6, 5, 2, color);
    display.fillRect(x + 5, y + 2, 3, 2, color);
    display.drawPixel(x + 4, y + 2, is_black ? SSD1306_WHITE : SSD1306_BLACK);
    display.fillRect(x, y + 2, 2, 2, color);
}

// ─── OLED render (training mode) ─────────────────────────────────────────────
static void draw_sim_training() {
    display.clearDisplay();

    int best_idx = best_alive_idx();

    // Pipes
    for (int p = 0; p < 2; p++) {
        int px  = (int)pipes[p].x;
        int top = pipes[p].gap_y - gap_size / 2;
        int bot = pipes[p].gap_y + gap_size / 2;
        int clip_top = max(top, 9);
        if (clip_top > 9)
            display.fillRect(px, 9, PIPE_WIDTH, clip_top - 9, SSD1306_WHITE);
        else if (top <= 9 && bot > 9) {
            // gap starts inside HUD zone — draw bottom pipe only
        } else {
            display.fillRect(px, 9, PIPE_WIDTH, top - 9, SSD1306_WHITE);
        }
        if (bot < SCREEN_HEIGHT)
            display.fillRect(px, bot, PIPE_WIDTH, SCREEN_HEIGHT - bot, SSD1306_WHITE);
    }

    // Birds
    for (int i = 0; i < POP_SIZE; i++) {
        if (!birds[i].alive) continue;
        int by = (int)birds[i].y;
        if (i == best_idx) {
            draw_flappy_bird(BIRD_X, by);
        } else {
            display.drawPixel(BIRD_X + BIRD_W / 2,     by + BIRD_H / 2,     SSD1306_WHITE);
            display.drawPixel(BIRD_X + BIRD_W / 2 + 1, by + BIRD_H / 2,     SSD1306_WHITE);
            display.drawPixel(BIRD_X + BIRD_W / 2,     by + BIRD_H / 2 + 1, SSD1306_WHITE);
            display.drawPixel(BIRD_X + BIRD_W / 2 + 1, by + BIRD_H / 2 + 1, SSD1306_WHITE);
        }
    }

    // HUD bar (top 8 rows, inverted)
    display.fillRect(0, 0, SCREEN_WIDTH, 8, SSD1306_WHITE);
    display.setTextColor(SSD1306_BLACK);
    display.setTextSize(1);
    display.setCursor(1, 0);
    if (sim_paused)
        display.printf("G:%d A:%d B:%d D:%d [PAUSED]", generation, alive_count, best_ever, current_difficulty);
    else
        display.printf("G:%d A:%d B:%d D:%d", generation, alive_count, best_ever, current_difficulty);

    // Mode tag (bottom row)
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 56);
    display.print("MODE: TRAINING");

    display.display();
}

// ─── OLED render (inference mode) ────────────────────────────────────────────
static void draw_sim_inference(int bird_y, bool just_flapped, int score, bool fpga_active) {
    display.clearDisplay();

    // Pipes
    for (int p = 0; p < 2; p++) {
        int px  = (int)pipes[p].x;
        int top = pipes[p].gap_y - gap_size / 2;
        int bot = pipes[p].gap_y + gap_size / 2;
        int clip_top = max(top, 9);
        if (clip_top > 9)
            display.fillRect(px, 9, PIPE_WIDTH, clip_top - 9, SSD1306_WHITE);
        else if (!(top <= 9 && bot > 9)) {
            display.fillRect(px, 9, PIPE_WIDTH, top - 9, SSD1306_WHITE);
        }
        if (bot < SCREEN_HEIGHT)
            display.fillRect(px, bot, PIPE_WIDTH, SCREEN_HEIGHT - bot, SSD1306_WHITE);
    }

    // Single best bird
    draw_flappy_bird(BIRD_X, bird_y);

    // HUD bar
    display.fillRect(0, 0, SCREEN_WIDTH, 8, SSD1306_WHITE);
    display.setTextColor(SSD1306_BLACK);
    display.setTextSize(1);
    display.setCursor(1, 0);
    display.printf("FPGA-INF  Scr:%d  D:%d", score, current_difficulty);

    // Mode tag (bottom row, inverted block to make it highly visible)
    display.fillRect(0, 55, SCREEN_WIDTH, 9, SSD1306_WHITE);
    display.setTextColor(SSD1306_BLACK);
    display.setCursor(2, 56);
    display.print(fpga_active ? "MODE: FPGA INF" : "MODE: FPGA INF*");

    display.display();
}

// ─── Epoch screen (training only) ────────────────────────────────────────────
static void draw_epoch_screen() {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(5, 8);
    display.printf("Gen %d complete", generation);
    display.setCursor(5, 20);
    display.printf("Best: %d obstacles", best_ever);
    display.setCursor(5, 32);
    display.println("Evolving...");
    display.setCursor(5, 44);
    display.printf("Pop: %d  Elite: %d", POP_SIZE, ELITE_COUNT);
    display.display();
}

// ─── Reset simulation (full GA state) ────────────────────────────────────────
void reset_simulation() {
    generation   = 1;
    best_ever    = 0;
    world_score  = 0;
    alive_count  = POP_SIZE;
    generation_seed = esp_random();
    if (!user_override_difficulty) {
        current_difficulty = 0x00;
    }
    update_difficulty_params();
    init_world();

    for (int i = 0; i < POP_SIZE; i++) {
        birds[i].nn.randomise();
        birds[i].y = 28.0f; birds[i].vy = 0.0f;
        birds[i].alive = true; birds[i].fitness = 0; birds[i].pipes_passed = 0;
    }
    best_ever_nn.randomise();   // reset saved best-ever network too
}

// ─── Send all weights to FPGA ─────────────────────────────────────────────────
// Format: 0xA5 header + 25 × 2 bytes (Q7.8, MSB first) = 51 bytes total
// Order: w0[0..15], b0[0..3], w1[0..3], b1[0]
static void send_weights_to_fpga(const NeuralNetwork& nn) {
    // Header
    FpgaSerial.write(0xA5);

    // w0 (16 values, input→hidden row-major [hidden][input])
    for (int i = 0; i < NN_W0_SIZE; i++) {
        int16_t v = f_to_q78(nn.w0[i]);
        FpgaSerial.write((uint8_t)(v >> 8));
        FpgaSerial.write((uint8_t)(v & 0xFF));
    }
    // b0 (4 values)
    for (int i = 0; i < NN_B0_SIZE; i++) {
        int16_t v = f_to_q78(nn.b0[i]);
        FpgaSerial.write((uint8_t)(v >> 8));
        FpgaSerial.write((uint8_t)(v & 0xFF));
    }
    // w1 (4 values, hidden→output)
    for (int i = 0; i < NN_W1_SIZE; i++) {
        int16_t v = f_to_q78(nn.w1[i]);
        FpgaSerial.write((uint8_t)(v >> 8));
        FpgaSerial.write((uint8_t)(v & 0xFF));
    }
    // b1 (1 value)
    {
        int16_t v = f_to_q78(nn.b1[0]);
        FpgaSerial.write((uint8_t)(v >> 8));
        FpgaSerial.write((uint8_t)(v & 0xFF));
    }
    FpgaSerial.flush();
}

// ─── Enter inference mode transition ─────────────────────────────────────────
// Called once when 0xFD (SW[9] HIGH) is received from FPGA.
static void enter_inference_mode() {
    // 1. Visual blink indicator
    for (int blink = 0; blink < 5; blink++) {
        display.clearDisplay();
        if (blink % 2 == 0) {
            display.fillRect(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, SSD1306_WHITE);
            display.setTextColor(SSD1306_BLACK);
            display.setTextSize(3);
            display.setCursor(22, 8);
            display.println("INF");
            display.setTextSize(1);
            display.setCursor(4, 40);
            display.println("INFERENCE MODE");
            display.setCursor(4, 52);
            display.println("FPGA CO-PROCESSOR");
        }
        // else: blank frame for flash effect
        display.display();
        delay(300);
    }
    delay(400);  // hold final state briefly

    // 2. Level reset: shrink to single best-bird slot
    sim_paused  = false;
    world_score = 0;
    generation_seed = esp_random();
    update_difficulty_params();
    init_world();

    // Only slot 0 is active in inference mode — copy best-ever network in
    birds[0].nn.copyFrom(best_ever_nn);
    birds[0].y = 28.0f; birds[0].vy = 0.0f;
    birds[0].alive = true; birds[0].fitness = 0; birds[0].pipes_passed = 0;
    alive_count = 1;

    // 3. Stream weights to FPGA
    send_weights_to_fpga(best_ever_nn);

    // Safety margin: give the FPGA time to finish processing the last weight
    // byte after FpgaSerial.flush() returns.  flush() empties the SW ring
    // buffer but the hardware shift register may still be clocking out the
    // final byte (~87 µs at 115200 baud).  If the ESP32 sends the first 0xBB
    // telemetry frame before the FPGA deasserts wload_active, the frame is
    // silently dropped and the bird never receives a flap decision.
    delay(80);

    inf_mode = true;
}

// ─── Exit inference mode transition ──────────────────────────────────────────
// Called when 0xFC (SW[9] LOW) is received from FPGA.
static void exit_inference_mode() {
    inf_mode = false;

    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(2);
    display.setCursor(2, 10);
    display.println("TRAINING");
    display.setTextSize(1);
    display.setCursor(2, 42);
    display.println("Resuming GA...");
    display.display();
    delay(600);

    // Restore full 30-bird swarm from current best-ever network
    for (int i = 0; i < POP_SIZE; i++) {
        birds[i].nn.copyFrom(best_ever_nn);
        if (i > 0) birds[i].nn.mutate(MUTATION_STD);
        birds[i].y = 28.0f; birds[i].vy = 0.0f;
        birds[i].alive = true; birds[i].fitness = 0; birds[i].pipes_passed = 0;
    }
    alive_count = POP_SIZE;
    world_score = 0;
    generation_seed = esp_random();
    init_world();
}

// ─── Setup ────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    Wire.begin(SDA_PIN, SCL_PIN, 400000);
    if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) { for (;;); }

    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(2);
    display.setCursor(2, 4);
    display.println("NEURO");
    display.println("EVOLUTION");
    display.setTextSize(1);
    display.setCursor(5, 46);
    display.printf("%d birds  |  4-4-1 NN", POP_SIZE);
    display.setCursor(5, 56);
    display.print("M3: FPGA INFER");
    display.display();
    delay(1800);

    // Bidirectional UART to FPGA: TX=16, RX=17, 115200 8N1
    FpgaSerial.begin(115200, SERIAL_8N1, UART_RX_PIN, UART_TX_PIN);

    randomSeed(esp_random());
    reset_simulation();
}

// ─── Main loop ────────────────────────────────────────────────────────────────
void loop() {
    uint32_t frame_start = millis();

    // ── 1. Process UART commands from FPGA ───────────────────────────────────
    while (FpgaSerial.available()) {
        uint8_t cmd = FpgaSerial.read();
        switch (cmd) {
            case 0xFE:   // KEY[0] — pause / resume (training mode only)
                if (!inf_mode) sim_paused = !sim_paused;
                break;

            case 0xFB:   // KEY[1] — full simulation reset
                if (!inf_mode) {
                    reset_simulation();
                } else {
                    // In inference mode: restart the single-bird level
                    world_score = 0;
                    generation_seed = esp_random();
                    init_world();
                    birds[0].y = 28.0f; birds[0].vy = 0.0f;
                    birds[0].alive = true; birds[0].fitness = 0; birds[0].pipes_passed = 0;
                    alive_count = 1;
                }
                break;

            case 0xFD:   // SW[9] HIGH — enter FPGA inference mode
                if (!inf_mode) enter_inference_mode();
                break;

            case 0xFC:   // SW[9] LOW  — return to training mode
                if (inf_mode) exit_inference_mode();
                break;

            default:     // 0x00-0x0F — difficulty override via SW[3:0]
                if (cmd <= 0x0F) {
                    current_difficulty = cmd;
                    user_override_difficulty = true;
                    update_difficulty_params();
                }
                break;
        }
    }

    // =========================================================================
    // INFERENCE MODE GAME LOOP
    // =========================================================================
    if (inf_mode) {
        if (sim_paused) {
            draw_sim_inference((int)birds[0].y, false, world_score, false);
            uint32_t e = millis() - frame_start;
            if (e < FRAME_MS) delay(FRAME_MS - e);
            return;
        }

        // ── Advance world ──────────────────────────────────────────────────
        advance_pipes();

        Bird& b = birds[0];

        if (b.alive) {
            // ── Build telemetry ───────────────────────────────────────────
            const Pipe* np   = nearest_pipe();
            float dx_raw     = np->x - (float)(BIRD_X + BIRD_W);
            float dy_raw     = (float)np->gap_y;

            float in_y  = clamp(b.y / (float)SCREEN_HEIGHT,             0.0f,  1.0f);
            float in_vy = clamp(b.vy / 6.0f,                           -1.0f,  1.0f);
            float in_dx = clamp(dx_raw / (float)SCREEN_WIDTH,           0.0f,  1.0f);
            float in_dy = clamp((b.y - dy_raw) / (float)SCREEN_HEIGHT, -1.0f,  1.0f);

            // ── Send telemetry frame to FPGA ──────────────────────────────
            // Format: 0xBB + 4 × signed Q0.7 bytes
            FpgaSerial.write((uint8_t)0xBB);
            FpgaSerial.write((uint8_t)f_to_q07(in_y));
            FpgaSerial.write((uint8_t)f_to_q07(in_vy));
            FpgaSerial.write((uint8_t)f_to_q07(in_dx));
            FpgaSerial.write((uint8_t)f_to_q07(in_dy));
            FpgaSerial.flush();

            // ── Poll for single-byte FPGA decision (block up to 10 ms) ───
            bool flap = false;
            bool fpga_replied = false;
            uint32_t poll_start = millis();
            while ((millis() - poll_start) < 10) {
                if (FpgaSerial.available()) {
                    uint8_t resp = FpgaSerial.read();
                    // Filter out legacy control bytes that may arrive asynchronously
                    if (resp == 0x01 || resp == 0x00) {
                        flap = (resp == 0x01);
                        fpga_replied = true;
                        break;
                    }
                    switch (resp) {
                        case 0xFE: /* pause in inf mode: ignore */ break;
                        case 0xFD: /* already in inf mode */       break;
                        case 0xFC: exit_inference_mode(); return;
                        case 0xFB: {
                            world_score = 0; generation_seed = esp_random();
                            init_world();
                            birds[0].y = 28.0f; birds[0].vy = 0.0f;
                            birds[0].alive = true; birds[0].fitness = 0;
                            birds[0].pipes_passed = 0; alive_count = 1;
                        } return;
                        default: if (resp <= 0x0F) {
                            current_difficulty = resp;
                            user_override_difficulty = true;
                            update_difficulty_params();
                        } break;
                    }
                }
            }
            // ── Fallback: FPGA wire not connected or weights not yet loaded ──
            // Use the local C++ NN so the bird still flies during the demo.
            // When the FPGA wire is in place this branch is never taken.
            if (!fpga_replied) {
                flap = best_ever_nn.forward(in_y, in_vy, in_dx, in_dy);
            }

            // ── Apply FPGA decision ───────────────────────────────────────
            if (flap) b.vy = JUMP_IMPULSE;

            b.vy += GRAVITY;
            b.y  += b.vy;
            b.fitness++;
            b.pipes_passed = world_score;

            if (collides(b)) {
                b.alive    = false;
                alive_count = 0;
            }

            // Render
            draw_sim_inference((int)b.y, flap, world_score, fpga_replied);

        } else {
            // Bird crashed — show crash screen then restart inference level
            display.clearDisplay();
            display.setTextColor(SSD1306_WHITE);
            display.setTextSize(2);
            display.setCursor(10, 8);
            display.println("CRASHED");
            display.setTextSize(1);
            display.setCursor(4, 32);
            display.printf("Score: %d  Best: %d", world_score, best_ever);
            display.setCursor(4, 44);
            display.println("FPGA INFERENCE");
            display.setCursor(4, 56);
            display.println("Restarting...");
            display.display();
            delay(2000);

            // Restart inference level (same weights already in FPGA)
            world_score = 0;
            generation_seed = esp_random();
            init_world();
            birds[0].y = 28.0f; birds[0].vy = 0.0f;
            birds[0].alive = true; birds[0].fitness = 0; birds[0].pipes_passed = 0;
            alive_count = 1;
        }

        uint32_t elapsed = millis() - frame_start;
        if (elapsed < FRAME_MS) delay(FRAME_MS - elapsed);
        return;
    }

    // =========================================================================
    // TRAINING MODE GAME LOOP  (full GA — unchanged from Milestone 2)
    // =========================================================================

    // ── Skip physics when paused ──────────────────────────────────────────────
    if (sim_paused) {
        draw_sim_training();
        uint32_t e = millis() - frame_start;
        if (e < FRAME_MS) delay(FRAME_MS - e);
        return;
    }

    // ── Advance world ─────────────────────────────────────────────────────────
    advance_pipes();

    // ── Per-bird NN inference + physics ──────────────────────────────────────
    const Pipe* np   = nearest_pipe();
    float dx_raw     = np->x - (float)(BIRD_X + BIRD_W);
    float dy_raw     = (float)np->gap_y;

    for (int i = 0; i < POP_SIZE; i++) {
        if (!birds[i].alive) continue;

        float in_y  = clamp(birds[i].y / (float)SCREEN_HEIGHT,              0.0f,  1.0f);
        float in_vy = clamp(birds[i].vy / 6.0f,                            -1.0f,  1.0f);
        float in_dx = clamp(dx_raw / (float)SCREEN_WIDTH,                   0.0f,  1.0f);
        float in_dy = clamp((birds[i].y - dy_raw) / (float)SCREEN_HEIGHT,  -1.0f,  1.0f);

        // Internal C++ NN — used exclusively in training mode
        if (birds[i].nn.forward(in_y, in_vy, in_dx, in_dy))
            birds[i].vy = JUMP_IMPULSE;

        birds[i].vy += GRAVITY;
        birds[i].y  += birds[i].vy;

        if (collides(birds[i])) {
            birds[i].alive = false;
            alive_count--;
        } else {
            birds[i].fitness++;
            birds[i].pipes_passed = world_score;
        }
    }

    // ── Epoch boundary ────────────────────────────────────────────────────────
    if (alive_count <= 0) {
        // Update best-ever record before evolving
        for (int i = 0; i < POP_SIZE; i++) {
            if (birds[i].pipes_passed > best_ever) {
                best_ever = birds[i].pipes_passed;
                best_ever_nn.copyFrom(birds[i].nn);
            }
        }
        draw_sim_training();
        draw_epoch_screen();
        delay(2500);
        run_epoch();
        return;
    }

    // ── Render ────────────────────────────────────────────────────────────────
    draw_sim_training();

    // ── Frame pacing ──────────────────────────────────────────────────────────
    uint32_t elapsed = millis() - frame_start;
    if (elapsed < FRAME_MS) delay(FRAME_MS - elapsed);
}

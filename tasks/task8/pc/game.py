import pygame
import serial
import serial.tools.list_ports
import threading
import time
import math
import random

CELL_SIZE = 40
MAP = [
    "WWWWWWWWWWWWWWW",
    "W.............W",
    "W.WW.WWW.WW.W.W",
    "W.WW.WWW.WW.W.W",
    "W.............W",
    "W.WW.W.W.WW.W.W",
    "W....W.W....W.W",
    "WWWW.W.W.WWWW.W",
    "W....W.W......W",
    "W.WW.W.W.WW.W.W",
    "W.............W",
    "W.WW.WWW.WW.W.W",
    "W.WW.WWW.WW.W.W",
    "W.............W",
    "WWWWWWWWWWWWWWW",
]

MAP_WIDTH = len(MAP[0])
MAP_HEIGHT = len(MAP)
SCREEN_WIDTH = MAP_WIDTH * CELL_SIZE
SCREEN_HEIGHT = MAP_HEIGHT * CELL_SIZE + 80

BLACK = (10, 10, 15)
BLUE = (0, 0, 200)
NEON_BLUE = (0, 150, 255)
YELLOW = (255, 255, 0)
WHITE = (255, 255, 255)
RED = (255, 50, 50)
PINK = (255, 150, 150)
CYAN = (50, 255, 255)
DARK_BLUE = (0, 0, 100)
LIGHT_BLUE = (100, 150, 255)
GREEN = (50, 255, 50)

UP = (0, -1)
DOWN = (0, 1)
LEFT = (-1, 0)
RIGHT = (1, 0)
DIRS = [UP, RIGHT, DOWN, LEFT]

state_dict = {
    'KEY0': 0, 'KEY1': 0,
    'SW0': 0, 'SW1': 0, 'SW2': 0,
    'SW3': 0, 'SW4': 0, 'SW5': 0,
    'SW6': 0, 'SW7': 0, 'SW8': 0, 'SW9': 0
}
state_lock = threading.Lock()

def log_debug(msg):
    try:
        with open("c:/Users/Inbal/Desktop/degree/semester 4/hackaton/TechCrash2026_inbal_liran/tasks/task8/pc/debug.log", "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} - {msg}\n")
    except Exception:
        pass

def serial_thread():
    port = None
    buffer = bytearray()
    port_open_time = 0
    last_read_time = time.time()
    while True:
        if port is None:
            ports = list(serial.tools.list_ports.comports())
            log_debug(f"Scanning ports... Found: {[p.device for p in ports]}")
            for p in ports:
                if "USB" in p.description or "UART" in p.description or "COM" in p.device:
                    try:
                        ser = serial.Serial(p.device, 115200, timeout=0.1)
                        port = ser
                        port_open_time = time.time()
                        log_debug(f"Successfully opened auto-detected port: {p.device}")
                        break
                    except Exception as e:
                        log_debug(f"Failed to open auto-detected port {p.device}: {str(e)}")
                        pass
            if port is None:
                try:
                    ser = serial.Serial('COM5', 115200, timeout=0.1)
                    port = ser
                    port_open_time = time.time()
                    log_debug("Successfully opened fallback port COM5")
                except Exception as e:
                    log_debug(f"Failed to open fallback COM5: {str(e)}")
                    time.sleep(0.5)
                    continue
        try:
            if port.in_waiting > 0:
                now = time.time()
                # Ignore first 2 seconds of data to discard ESP32 boot log
                if now - port_open_time < 2.0:
                    port.read(port.in_waiting)
                    time.sleep(0.01)
                    continue
                if now - last_read_time > 0.010:
                    buffer.clear()
                last_read_time = now

                data = port.read(port.in_waiting)
                log_debug(f"Read {len(data)} bytes: {list(data)}")
                buffer.extend(data)
                while len(buffer) >= 2:
                    if (buffer[0] & 0xF0) == 0:
                        high = buffer[0]
                        low = buffer[1]
                        val = (high << 8) | low
                        k0 = val & 1
                        k1 = (val >> 1) & 1
                        sw = [(val >> (j + 2)) & 1 for j in range(10)]
                        log_debug(f"Parsed packet: val=0x{val:04X} -> KEY0={k0}, KEY1={k1}, SW={sw}")
                        with state_lock:
                            state_dict['KEY0'] = k0
                            state_dict['KEY1'] = k1
                            for j in range(10):
                                state_dict[f'SW{j}'] = sw[j]
                        del buffer[:2]
                    else:
                        log_debug(f"Misaligned byte: 0x{buffer[0]:02X}")
                        del buffer[0]
            else:
                time.sleep(0.001)
        except Exception as e:
            log_debug(f"Error in read loop: {str(e)}")
            port = None
            time.sleep(0.5)

threading.Thread(target=serial_thread, daemon=True).start()

def is_wall(gx, gy, wall_phase):
    if gx < 0 or gx >= MAP_WIDTH or gy < 0 or gy >= MAP_HEIGHT:
        return True
    if MAP[gy][gx] == 'W':
        return not wall_phase
    return False

def get_map_cell(gx, gy):
    if gx < 0 or gx >= MAP_WIDTH or gy < 0 or gy >= MAP_HEIGHT:
        return 'W'
    return MAP[gy][gx]

class Pacman:
    def __init__(self, x, y):
        self.grid_x = x
        self.grid_y = y
        self.px = x * CELL_SIZE
        self.py = y * CELL_SIZE
        self.target_gx = x
        self.target_gy = y
        self.dir = RIGHT
        self.mouth_angle = 0
        self.mouth_opening = True

    def update(self, speed, wall_phase, queued_turn, queued_dir):
        tx = self.target_gx * CELL_SIZE
        ty = self.target_gy * CELL_SIZE
        dx = tx - self.px
        dy = ty - self.py
        consumed_phase = False

        if dx == 0 and dy == 0:
            self.grid_x = self.target_gx
            self.grid_y = self.target_gy

            new_dir = None
            if queued_turn == 'RIGHT':
                idx = DIRS.index(self.dir)
                new_dir = DIRS[(idx + 1) % 4]
            elif queued_turn == 'LEFT':
                idx = DIRS.index(self.dir)
                new_dir = DIRS[(idx - 1) % 4]
            elif queued_dir is not None:
                new_dir = queued_dir

            if new_dir is not None:
                next_x = self.grid_x + new_dir[0]
                next_y = self.grid_y + new_dir[1]
                if not is_wall(next_x, next_y, wall_phase):
                    self.dir = new_dir
                    queued_turn = None
                    queued_dir = None
                else:
                    queued_turn = None
                    queued_dir = None

            next_x = self.grid_x + self.dir[0]
            next_y = self.grid_y + self.dir[1]
            if not is_wall(next_x, next_y, wall_phase):
                self.target_gx = next_x
                self.target_gy = next_y
                if get_map_cell(next_x, next_y) == 'W':
                    consumed_phase = True
            else:
                self.target_gx = self.grid_x
                self.target_gy = self.grid_y
        else:
            step_x = math.copysign(min(speed, abs(dx)), dx) if dx != 0 else 0
            step_y = math.copysign(min(speed, abs(dy)), dy) if dy != 0 else 0
            self.px += step_x
            self.py += step_y

        if self.mouth_opening:
            self.mouth_angle += 4
            if self.mouth_angle >= 45:
                self.mouth_opening = False
        else:
            self.mouth_angle -= 4
            if self.mouth_angle <= 0:
                self.mouth_opening = True
        return consumed_phase, queued_turn, queued_dir

    def draw(self, screen):
        center = (int(self.px + CELL_SIZE // 2), int(self.py + CELL_SIZE // 2))
        radius = CELL_SIZE // 2 - 2
        
        if self.dir == RIGHT:
            start_ang, end_ang = self.mouth_angle, 360 - self.mouth_angle
        elif self.dir == LEFT:
            start_ang, end_ang = 180 + self.mouth_angle, 180 - self.mouth_angle + 360
        elif self.dir == UP:
            start_ang, end_ang = 90 + self.mouth_angle, 90 - self.mouth_angle + 360
        else:
            start_ang, end_ang = 270 + self.mouth_angle, 270 - self.mouth_angle + 360
            
        if self.mouth_angle < 5:
            pygame.draw.circle(screen, YELLOW, center, radius)
        else:
            points = [center]
            start_rad = math.radians(start_ang)
            end_rad = math.radians(end_ang)
            steps = 20
            for i in range(steps + 1):
                ang = start_rad + (end_rad - start_rad) * i / steps
                points.append((
                    center[0] + radius * math.cos(ang),
                    center[1] - radius * math.sin(ang)
                ))
            pygame.draw.polygon(screen, YELLOW, points)

class Ghost:
    def __init__(self, x, y, color):
        self.grid_x = x
        self.grid_y = y
        self.px = x * CELL_SIZE
        self.py = y * CELL_SIZE
        self.target_gx = x
        self.target_gy = y
        self.dir = UP
        self.color = color

    def update(self, speed):
        tx = self.target_gx * CELL_SIZE
        ty = self.target_gy * CELL_SIZE
        dx = tx - self.px
        dy = ty - self.py

        if dx == 0 and dy == 0:
            self.grid_x = self.target_gx
            self.grid_y = self.target_gy

            valid_dirs = []
            for d in DIRS:
                if d == (-self.dir[0], -self.dir[1]):
                    continue
                nx = self.grid_x + d[0]
                ny = self.grid_y + d[1]
                if not is_wall(nx, ny, False):
                    valid_dirs.append(d)

            if not valid_dirs:
                rev = (-self.dir[0], -self.dir[1])
                nx = self.grid_x + rev[0]
                ny = self.grid_y + rev[1]
                if not is_wall(nx, ny, False):
                    valid_dirs.append(rev)

            if valid_dirs:
                self.dir = random.choice(valid_dirs)
                self.target_gx = self.grid_x + self.dir[0]
                self.target_gy = self.grid_y + self.dir[1]
            else:
                self.target_gx = self.grid_x
                self.target_gy = self.grid_y
        else:
            step_x = math.copysign(min(speed, abs(dx)), dx) if dx != 0 else 0
            step_y = math.copysign(min(speed, abs(dy)), dy) if dy != 0 else 0
            self.px += step_x
            self.py += step_y

    def draw(self, screen, frightened, battery):
        center = (int(self.px + CELL_SIZE // 2), int(self.py + CELL_SIZE // 2))
        radius = CELL_SIZE // 2 - 2
        col = self.color
        if frightened:
            if battery < 30 and (int(time.time() * 5) % 2 == 0):
                col = WHITE
            else:
                col = DARK_BLUE

        rect = pygame.Rect(self.px + 2, self.py + 2, radius * 2, radius * 2)
        pygame.draw.ellipse(screen, col, rect)
        pygame.draw.rect(screen, col, (self.px + 2, self.py + CELL_SIZE // 2, radius * 2, radius))
        
        eye_radius = radius // 3
        pupil_radius = radius // 6
        
        left_eye_center = (int(self.px + CELL_SIZE // 3), int(self.py + CELL_SIZE // 3 + 2))
        pygame.draw.circle(screen, WHITE, left_eye_center, eye_radius)
        pupil_center = (
            left_eye_center[0] + self.dir[0] * pupil_radius,
            left_eye_center[1] + self.dir[1] * pupil_radius
        )
        pygame.draw.circle(screen, BLACK if not frightened else RED, pupil_center, pupil_radius)
        
        right_eye_center = (int(self.px + 2 * CELL_SIZE // 3), int(self.py + CELL_SIZE // 3 + 2))
        pygame.draw.circle(screen, WHITE, right_eye_center, eye_radius)
        pupil_center = (
            right_eye_center[0] + self.dir[0] * pupil_radius,
            right_eye_center[1] + self.dir[1] * pupil_radius
        )
        pygame.draw.circle(screen, BLACK if not frightened else RED, pupil_center, pupil_radius)

def main():
    pygame.init()
    screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
    pygame.display.set_caption("Pac-Man Hardware Bridge")
    clock = pygame.time.Clock()
    font = pygame.font.SysFont(None, 28)

    pacman = Pacman(1, 1)
    ghosts = [
        Ghost(6, 6, RED),
        Ghost(8, 6, PINK)
    ]

    pellets = []
    for gy in range(MAP_HEIGHT):
        for gx in range(MAP_WIDTH):
            if MAP[gy][gx] == '.':
                pellets.append((gx, gy))

    score = 0
    battery = 100.0
    wall_phase_active = False

    key0_prev = 0
    key1_prev = 0
    sw1_prev = 0

    queued_turn = None
    queued_dir = None

    running = True
    game_over = False

    while running:
        dt = clock.tick(60) / 1000.0

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key == pygame.K_UP:
                    queued_dir = UP
                elif event.key == pygame.K_DOWN:
                    queued_dir = DOWN
                elif event.key == pygame.K_LEFT:
                    queued_dir = LEFT
                elif event.key == pygame.K_RIGHT:
                    queued_dir = RIGHT
                elif event.key == pygame.K_SPACE:
                    wall_phase_active = True
                elif event.key == pygame.K_r and game_over:
                    pacman = Pacman(1, 1)
                    ghosts = [Ghost(6, 6, RED), Ghost(8, 6, PINK)]
                    score = 0
                    battery = 100.0
                    wall_phase_active = False
                    game_over = False

        with state_lock:
            k0 = state_dict['KEY0']
            k1 = state_dict['KEY1']
            sw0 = state_dict['SW0']
            sw1 = state_dict['SW1']
            sw2 = state_dict['SW2']

        if k0 == 1 and key0_prev == 0:
            queued_turn = 'RIGHT'
        if k1 == 1 and key1_prev == 0:
            queued_turn = 'LEFT'
        key0_prev = k0
        key1_prev = k1

        if sw1 == 1 and sw1_prev == 0:
            wall_phase_active = True
        sw1_prev = sw1

        if sw2 == 1 and battery > 0:
            frightened = True
            battery = max(0.0, battery - 25.0 * dt)
        else:
            frightened = False
            if sw2 == 0:
                battery = min(100.0, battery + 20.0 * dt)

        if not game_over:
            speed = 3.0 if sw0 == 1 else 2.0
            consumed, queued_turn, queued_dir = pacman.update(speed, wall_phase_active, queued_turn, queued_dir)
            if consumed:
                wall_phase_active = False

            ghost_speed = 1.0 if frightened else 2.0
            for g in ghosts:
                g.update(ghost_speed)

            p_cell = (pacman.grid_x, pacman.grid_y)
            if p_cell in pellets:
                pellets.remove(p_cell)
                score += 10

            for i, g in enumerate(ghosts):
                if g.grid_x == pacman.grid_x and g.grid_y == pacman.grid_y:
                    if frightened:
                        respawn_x = 6 if i == 0 else 8
                        respawn_y = 6
                        g.px = respawn_x * CELL_SIZE
                        g.py = respawn_y * CELL_SIZE
                        g.target_gx = respawn_x
                        g.target_gy = respawn_y
                        score += 200
                    else:
                        game_over = True

        screen.fill(BLACK)

        for gy in range(MAP_HEIGHT):
            for gx in range(MAP_WIDTH):
                if MAP[gy][gx] == 'W':
                    pygame.draw.rect(screen, BLUE if not wall_phase_active else NEON_BLUE,
                                     (gx * CELL_SIZE, gy * CELL_SIZE, CELL_SIZE, CELL_SIZE))

        for p in pellets:
            pygame.draw.circle(screen, WHITE, (p[0] * CELL_SIZE + CELL_SIZE // 2, p[1] * CELL_SIZE + CELL_SIZE // 2), 4)

        pacman.draw(screen)
        for g in ghosts:
            g.draw(screen, frightened, battery)

        # UI Panel
        pygame.draw.rect(screen, (20, 20, 30), (0, SCREEN_HEIGHT - 80, SCREEN_WIDTH, 80))
        
        score_text = font.render(f"SCORE: {score}", True, WHITE)
        screen.blit(score_text, (20, SCREEN_HEIGHT - 60))

        mode_str = "FRIGHTENED" if frightened else "NORMAL"
        mode_text = font.render(f"GHOST: {mode_str}", True, RED if frightened else GREEN)
        screen.blit(mode_text, (180, SCREEN_HEIGHT - 60))

        # Battery Bar
        pygame.draw.rect(screen, (50, 50, 50), (360, SCREEN_HEIGHT - 55, 100, 15))
        bat_color = GREEN if battery > 30 else RED
        pygame.draw.rect(screen, bat_color, (360, SCREEN_HEIGHT - 55, int(battery), 15))
        bat_text = font.render(f"BAT: {int(battery)}%", True, WHITE)
        screen.blit(bat_text, (360, SCREEN_HEIGHT - 35))

        phase_str = "ACTIVE" if wall_phase_active else "READY" if sw1 == 0 else "OFF"
        phase_color = NEON_BLUE if wall_phase_active else GREEN if sw1 == 0 else WHITE
        phase_text = font.render(f"PHASE: {phase_str}", True, phase_color)
        screen.blit(phase_text, (480, SCREEN_HEIGHT - 60))

        if game_over:
            over_text = font.render("GAME OVER - Press R to restart", True, RED)
            screen.blit(over_text, (SCREEN_WIDTH // 2 - 140, SCREEN_HEIGHT // 2 - 10))

        pygame.display.flip()

    pygame.quit()

if __name__ == "__main__":
    main()

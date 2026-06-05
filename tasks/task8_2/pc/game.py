import math
import random
import threading
import time
from enum import Enum

import pygame
import serial
from serial.tools import list_ports


MAZE = [
    "############################",
    "#o............##..........o#",
    "#.####.#####.##.#####.####.#",
    "#.#  #.#   #.##.#   #.#  #.#",
    "#o####.#####.##.#####.####o#",
    "#..........................#",
    "#.####.##.########.##.####.#",
    "#......##....##....##......#",
    "######.##### ## #####.######",
    "     #.#          #.#       ",
    "######.# ###GG### #.######  ",
    "      .  #      #  .        ",
    "######.# ######## #.######  ",
    "     #.#          #.#       ",
    "######.# ######## #.######  ",
    "#............P.............#",
    "#.####.#####.##.#####.####.#",
    "#o..##................##..o#",
    "###.##.##.########.##.##.###",
    "#......##....##....##......#",
    "#.##########.##.##########.#",
    "#..........................#",
    "#.####.#####.##.#####.####.#",
    "#o...#................#...o#",
    "###.#.##.########.##.#.###.#",
    "#...#.##....##....##.#...#.#",
    "#.###.#####.##.#####.###.#.#",
    "#..........................#",
    "############################",
]


class Direction(Enum):
    UP = (0, -1)
    DOWN = (0, 1)
    LEFT = (-1, 0)
    RIGHT = (1, 0)


OPPOSITE = {
    Direction.UP: Direction.DOWN,
    Direction.DOWN: Direction.UP,
    Direction.LEFT: Direction.RIGHT,
    Direction.RIGHT: Direction.LEFT,
}


class Game:
    def __init__(self, port="COM5", baudrate=115200):
        pygame.init()
        self.tile = 24
        self.cols = len(MAZE[0])
        self.rows = len(MAZE)
        self.header_h = 56
        self.width = self.cols * self.tile
        self.height = self.rows * self.tile + self.header_h
        self.screen = pygame.display.set_mode((self.width, self.height))
        pygame.display.set_caption("Pac-Man")
        self.clock = pygame.time.Clock()
        self.font = pygame.font.Font(None, 34)
        self.small_font = pygame.font.Font(None, 26)

        self.state = {
            "key0": False,
            "key1": False,
            "sw": [False] * 10,
            "lock": threading.Lock(),
        }

        self.walls = set()
        self.pellets = set()
        self.power_pellets = set()
        self.ghost_spawns = []
        self.pacman_spawn = (1, 1)
        self._parse_maze()

        self.pacman_pos = [float(self.pacman_spawn[0]), float(self.pacman_spawn[1])]
        self.current_direction = Direction.LEFT
        self.queued_direction = Direction.LEFT
        self.base_speed = 2.2
        self.speed_multiplier = 1.0
        self.phase_charge = False
        self.prev_sw1 = False

        self.fright_battery_max = 900
        self.fright_battery = self.fright_battery_max
        self.ghost_frightened = False

        self.score = 0
        self.lives = 3
        self.win = False
        self.running = True
        self.frame = 0
        self.center_epsilon = 0.02

        self.ghosts = []
        self._reset_entities()

        self.serial_port = self._open_serial(port, baudrate)
        if self.serial_port:
            self.serial_thread = threading.Thread(target=self._serial_reader, daemon=True)
            self.serial_thread.start()

    def _open_serial(self, preferred_port, baudrate):
        candidates = []
        if preferred_port:
            candidates.append(preferred_port)

        for p in list_ports.comports():
            if p.device not in candidates:
                candidates.append(p.device)

        for device in candidates:
            try:
                return serial.Serial(device, baudrate, timeout=0.0)
            except Exception:
                continue
        return None

    def _parse_maze(self):
        for y, row in enumerate(MAZE):
            for x, ch in enumerate(row):
                if ch == "#":
                    self.walls.add((x, y))
                elif ch == ".":
                    self.pellets.add((x, y))
                elif ch == "o":
                    self.power_pellets.add((x, y))
                elif ch == "P":
                    self.pacman_spawn = (x, y)
                elif ch == "G":
                    self.ghost_spawns.append((x, y))

    def _reset_entities(self):
        self.pacman_pos = [float(self.pacman_spawn[0]), float(self.pacman_spawn[1])]
        self.current_direction = Direction.LEFT
        self.queued_direction = Direction.LEFT

        colors = [(255, 64, 64), (255, 128, 255), (0, 255, 255), (255, 184, 82)]
        self.ghosts = []
        for i, spawn in enumerate(self.ghost_spawns[:4]):
            self.ghosts.append(
                {
                    "pos": [float(spawn[0]), float(spawn[1])],
                    "dir": random.choice(list(Direction)),
                    "color": colors[i % len(colors)],
                    "spawn": spawn,
                }
            )

    def _serial_reader(self):
        buffer = bytearray()
        while self.running:
            try:
                if self.serial_port and self.serial_port.in_waiting:
                    buffer.extend(self.serial_port.read(self.serial_port.in_waiting))
                    while len(buffer) >= 2:
                        high = buffer[0]
                        low = buffer[1]
                        del buffer[:2]

                        payload = (high << 8) | low
                        key0 = payload & 0x0001
                        key1 = (payload >> 1) & 0x0001
                        sw_val = (payload >> 2) & 0x03FF

                        with self.state["lock"]:
                            self.state["key0"] = bool(key0)
                            self.state["key1"] = bool(key1)
                            for i in range(10):
                                self.state["sw"][i] = bool((sw_val >> i) & 0x01)
                else:
                    time.sleep(0.001)
            except Exception:
                time.sleep(0.02)

    def _tile_is_wall(self, tx, ty):
        if tx < 0 or tx >= self.cols or ty < 0 or ty >= self.rows:
            return False
        return (tx, ty) in self.walls

    def _can_move(self, pos, direction):
        dx, dy = direction.value
        nx = pos[0] + dx * 0.52
        ny = pos[1] + dy * 0.52
        tx = int(round(nx))
        ty = int(round(ny))
        return not self._tile_is_wall(tx, ty)

    def _is_centered(self, pos):
        return (
            abs(pos[0] - round(pos[0])) < self.center_epsilon
            and abs(pos[1] - round(pos[1])) < self.center_epsilon
        )

    def _update_input(self):
        with self.state["lock"]:
            key0 = self.state["key0"]
            key1 = self.state["key1"]
            sw = self.state["sw"].copy()

        keys = pygame.key.get_pressed()
        if keys[pygame.K_UP]:
            self.queued_direction = Direction.UP
        elif keys[pygame.K_DOWN]:
            self.queued_direction = Direction.DOWN
        elif keys[pygame.K_LEFT]:
            self.queued_direction = Direction.LEFT
        elif keys[pygame.K_RIGHT]:
            self.queued_direction = Direction.RIGHT

        if key0:
            self.queued_direction = Direction.RIGHT
        if key1:
            self.queued_direction = Direction.LEFT

        self.speed_multiplier = 1.5 if sw[0] else 1.0

        if sw[1] and not self.prev_sw1:
            self.phase_charge = True
        self.prev_sw1 = sw[1]

        if sw[2] and self.fright_battery > 0:
            self.ghost_frightened = True
            self.fright_battery = max(0, self.fright_battery - 3)
        else:
            self.ghost_frightened = False
            self.fright_battery = min(self.fright_battery_max, self.fright_battery + 2)

    def _move_pacman(self):
        speed_tiles = (self.base_speed * self.speed_multiplier) / self.tile

        if self._is_centered(self.pacman_pos):
            self.pacman_pos[0] = round(self.pacman_pos[0])
            self.pacman_pos[1] = round(self.pacman_pos[1])
            if self._can_move(self.pacman_pos, self.queued_direction):
                self.current_direction = self.queued_direction

        dx, dy = self.current_direction.value
        nx = self.pacman_pos[0] + dx * speed_tiles
        ny = self.pacman_pos[1] + dy * speed_tiles

        target_tx = int(round(nx))
        target_ty = int(round(ny))
        blocked = self._tile_is_wall(target_tx, target_ty)

        if blocked and self.phase_charge:
            self.phase_charge = False
            blocked = False

        if not blocked:
            self.pacman_pos[0] = nx
            self.pacman_pos[1] = ny

        if self.pacman_pos[0] < -0.5:
            self.pacman_pos[0] = self.cols - 0.5
        elif self.pacman_pos[0] > self.cols - 0.5:
            self.pacman_pos[0] = -0.5

        tx = int(round(self.pacman_pos[0]))
        ty = int(round(self.pacman_pos[1]))
        if (tx, ty) in self.pellets:
            self.pellets.remove((tx, ty))
            self.score += 10
        if (tx, ty) in self.power_pellets:
            self.power_pellets.remove((tx, ty))
            self.score += 50
            self.ghost_frightened = True
            self.fright_battery = max(self.fright_battery, 300)

    def _choose_ghost_direction(self, ghost):
        dirs = [Direction.UP, Direction.DOWN, Direction.LEFT, Direction.RIGHT]
        valid = []
        for d in dirs:
            if d == OPPOSITE[ghost["dir"]]:
                continue
            if self._can_move(ghost["pos"], d):
                valid.append(d)

        if not valid:
            valid = [d for d in dirs if self._can_move(ghost["pos"], d)]
        if not valid:
            return ghost["dir"]

        if self.ghost_frightened:
            return random.choice(valid)

        pac_x, pac_y = self.pacman_pos
        best = valid[0]
        best_dist = 1e9
        for d in valid:
            dx, dy = d.value
            gx = ghost["pos"][0] + dx
            gy = ghost["pos"][1] + dy
            dist = abs(gx - pac_x) + abs(gy - pac_y)
            if dist < best_dist:
                best_dist = dist
                best = d
        return best

    def _update_ghosts(self):
        ghost_speed = 1.8 / self.tile
        if self.ghost_frightened:
            ghost_speed = 1.3 / self.tile

        for ghost in self.ghosts:
            if self._is_centered(ghost["pos"]):
                ghost["pos"][0] = round(ghost["pos"][0])
                ghost["pos"][1] = round(ghost["pos"][1])
                ghost["dir"] = self._choose_ghost_direction(ghost)

            dx, dy = ghost["dir"].value
            nx = ghost["pos"][0] + dx * ghost_speed
            ny = ghost["pos"][1] + dy * ghost_speed
            tx = int(round(nx))
            ty = int(round(ny))
            if not self._tile_is_wall(tx, ty):
                ghost["pos"][0] = nx
                ghost["pos"][1] = ny

            if ghost["pos"][0] < -0.5:
                ghost["pos"][0] = self.cols - 0.5
            elif ghost["pos"][0] > self.cols - 0.5:
                ghost["pos"][0] = -0.5

    def _check_collisions(self):
        px, py = self.pacman_pos
        for ghost in self.ghosts:
            gx, gy = ghost["pos"]
            if math.hypot(px - gx, py - gy) < 0.55:
                if self.ghost_frightened:
                    self.score += 200
                    ghost["pos"] = [float(ghost["spawn"][0]), float(ghost["spawn"][1])]
                    ghost["dir"] = random.choice(list(Direction))
                else:
                    self.lives -= 1
                    if self.lives <= 0:
                        self.running = False
                    else:
                        self._reset_entities()
                    return

        if not self.pellets and not self.power_pellets:
            self.win = True
            self.running = False

    def _tile_to_pixel(self, tx, ty):
        return int(tx * self.tile + self.tile / 2), int(ty * self.tile + self.header_h + self.tile / 2)

    def _draw_walls(self):
        for tx, ty in self.walls:
            x = tx * self.tile
            y = ty * self.tile + self.header_h
            rect = pygame.Rect(x, y, self.tile, self.tile)
            pygame.draw.rect(self.screen, (25, 48, 198), rect, border_radius=6)
            pygame.draw.rect(self.screen, (68, 115, 255), rect, 2, border_radius=6)

    def _draw_pellets(self):
        pulse = 0.75 + 0.25 * math.sin(self.frame * 0.15)
        for tx, ty in self.pellets:
            cx, cy = self._tile_to_pixel(tx, ty)
            pygame.draw.circle(self.screen, (255, 221, 160), (cx, cy), 3)
        for tx, ty in self.power_pellets:
            cx, cy = self._tile_to_pixel(tx, ty)
            pygame.draw.circle(self.screen, (255, 247, 200), (cx, cy), int(5 + 2 * pulse))

    def _draw_pacman(self):
        cx, cy = self._tile_to_pixel(self.pacman_pos[0], self.pacman_pos[1])
        r = int(self.tile * 0.42)
        mouth = 8 + int(20 * abs(math.sin(self.frame * 0.22)))

        if self.current_direction == Direction.RIGHT:
            a1, a2 = mouth, 360 - mouth
        elif self.current_direction == Direction.LEFT:
            a1, a2 = 180 + mouth, 180 - mouth
        elif self.current_direction == Direction.UP:
            a1, a2 = 270 + mouth, 270 - mouth
        else:
            a1, a2 = 90 + mouth, 90 - mouth

        pygame.draw.circle(self.screen, (255, 223, 0), (cx, cy), r)
        p1 = (cx, cy)
        p2 = (cx + int(r * math.cos(math.radians(a1))), cy - int(r * math.sin(math.radians(a1))))
        p3 = (cx + int(r * math.cos(math.radians(a2))), cy - int(r * math.sin(math.radians(a2))))
        pygame.draw.polygon(self.screen, (0, 0, 0), [p1, p2, p3])

    def _draw_ghost(self, ghost):
        cx, cy = self._tile_to_pixel(ghost["pos"][0], ghost["pos"][1])
        w = int(self.tile * 0.8)
        h = int(self.tile * 0.8)
        x = cx - w // 2
        y = cy - h // 2

        color = (64, 97, 255) if self.ghost_frightened else ghost["color"]
        pygame.draw.rect(self.screen, color, (x, y + h // 3, w, h // 2))
        pygame.draw.circle(self.screen, color, (cx, y + h // 3), w // 2)

        step = w // 4
        for i in range(3):
            lx = x + step // 2 + i * step
            pygame.draw.circle(self.screen, color, (lx, y + h - 1), step // 2)

        eye_y = y + h // 3
        pygame.draw.circle(self.screen, (255, 255, 255), (cx - w // 5, eye_y), 4)
        pygame.draw.circle(self.screen, (255, 255, 255), (cx + w // 5, eye_y), 4)
        pygame.draw.circle(self.screen, (20, 20, 120), (cx - w // 5, eye_y), 2)
        pygame.draw.circle(self.screen, (20, 20, 120), (cx + w // 5, eye_y), 2)

    def _draw_hud(self):
        pygame.draw.rect(self.screen, (7, 7, 15), (0, 0, self.width, self.header_h))
        title = self.font.render("PAC-MAN", True, (255, 227, 46))
        self.screen.blit(title, (12, 12))

        status = f"Score {self.score:05d}   Lives {self.lives}"
        status_surf = self.small_font.render(status, True, (220, 230, 255))
        self.screen.blit(status_surf, (190, 18))

        batt_w = 140
        batt_ratio = self.fright_battery / float(self.fright_battery_max)
        pygame.draw.rect(self.screen, (45, 52, 70), (self.width - batt_w - 20, 19, batt_w, 14), border_radius=7)
        pygame.draw.rect(
            self.screen,
            (74, 174, 255),
            (self.width - batt_w - 20, 19, int(batt_w * batt_ratio), 14),
            border_radius=7,
        )

        txt = self.small_font.render("FRIGHT", True, (180, 210, 255))
        self.screen.blit(txt, (self.width - batt_w - 86, 15))

        mods = f"SW0 speed:{'ON' if self.speed_multiplier > 1 else 'OFF'}  SW1 phase:{'ARMED' if self.phase_charge else 'OFF'}"
        mods_surf = self.small_font.render(mods, True, (150, 165, 190))
        self.screen.blit(mods_surf, (12, self.height - 28))

    def _render(self):
        self.screen.fill((0, 0, 0))
        self._draw_hud()
        self._draw_walls()
        self._draw_pellets()
        self._draw_pacman()
        for ghost in self.ghosts:
            self._draw_ghost(ghost)
        pygame.display.flip()

    def run(self):
        while self.running:
            self.frame += 1
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False

            self._update_input()
            self._move_pacman()
            self._update_ghosts()
            self._check_collisions()
            self._render()
            self.clock.tick(60)

        self._show_end_screen()
        pygame.quit()
        if self.serial_port:
            self.serial_port.close()

    def _show_end_screen(self):
        end_text = "YOU WIN" if self.win else "GAME OVER"
        t0 = time.time()
        while time.time() - t0 < 2.0:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    return
            self._render()
            overlay = pygame.Surface((self.width, self.height), pygame.SRCALPHA)
            overlay.fill((0, 0, 0, 130))
            self.screen.blit(overlay, (0, 0))
            txt = self.font.render(end_text, True, (255, 240, 120))
            sub = self.small_font.render(f"Score {self.score}", True, (240, 240, 240))
            self.screen.blit(txt, (self.width // 2 - txt.get_width() // 2, self.height // 2 - 24))
            self.screen.blit(sub, (self.width // 2 - sub.get_width() // 2, self.height // 2 + 14))
            pygame.display.flip()
            self.clock.tick(60)


if __name__ == "__main__":
    game = Game()
    game.run()

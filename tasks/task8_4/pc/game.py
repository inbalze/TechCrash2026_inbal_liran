import pygame, threading, serial, sys, random, math
import scores_io

TILE       = 24
COLS       = 21
ROWS       = 21
SCREEN_W   = COLS * TILE
SCREEN_H   = ROWS * TILE + 64
FPS        = 60
BASE_SPEED = 2.5
GHOST_SPD  = 2.0
SNAP_DIST  = 6

BLACK  = (0,   0,   0);  BLUE   = (33,  33, 222); YELLOW = (255, 255,   0)
WHITE  = (255, 255, 255); RED    = (220,  50,  50); PINK   = (255, 184, 255)
CYAN   = (0,   255, 255); ORANGE = (255, 184,  82); SCARED = (0,    0,  200)
DARKBG = (10,  10,  10)

RIGHT = ( 1,  0); LEFT  = (-1,  0)
UP    = ( 0, -1); DOWN  = ( 0,  1)
DIRS  = [RIGHT, LEFT, UP, DOWN]
DIR_A = {RIGHT: 0, DOWN: 90, LEFT: 180, UP: 270}

def rright(d): return {RIGHT: DOWN, DOWN: LEFT, LEFT: UP,   UP: RIGHT}[d]
def rleft(d):  return {RIGHT: UP,   UP: LEFT,   LEFT: DOWN, DOWN: RIGHT}[d]

MAZE = [
    "#####################",
    "#.........#.........#",
    "#.##.####.#.####.##.#",
    "#o##.####.#.####.##o#",
    "#.##.####.#.####.##.#",
    "#...................#",
    "#.###.#.#####.#.###.#",
    "#.....#.......#.....#",
    "#.###.#.#####.#.###.#",
    "#...................#",
    "##.##.###.#.###.##.##",
    "#.....#.......#.....#",
    "#.###.#.#####.#.###.#",
    "#.....#.......#.....#",
    "##.##.###.#.###.##.##",
    "#...................#",
    "#.###.#.#####.#.###.#",
    "#.....#.......#.....#",
    "#.###.#.#.#.#.#.###.#",
    "#.........#.........#",
    "#####################",
]

hw_lock  = threading.Lock()
hw_state = {k: 0 for k in ('KEY0', 'KEY1', 'SW0', 'SW1', 'SW2', 'SW9')}


class SerialThread(threading.Thread):
    def __init__(self, port):
        super().__init__(daemon=True)
        self.running = True
        try:
            self.ser = serial.Serial(port, 115200, timeout=0.1)
        except Exception as e:
            print(f"[serial] {e}"); self.ser = None

    def run(self):
        if not self.ser:
            return
        while self.running:
            try:
                b = self.ser.read(1)
                if not b: continue
                hi = b[0]
                if hi & 0xF0: continue
                lo = self.ser.read(1)
                if not lo: continue
                v = (hi << 8) | lo[0]
                with hw_lock:
                    hw_state['KEY0'] = v & 1
                    hw_state['KEY1'] = (v >> 1) & 1
                    hw_state['SW0']  = (v >> 2) & 1
                    hw_state['SW1']  = (v >> 3) & 1
                    hw_state['SW2']  = (v >> 4) & 1
                    hw_state['SW9']  = (v >> 11) & 1
            except Exception:
                pass

    def stop(self):
        self.running = False
        if self.ser: self.ser.close()


class Grid:
    def __init__(self):
        self._d   = [list(r) for r in MAZE]
        self.pels = {(c, r) for r, row in enumerate(self._d)
                     for c, ch in enumerate(row) if ch == '.'}
        self.pows = {(c, r) for r, row in enumerate(self._d)
                     for c, ch in enumerate(row) if ch == 'o'}

    def wall(self, c, r):
        if not (0 <= c < COLS and 0 <= r < ROWS): return True
        return self._d[r][c] == '#'

    def eat(self, c, r):
        if (c, r) in self.pels: self.pels.discard((c, r)); return 'p'
        if (c, r) in self.pows: self.pows.discard((c, r)); return 'P'
        return None

    def draw(self, s):
        for r in range(ROWS):
            for c in range(COLS):
                x, y = c * TILE, r * TILE
                if self._d[r][c] == '#':
                    pygame.draw.rect(s, BLUE,        (x, y, TILE, TILE))
                    pygame.draw.rect(s, (20, 20, 100),(x+1, y+1, TILE-2, TILE-2), 1)
        for c, r in self.pels:
            pygame.draw.circle(s, WHITE, (c*TILE+TILE//2, r*TILE+TILE//2), 3)
        for c, r in self.pows:
            pygame.draw.circle(s, WHITE, (c*TILE+TILE//2, r*TILE+TILE//2), 7)


class PacMan:
    def __init__(self, grid):
        self.grid   = grid
        self.px     = float(10*TILE + TILE//2)
        self.py     = float(9*TILE + TILE//2)
        self.dir    = LEFT
        self.queued = LEFT
        self.speed  = BASE_SPEED
        self.phase  = False
        self.score  = 0
        self.alive  = True
        self.tick   = 0
        self.stuck  = 0

    def _tile(self):
        return int(self.px // TILE), int(self.py // TILE)

    def _cen(self, c, r):
        return float(c*TILE + TILE//2), float(r*TILE + TILE//2)

    def _at_cen(self):
        c, r   = self._tile()
        cx, cy = self._cen(c, r)
        return abs(self.px - cx) <= SNAP_DIST and abs(self.py - cy) <= SNAP_DIST

    def update(self, speed_mod):
        if not self.alive: return
        self.speed = BASE_SPEED * speed_mod
        c, r   = self._tile()
        cx, cy = self._cen(c, r)

        if abs(self.px - cx) < self.speed and abs(self.py - cy) < self.speed:
            self.px, self.py = cx, cy

            # 1. Handle queued direction change
            if self.queued != self.dir:
                nc, nr  = c + self.queued[0], r + self.queued[1]
                blocked = self.grid.wall(nc, nr)
                if not blocked:
                    self.dir = self.queued
                    self.queued = self.dir
                elif self.phase:
                    self.phase = False
                    self.dir = self.queued
                    self.queued = self.dir
                    self.stuck = 0
                    self.px += self.dir[0] * self.speed
                    self.py += self.dir[1] * self.speed
                    self.tick += 1
                    return
                else:
                    self.queued = self.dir

            # 2. Handle straight movement wall collision
            nc, nr = c + self.dir[0], r + self.dir[1]
            if self.grid.wall(nc, nr):
                if self.phase:
                    self.phase = False
                else:
                    return

        self.px += self.dir[0] * self.speed
        self.py += self.dir[1] * self.speed

        c, r = self._tile()
        res  = self.grid.eat(c, r)
        if res == 'p': self.score += 10
        if res == 'P': self.score += 50
        self.tick += 1

    def draw(self, s):
        if not self.alive: return
        x, y = int(self.px), int(self.py)
        rad  = TILE // 2 - 2
        ma   = 30 + 25 * abs(math.sin(self.tick * 0.15))
        ang  = DIR_A.get(self.dir, 0)
        pygame.draw.circle(s, YELLOW, (x, y), rad)
        pts = [(x, y)]
        for a in range(int(ang - ma), int(ang + ma) + 1, 3):
            pts.append((int(x + rad * math.cos(math.radians(a))),
                        int(y + rad * math.sin(math.radians(a)))))
        if len(pts) >= 3:
            pygame.draw.polygon(s, BLACK, pts)


class Ghost:
    def __init__(self, grid, sc, sr, color):
        self.grid = grid
        self.sc, self.sr = sc, sr
        self.px   = float(sc*TILE + TILE//2)
        self.py   = float(sr*TILE + TILE//2)
        _v = [d for d in DIRS if not self.grid.wall(sc+d[0], sr+d[1])]
        self.dir  = random.choice(_v) if _v else random.choice(DIRS)
        self.color      = color
        self.frightened = False
        self.eaten      = False

    def _tile(self):
        return int(self.px // TILE), int(self.py // TILE)

    def _cen(self, c, r):
        return float(c*TILE + TILE//2), float(r*TILE + TILE//2)

    def _at_cen(self):
        c, r   = self._tile()
        cx, cy = self._cen(c, r)
        return abs(self.px - cx) <= SNAP_DIST and abs(self.py - cy) <= SNAP_DIST

    def respawn(self):
        self.px, self.py    = float(self.sc*TILE+TILE//2), float(self.sr*TILE+TILE//2)
        _v = [d for d in DIRS if not self.grid.wall(self.sc+d[0], self.sr+d[1])]
        self.dir            = random.choice(_v) if _v else random.choice(DIRS)
        self.frightened     = False
        self.eaten          = False

    def update(self, tpx, tpy, scatter=False):
        spd = GHOST_SPD * (2.5 if self.eaten else 0.6 if self.frightened else 1.0)

        if self.eaten:
            tx, ty = float(self.sc*TILE+TILE//2), float(self.sr*TILE+TILE//2)
            if math.hypot(self.px - tx, self.py - ty) < spd * 2:
                self.respawn(); return
            dx, dy   = tx - self.px, ty - self.py
            self.dir = (RIGHT if abs(dx) >= abs(dy) and dx > 0 else
                        LEFT  if abs(dx) >= abs(dy) and dx < 0 else
                        DOWN  if dy > 0 else UP)
            self.px += self.dir[0] * spd
            self.py += self.dir[1] * spd
            return

        # Safety: redirect before hitting a wall
        _c, _r = self._tile()
        if self.grid.wall(_c + self.dir[0], _r + self.dir[1]):
            _cx, _cy = self._cen(_c, _r)
            self.px, self.py = _cx, _cy
            _opp = (-self.dir[0], -self.dir[1])
            _v = [d for d in DIRS if d != _opp and not self.grid.wall(_c+d[0], _r+d[1])]
            if not _v: _v = [d for d in DIRS if not self.grid.wall(_c+d[0], _r+d[1])]
            if not _v: return
            self.dir = random.choice(_v)

        # Move first, then check if we've arrived at a new tile center
        self.px += self.dir[0] * spd
        self.py += self.dir[1] * spd

        c, r   = self._tile()
        cx, cy = self._cen(c, r)
        if abs(self.px - cx) < spd and abs(self.py - cy) < spd:
            self.px, self.py = cx, cy
            opp   = (-self.dir[0], -self.dir[1])
            valid = [d for d in DIRS
                     if d != opp and not self.grid.wall(c+d[0], r+d[1])]
            if not valid: valid = [opp]
            if self.frightened:
                self.dir = random.choice(valid)
            elif scatter:
                self.dir = max(valid, key=lambda d:
                    ((c+d[0])*TILE + TILE//2 - tpx)**2 +
                    ((r+d[1])*TILE + TILE//2 - tpy)**2)
            else:
                self.dir = min(valid, key=lambda d:
                    ((c+d[0])*TILE + TILE//2 - tpx)**2 +
                    ((r+d[1])*TILE + TILE//2 - tpy)**2)

    def draw(self, s):
        x, y = int(self.px), int(self.py)
        rad  = TILE // 2 - 2
        col  = WHITE if self.eaten else SCARED if self.frightened else self.color
        pygame.draw.circle(s, col, (x, y - rad//4), rad)
        pygame.draw.rect(s,   col, (x - rad, y - rad//4, rad*2, rad + rad//2))
        if not self.eaten:
            ey = y - rad // 2
            for ex in (x - rad//3, x + rad//3):
                pygame.draw.circle(s, WHITE, (ex, ey), rad//4)
                if not self.frightened:
                    dx, dy = self.dir
                    pygame.draw.circle(s, (0, 0, 150),
                                       (ex + dx*2, ey + dy*2), max(1, rad//6))


class Game:
    def __init__(self, port):
        pygame.init()
        self.screen  = pygame.display.set_mode((SCREEN_W, SCREEN_H))
        pygame.display.set_caption("PAC-MAN  [HW]")
        self.clock   = pygame.time.Clock()
        self.fnt_s   = pygame.font.SysFont(None, 22)
        self.fnt_l   = pygame.font.SysFont(None, 64)
        self.serial  = SerialThread(port)
        self.serial.start()
        import time as _t; _t.sleep(0.4)
        with hw_lock:
            self.sw9_prev = hw_state['SW9']
        self.high_score = scores_io.load().get('pacman', 0)
        self._reset()

    def _reset(self):
        self.grid       = Grid()
        self.pac        = PacMan(self.grid)
        self.ghosts     = [
            Ghost(self.grid,  1,  1, RED),
            Ghost(self.grid, 19,  1, PINK),
            Ghost(self.grid,  1, 19, CYAN),
            Ghost(self.grid, 19, 19, ORANGE),
        ]
        self.battery    = 100.0
        self.paused     = False
        self.prev_hw    = {k: 0 for k in ('KEY0', 'KEY1', 'SW0', 'SW1', 'SW2')}
        self.hit_timer  = 0
        self.scatter_timer = 300
        self.lives      = 3
        self.state      = 'playing'

    def _hw(self):
        with hw_lock: return dict(hw_state)

    def _battery_tick(self, hw):
        if hw['SW2']:
            if self.battery > 0:
                self.battery = max(0.0, self.battery - 0.4)
                return True
            return False
        self.battery = min(100.0, self.battery + 0.08)
        return False

    def update(self):
        hw = self._hw()

        if hw['KEY0'] and not self.prev_hw['KEY0']:
            self.pac.queued = rright(self.pac.dir)
        if hw['KEY1'] and not self.prev_hw['KEY1']:
            self.pac.queued = rleft(self.pac.dir)

        frighten = self._battery_tick(hw)

        for g in self.ghosts:
            if not g.eaten: g.frightened = frighten

        # Update ghosts all the time during gameplay (even if hit_timer > 0)
        # Force scatter to True during hit_timer to keep ghosts away from the center spawn
        scatter = (self.scatter_timer > 0) or (self.hit_timer > 0)
        if self.hit_timer == 0:
            if self.scatter_timer > 0:
                self.scatter_timer -= 1
        for g in self.ghosts:
            g.update(self.pac.px, self.pac.py, scatter)

        if self.hit_timer > 0:
            self.hit_timer -= 1
            self.prev_hw = hw
            return

        self.pac.update(1.5 if hw['SW0'] else 1.0)

        for g in self.ghosts:
            if g.eaten: continue
            if math.hypot(self.pac.px - g.px, self.pac.py - g.py) < TILE * 0.75:
                if g.frightened:
                    g.eaten = True
                    self.pac.score += 200
                else:
                    self.lives    -= 1
                    self.hit_timer = 90
                    self.pac.px    = float(10*TILE + TILE//2)
                    self.pac.py    = float(9*TILE + TILE//2)
                    self.pac.dir   = self.pac.queued = LEFT
                    self.pac.stuck = 0
                    for ghost in self.ghosts:
                        ghost.respawn()
                    if self.lives <= 0:
                        self.state = 'game_over'
                        scores_io.save('pacman', self.pac.score)
                        self.high_score = max(self.high_score, self.pac.score)
                    break

        if not self.grid.pels and not self.grid.pows:
            self.state = 'win'
            scores_io.save('pacman', self.pac.score)
            self.high_score = max(self.high_score, self.pac.score)

        self.prev_hw = hw

    def _draw_ui(self):
        uy = ROWS * TILE + 6
        self.screen.blit(self.fnt_s.render(
            f"SCORE  {self.pac.score}    BEST {self.high_score}", True, WHITE), (6, uy))

        bx, by = SCREEN_W // 2 - 55, uy
        pygame.draw.rect(self.screen, (50, 50, 50), (bx, by, 110, 14))
        bw  = int(110 * self.battery / 100)
        bc  = ((0, 200, 0) if self.battery > 50 else
               (200, 200, 0) if self.battery > 20 else (200, 0, 0))
        pygame.draw.rect(self.screen, bc,    (bx, by, bw, 14))
        pygame.draw.rect(self.screen, WHITE, (bx, by, 110, 14), 1)
        self.screen.blit(self.fnt_s.render("BAT", True, YELLOW), (bx - 30, by - 1))

        for i in range(self.lives):
            pygame.draw.circle(self.screen, YELLOW,
                               (SCREEN_W - 14 - i * 20, uy + 7), 7)

        if self.pac.phase:
            self.screen.blit(self.fnt_s.render("PHASE READY", True, CYAN), (6, uy + 18))
        if self.scatter_timer > 0:
            secs = math.ceil(self.scatter_timer / 60)
            self.screen.blit(self.fnt_s.render(f"SCATTER  {secs}s", True, (100, 220, 255)),
                             (SCREEN_W - 110, uy + 18))



    def draw(self):
        self.screen.fill(DARKBG)
        self.grid.draw(self.screen)
        self.pac.draw(self.screen)
        for g in self.ghosts: g.draw(self.screen)
        self._draw_ui()

        if self.paused:
            lbl = self.fnt_l.render("PAUSED", True, YELLOW)
            self.screen.blit(lbl, (SCREEN_W//2 - lbl.get_width()//2, SCREEN_H//2 - 40))
        elif self.state == 'game_over':
            lbl = self.fnt_l.render("GAME OVER", True, RED)
            self.screen.blit(lbl, (SCREEN_W//2 - lbl.get_width()//2, SCREEN_H//2 - 40))
            sub = self.fnt_s.render("flip SW9 to restart", True, WHITE)
            self.screen.blit(sub, (SCREEN_W//2 - sub.get_width()//2, SCREEN_H//2 + 32))
        elif self.state == 'win':
            lbl = self.fnt_l.render("YOU WIN!", True, YELLOW)
            self.screen.blit(lbl, (SCREEN_W//2 - lbl.get_width()//2, SCREEN_H//2 - 40))
            sub = self.fnt_s.render("flip SW9 to restart", True, WHITE)
            self.screen.blit(sub, (SCREEN_W//2 - sub.get_width()//2, SCREEN_H//2 + 32))

        pygame.display.flip()

    def run(self):
        while True:
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    self.serial.stop(); pygame.quit(); sys.exit()
            hw = self._hw()
            sw9 = hw['SW9']
            if sw9 == 1 and self.sw9_prev == 0:
                if self.state == 'playing':
                    self.serial.stop(); pygame.quit(); sys.exit()
                else:
                    self._reset()
            self.sw9_prev = sw9
            
            # Check if SW1 is flipped on to pause the game
            self.paused = (hw['SW1'] == 1)
            
            if self.paused:
                self.prev_hw = hw
            elif self.state == 'playing':
                self.update()
            else:
                scatter = self.scatter_timer > 0
                for g in self.ghosts:
                    g.update(self.pac.px, self.pac.py, scatter)
            self.draw()
            self.clock.tick(FPS)


if __name__ == '__main__':
    import traceback, os
    log = os.path.join(os.path.dirname(__file__), 'game_crash.log')
    try:
        Game(sys.argv[1] if len(sys.argv) > 1 else 'COM5').run()
    except BaseException:
        with open(log, 'w') as f:
            traceback.print_exc(file=f)
        raise

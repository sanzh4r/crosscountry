#!/usr/bin/env python3
"""Draws three dashboard ideas over a game frame, for the owner to choose from.

    python3 art/dash_mock.py          ->  art/probe/dash-options.png, art/probe/dash-zoom.png
    python3 art/dash_mock.py export   ->  App/Resources/Art/dash.png (option A, the one chosen)

Everything is drawn pixel by pixel at the game's own resolution (640x360) in colours taken from
the game's palette, so the mock shows what the real thing would look like.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import compose  # noqa: E402

PAL = compose.master_palette()


def near(r, g, b):
    return tuple(min(PAL, key=lambda p: (p[0] - r) ** 2 + (p[1] - g) ** 2 + (p[2] - b) ** 2)) + (255,)


INK = near(40, 28, 40)
NIGHT = near(57, 38, 73)
PLUM = near(95, 55, 85)
CREAM = near(246, 232, 184)
SAND = near(236, 178, 97)
ORANGE = near(223, 144, 83)
BRASS = near(166, 114, 68)
BROWN = near(122, 72, 51)
RED = near(190, 70, 70)
MAGENTA = near(160, 70, 100)
HOT = (216, 74, 62, 255)      # warning red: brighter than anything in the scenery, on purpose

DIGITS = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
    "4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001001001001",
    "8": "111101111101111", "9": "111101111001111",
}


def digits(px, x, y, text, col, scale=1, shadow=None):
    for ch in text:
        bits = DIGITS[ch]
        for i, b in enumerate(bits):
            if b == "1":
                for dx in range(scale):
                    for dy in range(scale):
                        cx, cy = x + (i % 3) * scale + dx, y + (i // 3) * scale + dy
                        if shadow:
                            px[cx + 1, cy + 1] = shadow
                        px[cx, cy] = col
        x += 4 * scale


def disc(px, cx, cy, r, col, top_only=False):
    for dy in range(-r, 1 if top_only else r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r + r * 0.8:
                px[cx + dx, cy + dy] = col


def polar(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + math.cos(a) * r, cy - math.sin(a) * r


def tick(draw, cx, cy, r1, r2, deg, col):
    draw.line([polar(cx, cy, r1, deg), polar(cx, cy, r2, deg)], fill=col)


def needle(draw, cx, cy, r, deg, col, tail=4):
    draw.line([polar(cx, cy, -tail, deg), polar(cx, cy, r, deg)], fill=col)


def sweep(t, start=225, span=270):
    return start - span * t


# ---------------------------------------------------------------- A: twin brass clocks

def clock(im, cx, cy, r, value, redline=None, number=None, face_only=False):
    px, draw = im.load(), ImageDraw.Draw(im)
    disc(px, cx, cy, r + 1, INK)
    disc(px, cx, cy, r, BRASS)
    disc(px, cx - 1, cy - 1, r - 1, SAND)       # highlight on the upper-left of the rim
    disc(px, cx, cy, r - 2, BRASS)
    disc(px, cx, cy, r - 3, INK)
    disc(px, cx, cy, r - 4, CREAM)
    steps = 12
    for i in range(steps + 1):
        t = i / steps
        hot = redline is not None and t >= redline
        long = i % 2 == 0
        tick(draw, cx, cy, r - 5, r - (9 if long else 7), sweep(t), RED if hot else INK)
    if redline is not None:
        for d in range(int(sweep(1)), int(sweep(redline)) + 1):
            for rr in (r - 5, r - 6):
                x, y = polar(cx, cy, rr, d)
                px[round(x), round(y)] = RED
    if face_only:
        return
    if number is not None:
        text = str(number)
        digits(px, cx - len(text) * 2 + 1, cy + r // 2 - 3, text, BROWN)
    needle(draw, cx, cy, r - 7, sweep(value), RED)
    disc(px, cx, cy, 2, INK)
    px[cx, cy] = BRASS


def option_a(im, speed, revs, heat, face_only=False):
    clock(im, 289, 33, 26, speed, number=round(speed * 120), face_only=face_only)
    clock(im, 351, 33, 26, revs, redline=0.8, face_only=face_only)
    # Small temperature clock tucked between and below the two, as on an old twin-clock bike.
    px, draw = im.load(), ImageDraw.Draw(im)
    cx, cy, r = 320, 53, 10
    disc(px, cx, cy, r + 1, INK)
    disc(px, cx, cy, r, BRASS)
    disc(px, cx, cy, r - 2, CREAM)
    for i in range(5):
        tick(draw, cx, cy, r - 3, r - 5, sweep(i / 4, 200, 220), RED if i == 4 else INK)
    if face_only:
        return
    needle(draw, cx, cy, r - 4, sweep(heat, 200, 220), RED, tail=0)
    px[cx, cy] = INK


# The dashboard built into the game: option A, enlarged after the owner found it too small to read.
# Left: speed. Right: engine heat, the one that matters (the engine cuts out when it is full).
# Small: revs. DashboardNode.swift holds the same numbers.
BIG_R, SMALL_R = 34, 14
SPEED_C, HEAT_C, REV_C = (36, 36), (116, 36), (76, 62)
DASH_SIZE = (153, 78)
FLAME = ["...#...", "..##...", "..###..", ".####.#", ".######", "#######", "##.####", "##..###", ".#...#."]


def face(im, cx, cy, r, steps, redline=None, start=225, span=270, numerals=None, top=120):
    px, draw = im.load(), ImageDraw.Draw(im)
    big = r > 20
    disc(px, cx, cy, r + 1, INK)
    disc(px, cx, cy, r, BRASS)
    disc(px, cx - 1, cy - 1, r - 1, SAND)
    disc(px, cx, cy, r - 2, BRASS)
    disc(px, cx, cy, r - 3, INK)
    disc(px, cx, cy, r - 4, CREAM)
    if redline is not None:
        for d10 in range(int(sweep(1, start, span)) * 10, int(sweep(redline, start, span)) * 10 + 1, 4):
            for rr in range(r - 5 - (3 if big else 1), r - 4):
                x, y = polar(cx, cy, rr, d10 / 10)
                px[round(x), round(y)] = RED
    for i in range(steps + 1):
        t = i / steps
        long = i % 2 == 0
        hot = redline is not None and t >= redline
        length = (7 if long else 4) if big else (3 if long else 2)
        tick(draw, cx, cy, r - 5, r - 5 - length, sweep(t, start, span), INK if not hot or big else RED)
    for n in numerals or []:
        text = str(n)
        x, y = polar(cx, cy, r - 18, sweep(n / top, start, span))
        digits(px, round(x) - len(text) * 2 + 1, round(y) - 2, text, BROWN)


def flame(px, x, y, body, core=None):
    for j, row in enumerate(FLAME):
        for i, ch in enumerate(row):
            if ch == "#":
                px[x + i, y + j] = core if core and 2 <= i <= 4 and j >= 5 else body


def dashboard(sample=None):
    im = Image.new("RGBA", DASH_SIZE, (0, 0, 0, 0))
    face(im, *SPEED_C, BIG_R, 12, numerals=[40, 80])
    face(im, *HEAT_C, BIG_R, 12, redline=0.7)
    face(im, *REV_C, SMALL_R, 8, redline=0.8, start=200, span=220)
    if sample:                                   # moving parts, only for the preview
        px, draw = im.load(), ImageDraw.Draw(im)
        speed, heat, revs = sample
        digits(px, SPEED_C[0] - 8 + 1, 50, str(round(speed * 120)), BROWN, scale=2)
        flame(px, HEAT_C[0] - 3, 50, RED, SAND)
        for (cx, cy), r, v, st, sp in ((SPEED_C, BIG_R, speed, 225, 270), (HEAT_C, BIG_R, heat, 225, 270),
                                       (REV_C, SMALL_R, revs, 200, 220)):
            big = r > 20
            a, b = polar(cx, cy, -5 if big else 0, sweep(v, st, sp)), polar(cx, cy, r - (9 if big else 5), sweep(v, st, sp))
            draw.line([a, b], fill=RED, width=2 if big else 1)
            disc(px, cx, cy, 3 if big else 1, INK)
            px[cx, cy] = BRASS
    return im


# ---------------------------------------------------------------- Digital (the one chosen)

SEGMENTS = {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc",
            "7": "abc", "8": "abcdefg", "9": "abfgcd"}
LETTERS = {"k": "101101110101101", "m": "000000111111101", "/": "001001010100100", "h": "100100110101101"}


def seven(px, x, y, ch, col, w=13, h=23, t=3):
    """One seven-segment digit with its top-left at (x, y)."""
    m = h // 2
    boxes = {"a": (1, 0, w - 2, t - 1), "g": (1, m - 1, w - 2, m + 1), "d": (1, h - t, w - 2, h - 1),
             "f": (0, 1, t - 1, m - 1), "b": (w - t, 1, w - 1, m - 1),
             "e": (0, m + 1, t - 1, h - 2), "c": (w - t, m + 1, w - 1, h - 2)}
    for seg in SEGMENTS[ch]:
        x0, y0, x1, y1 = boxes[seg]
        for yy in range(y0, y1 + 1):
            for xx in range(x0, x1 + 1):
                px[x + xx, y + yy] = col


def digital(speed, heat, flash=False):
    """Dark instrument panel: speed as lit digits, engine heat as a bar that fills toward a red zone.
    With speed None only the fixed parts are drawn (the game draws the rest, see DashboardNode.swift)."""
    w, h = 150, 62
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()
    hot = heat >= 0.7
    for y in range(h):
        for x in range(w):
            corner = (x < 2 or x >= w - 2) and (y < 2 or y >= h - 2)
            edge = min(x, y, w - 1 - x, h - 1 - y)
            if corner:
                continue
            px[x, y] = INK if edge == 0 else (HOT if flash else BRASS) if edge <= 2 else INK if edge == 3 else NIGHT
    for x in range(3, w - 3):                                   # light catching the top of the bezel
        if not flash:
            px[x, 1] = SAND
    # Speed: three digits, unlit segments stay faintly visible as on an old display.
    text = "   " if speed is None else str(round(speed * 120)).rjust(3)
    for i, ch in enumerate(text):
        x = 46 + i * 17
        seven(px, x, 8, "8", PLUM)
        if ch != " ":
            seven(px, x, 8, ch, CREAM)
    for i, ch in enumerate("km/h"):
        for b, on in enumerate(LETTERS[ch]):
            if on == "1":
                px[101 + i * 4 + b % 3, 26 + b // 3] = SAND
    if speed is None:
        return im
    # Heat bar: sixteen blocks, the last five are the red zone; a flame marks what it measures.
    flame(px, 9, 43, HOT if hot else SAND, SAND if hot else None)
    blocks = 16
    for i in range(blocks):
        x = 22 + i * 7
        zone = i >= blocks - 5
        lit = (i + 0.5) / blocks <= heat
        col = (HOT if zone else ORANGE if i >= 6 else SAND) if lit else PLUM
        for yy in range(42, 54):
            for xx in range(x, x + 6):
                px[xx, yy] = CREAM if lit and not zone and yy == 42 else col
        if zone and not lit:
            for xx in range(x, x + 6):
                px[xx, 42] = px[xx, 43] = HOT                     # red caps show where the danger starts
    return im


def digital_sheet():
    base = Image.open(HERE / "probe" / "frame-2.png").convert("RGBA").resize((640, 360), Image.NEAREST)
    base.alpha_composite(digital(0.62, 0.45), ((640 - 150) // 2, 38))
    game = base.crop((0, 32, 640, 328)).resize((1920, 888), Image.NEAREST)
    states = [("Cool engine", digital(0.3, 0.2)), ("Boosting", digital(0.62, 0.6)),
              ("About to cut out (flashes)", digital(0.87, 0.9, flash=True))]
    sheet = Image.new("RGB", (1920, 888 + 420), (30, 22, 34))
    sheet.paste(game, (0, 0))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=30)
    for i, (name, im) in enumerate(states):
        tile = Image.new("RGBA", (600, 248), NIGHT[:3] + (255,))
        tile.alpha_composite(im.resize((600, 248), Image.NEAREST))
        sheet.paste(tile.convert("RGB"), (30 + i * 630, 888 + 80))
        d.text((30 + i * 630, 888 + 28), name, fill=(246, 232, 184), font=font)
    sheet.save(HERE / "probe" / "dash-digital.png")


def export():
    """The fixed parts of the digital dashboard, with a brass and a red frame."""
    out = HERE.parent / "App" / "Resources" / "Art"
    digital(None, 0).save(out / "dash.png")
    digital(None, 0, flash=True).save(out / "dash-warn.png")


# ---------------------------------------------------------------- B: half-moon night dial

def option_b(im, speed, revs, heat):
    px, draw = im.load(), ImageDraw.Draw(im)
    cx, cy, r = 320, 60, 50
    disc(px, cx, cy, r + 1, INK, top_only=True)
    disc(px, cx, cy, r, BRASS, top_only=True)
    disc(px, cx, cy, r - 2, INK, top_only=True)
    disc(px, cx, cy, r - 3, NIGHT, top_only=True)
    for x in range(cx - r - 1, cx + r + 2):                      # flat lower edge
        px[x, cy + 1] = INK
    # Outer scale: speed.
    for i in range(13):
        t = i / 12
        tick(draw, cx, cy, r - 5, r - (11 if i % 2 == 0 else 8), sweep(t, 180, 180), CREAM if i % 2 == 0 else SAND)
    # Inner arc: revs as lit blocks, the last few are the red zone.
    blocks = 18
    for i in range(blocks):
        t = (i + 0.5) / blocks
        lit = t <= revs
        hot = i >= blocks - 4
        col = (RED if hot else ORANGE) if lit else PLUM
        for d in range(-3, 4):
            deg = sweep(t, 180, 180) + d
            for rr in (r - 19, r - 20, r - 21, r - 22):
                x, y = polar(cx, cy, rr, deg)
                if round(y) <= cy:
                    px[round(x), round(y)] = col
    # Heat: a row of lamps along the flat edge.
    for i in range(8):
        x = cx - 23 + i * 6
        col = (RED if i >= 6 else SAND) if i / 8 < heat else PLUM
        for dx in range(4):
            for dy in range(2):
                px[x + dx, cy - 3 + dy] = col
    text = str(round(speed * 120))
    digits(px, cx - len(text) * 4 + 1, cy - 18, text, CREAM, scale=2)
    # The pointer only crosses the outer scale, so it never covers the number.
    deg = sweep(speed, 180, 180)
    for off in (-1, 0, 1):
        draw.line([polar(cx, cy, r - 16, deg + off), polar(cx, cy, r - 5, deg)], fill=RED if off else CREAM)


# ---------------------------------------------------------------- C: rev strip and big digits

def option_c(im, speed, revs, heat):
    px = im.load()
    blocks, x0, base = 22, 250, 38
    for i in range(blocks):
        t = (i + 0.5) / blocks
        h = 5 + round(17 * (i / (blocks - 1)) ** 1.4)
        lit = t <= revs
        hot = i >= blocks - 5
        col = (RED if hot else SAND if i < 8 else ORANGE) if lit else None
        x = x0 + i * 5
        for dx in range(-1, 5):
            for dy in range(-1, h + 1):
                edge = dx in (-1, 4) or dy in (-1, h)
                y = base - dy
                if edge:
                    px[x + dx, y] = INK
                elif col:
                    px[x + dx, y] = CREAM if dy == h - 1 and not hot else col
                else:
                    px[x + dx, y] = RED if hot and dy == h - 1 else NIGHT
    # Heat lamps under the strip.
    for i in range(blocks):
        x = x0 + i * 5
        col = (RED if i >= blocks - 5 else ORANGE) if (i + 0.5) / blocks < heat else NIGHT
        for dx in range(-1, 5):
            for dy in range(4):
                px[x + dx, base + 3 + dy] = INK if dx in (-1, 4) or dy in (0, 3) else col
    text = str(round(speed * 120))
    digits(px, x0 + blocks * 5 + 6 + (3 - len(text)) * 12, 14, text, CREAM, scale=3, shadow=INK)


OPTIONS = [("A  Twin brass clocks", option_a), ("B  Half-moon night dial", option_b),
           ("C  Rev strip and digits", option_c)]


def main():
    base = Image.open(HERE / "probe" / "frame-2.png").convert("RGBA")
    base = base.resize((640, 360), Image.NEAREST)
    font = ImageFont.load_default(size=28)
    frames, zooms = [], []
    for name, fn in OPTIONS:
        im = base.copy()
        fn(im, 0.62, 0.7, 0.55)
        frames.append((name, im.resize((1280, 720), Image.NEAREST)))
        zooms.append(im.crop((230, 0, 410, 70)).resize((180 * 6, 70 * 6), Image.NEAREST))
    sheet = Image.new("RGB", (1280, len(frames) * 770), (30, 22, 34))
    zoom = Image.new("RGB", (1080, len(frames) * 470), (30, 22, 34))
    d, dz = ImageDraw.Draw(sheet), ImageDraw.Draw(zoom)
    for i, (name, im) in enumerate(frames):
        d.text((12, i * 770 + 8), name, fill=(246, 232, 184), font=font)
        sheet.paste(im, (0, i * 770 + 50))
        dz.text((12, i * 470 + 8), name, fill=(246, 232, 184), font=font)
        zoom.paste(zooms[i], (0, i * 470 + 50))
    sheet.save(HERE / "probe" / "dash-options.png")
    zoom.save(HERE / "probe" / "dash-zoom.png")


if __name__ == "__main__":
    {"export": export, "digital": digital_sheet}.get((sys.argv[1:] or [""])[0], main)()

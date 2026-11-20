#!/usr/bin/env python3
"""Turns art/raw into game-ready Dune dusk art and renders mock frames to judge the whole picture.

    python3 art/compose.py assets   # write processed layers and sprites to App/Resources/Art
    python3 art/compose.py mock     # write art/probe/frame-*.png using the same layout rules as the game

Everything is snapped to one palette taken from the backdrop, and scenery further away is blended
toward the horizon haze colour, so every layer shares colours and light.
"""
import math
import random
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
RAW = HERE / "raw"
OUT = HERE.parent / "App" / "Resources" / "Art"
PROBE = HERE / "probe"

SCENE_W, SCENE_H = 640, 360
PX_PER_M = 27
BACKDROP = "backdrop-6112"
BACKDROP_CROP_TOP = 40          # rows of the 640x400 backdrop hidden above the screen at rest
GROUND_Y = 272                  # screen y (from top) of height 0 at rest
PALETTE_SIZE = 56

# name -> (pieces, parallax, haze, base_y on screen, spacing range in px, seed)
LAYERS = {
    "mid": (["butte-a", "butte-c", "arch", "butte-b", "windpump"], 0.12, 0.34, 266, (200, 460), 23),
    "near": (["cactus-a", "boulders-a", "fence", "cactus-c", "bush", "deadtree", "boulders-b", "cactus-b",
              "tyres", "skull", "flagpole"], 0.4, 0.0, 277, (110, 300), 37),
}
FAR_SCALE = {}                  # every piece is drawn at its native pixel size so pixel density matches
TRACK_PX = 600 * PX_PER_M


BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def load(name):
    return Image.open(RAW / f"{name}.png").convert("RGBA")


def master_palette():
    q = load(BACKDROP).convert("RGB").quantize(PALETTE_SIZE, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    flat = q.getpalette()[:PALETTE_SIZE * 3]
    return [tuple(flat[i:i + 3]) for i in range(0, len(flat), 3)]


def snap(img, palette, haze=0.0, haze_colour=(0, 0, 0)):
    """Hard alpha, optional blend toward the haze colour, then nearest palette colour."""
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    src, dst = img.load(), out.load()
    cache = {}
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = src[x, y]
            if a < 128:
                continue
            if haze:
                r = round(r + (haze_colour[0] - r) * haze)
                g = round(g + (haze_colour[1] - g) * haze)
                b = round(b + (haze_colour[2] - b) * haze)
            key = (r, g, b)
            if key not in cache:
                cache[key] = min(palette, key=lambda p: (p[0] - r) ** 2 + (p[1] - g) ** 2 + (p[2] - b) ** 2)
            dst[x, y] = cache[key] + (255,)
    return out


def trimmed(img):
    """Crop to content, then drop stray rows under the widest part so the piece sits on its base."""
    return img.crop(img.getbbox())


def haze_colour(backdrop):
    """Average colour of the band just above the horizon."""
    band = backdrop.crop((0, 262, backdrop.width, 282)).convert("RGB").resize((1, 1), Image.BOX)
    return band.getpixel((0, 0))


STRIP_WIDTH = {"mid": 2048, "near": 4096}     # strips tile horizontally in the game
FLOOR_ROWS = 40                               # rows of desert floor baked under each strip's base line
def bottom_runs(img):
    """The (first, last) columns of each opaque run on the image's lowest row."""
    y = img.getbbox()[3] - 1
    runs = []
    for x in range(img.width):
        if img.getpixel((x, y))[3] > 0:
            if runs and runs[-1][1] == x - 1:
                runs[-1][1] = x
            else:
                runs.append([x, x])
    return y, runs


def round_wheel_bottoms(img, wheels, trim=2):
    """PixelLab draws the tyres resting on the ground, with a flat bottom two rows deep. Clip the
    corners of the lowest row under each wheel so it closes like its top does. `wheels` comes from
    a riding frame, so a boot planted on the ground is left alone."""
    img = img.copy()
    y, runs = wheels
    for a, b in runs:
        for x in list(range(a, a + trim)) + list(range(b - trim + 1, b + 1)):
            img.putpixel((x, y), (0, 0, 0, 0))
    return img


PLANT = 3                                     # pieces sink this far into their floor


def floor_tones(name, palette, haze_rgb):
    """(top, bottom) colours of the plain a layer stands on."""
    sand = sand_colours(palette)
    haze = LAYERS[name][2]
    def hz(c):
        m = tuple(round(c[i] + (haze_rgb[i] - c[i]) * haze) for i in range(3))
        return min(palette, key=lambda q: sum((q[i] - m[i]) ** 2 for i in range(3)))
    return (hz(sand[2]), hz(sand[3])) if name == "mid" else (hz(sand[3]), hz(sand[4]))


def build_layer(name, palette, haze_rgb):
    pieces, parallax, haze, base_y, (gap_lo, gap_hi), seed = LAYERS[name]
    width = STRIP_WIDTH[name]
    sprites = [snap(trimmed(load(p)), palette, haze, haze_rgb) for p in pieces]
    tall = max(s.height for s in sprites)
    strip = Image.new("RGBA", (width, tall + FLOOR_ROWS), (0, 0, 0, 0))
    top, bottom = floor_tones(name, palette, haze_rgb)
    px = strip.load()
    for y in range(tall - PLANT, tall + FLOOR_ROWS):
        d = y - (tall - PLANT)
        for x in range(width):
            px[x, y] = (top if d + BAYER[y % 4][x % 4] < 22 else bottom) + (255,)
    rng = random.Random(seed)
    x = rng.randint(20, gap_lo)
    last = None
    while True:
        choice = rng.choice([i for i in range(len(sprites)) if i != last])
        s = sprites[choice]
        if x + s.width + gap_lo // 2 > width:
            break
        last = choice
        if rng.random() < 0.5:
            s = s.transpose(Image.FLIP_LEFT_RIGHT)
        strip.alpha_composite(s, (x, tall - s.height))
        x += s.width + rng.randint(gap_lo, gap_hi)
    return strip, parallax, base_y


# ---- ground -------------------------------------------------------------------------------------

def sand_colours(palette):
    """Five sand tones from the palette, light to dark, chosen by closeness to hand-picked targets."""
    targets = [(238, 178, 104), (212, 140, 78), (176, 104, 62), (132, 72, 54), (92, 48, 52)]
    return [min(palette, key=lambda p: sum((p[i] - t[i]) ** 2 for i in range(3))) for t in targets]


def _hash(a, b=0):
    h = (a * 73856093) ^ (b * 19349663) ^ 0x9E3779B9
    h = (h ^ (h >> 13)) * 1274126177
    return (h ^ (h >> 16)) & 0xFFFF


# Sandstone strata: (thickness px, tone) repeating upward from far below the baseline. Uneven
# thicknesses and tones keep it from reading as brickwork.
STRATA = [(11, 3), (5, 2), (14, 3), (4, 4), (9, 2), (7, 3), (16, 2), (5, 4), (12, 3), (8, 2)]
STRATA_TOTAL = sum(t for t, _ in STRATA)


def rock_colour(x, depth, alt, tones):
    """Cut sandstone: strata are level in the world (by altitude `alt` px above the baseline), with a
    lit surface skin that follows the slope."""
    if depth < 2:
        return tones[0]
    if depth < 4:
        return tones[1]
    wobble = ((_hash(x // 24) % 3) - 1) if (x // 12) % 2 else 0      # seams step gently, never straight for long
    a = (alt + wobble + 4096) % STRATA_TOTAL
    for i, (thick, tone) in enumerate(STRATA):
        if a < thick:
            if a == thick - 1:
                return tones[4]                                  # dark seam on top of each stratum
            if a == thick - 2 and thick > 5:
                return tones[max(tone - 1, 1)]                    # lit lip under the seam
            layer_id = (alt + wobble + 4096) // STRATA_TOTAL * len(STRATA) + i
            crack_gap = 71 + _hash(layer_id) % 97                 # cracks are sparse and staggered per stratum
            if (x + _hash(layer_id, 7) % crack_gap) % crack_gap == 0 and thick > 6 and _hash(x, layer_id) % 3:
                return tones[4]
            if _hash(x, alt) < 1800:
                return tones[min(tone + 1, 4)]                    # pitting
            return tones[tone]
        a -= thick
    return tones[3]


ROCK_TONES = None


def rock_tones(palette):
    """Five red-sandstone tones from the palette, light to dark: redder and darker than the sand."""
    targets = [(240, 160, 96), (196, 100, 66), (150, 68, 56), (108, 50, 52), (64, 34, 46)]
    return [min(palette, key=lambda p: sum((p[i] - t[i]) ** 2 for i in range(3))) for t in targets]


def ground_colour(x, depth, tones, rock=False, alt=0):
    if rock:
        return rock_colour(x, depth, alt, ROCK_TONES or tones)
    """Colour of the ground `depth` pixels under the surface at world pixel column x."""
    if depth < 2:
        return tones[0]
    if depth < 5:
        return tones[1] if not rock else tones[2]
    # bands get darker with depth; ordered dither softens each boundary
    edges = [5, 26, 70, 150]
    band = 1
    for i, e in enumerate(edges):
        if depth + (BAYER[depth % 4][x % 4] - 8) * (0.5 + i * 0.6) > e:
            band = min(i + 1, 4)
    h = (x * 73856093 ^ depth * 19349663) & 0xFFFF
    if h < 380 and depth > 6:
        band = min(band + 1, 4)              # dark pebble
    elif h < 560 and depth > 6:
        band = max(band - 1, 1)              # light grain
    return tones[band]


# ---- mock ---------------------------------------------------------------------------------------

def demo_height(xm):
    """A stretch of track for the mock, in metres: small hill, big hill, rock ramp."""
    def cos_hill(x0, w, h):
        t = (xm - x0) / w
        return h * (1 - math.cos(2 * math.pi * t)) / 2 if 0 <= t <= 1 else 0
    h = cos_hill(14, 8, 1.5) + cos_hill(30, 16, 3.5)
    t = (xm - 54) / 12
    if 0 <= t <= 1:
        h += 2.5 * (t / 0.85) if t < 0.85 else 2.5 * (1 - (t - 0.85) / 0.15)
    return h


def is_rock(xm):
    return 54 <= xm <= 66


def render_frame(cam_m, palette, layers, backdrop, tones, bike=None, cam_up=0, floors=None):
    frame = Image.new("RGBA", (SCENE_W, SCENE_H), (0, 0, 0, 255))
    top = BACKDROP_CROP_TOP - min(round(cam_up * 0.1), BACKDROP_CROP_TOP)
    frame.alpha_composite(backdrop.crop((0, top, SCENE_W, top + SCENE_H)))
    cam_px = round(cam_m * PX_PER_M)
    for name in ("mid", "near"):
        strip, parallax, base_y = layers[name]
        off = round(cam_px * parallax) % strip.width
        y = base_y - (strip.height - FLOOR_ROWS) + round(cam_up * (0.15 + parallax))
        for k in (0, 1):
            frame.alpha_composite(strip, (k * strip.width - off, y))
        if floors and y + strip.height < SCENE_H:
            frame.paste(floors[name][1] + (255,), (0, y + strip.height, SCENE_W, SCENE_H))
    px = frame.load()
    left_m = cam_m - SCENE_W * 0.3 / PX_PER_M
    for sx in range(SCENE_W):
        wx = round(left_m * PX_PER_M) + sx
        xm = wx / PX_PER_M
        top = GROUND_Y - round(demo_height(xm) * PX_PER_M) + cam_up
        for sy in range(max(top, 0), SCENE_H):
            px[sx, sy] = ground_colour(wx, sy - top, tones, is_rock(xm), GROUND_Y + cam_up - sy) + (255,)
    if bike is not None:
        bx = round(SCENE_W * 0.3)
        by = GROUND_Y - round(demo_height(cam_m) * PX_PER_M) - (cam_up and 0)
        frame.alpha_composite(bike, (bx - bike.width // 2, by - bike.height + 2))
    return frame


def prepared():
    palette = master_palette()
    backdrop = snap(load(BACKDROP), palette)
    haze_rgb = haze_colour(backdrop)
    layers = {n: build_layer(n, palette, haze_rgb) for n in LAYERS}
    return palette, backdrop, layers, sand_colours(palette)


def mock():
    global ROCK_TONES
    palette, backdrop, layers, tones = prepared()
    ROCK_TONES = rock_tones(palette)
    haze_rgb = haze_colour(backdrop)
    floors = {n: floor_tones(n, palette, haze_rgb) for n in LAYERS}
    bike = trimmed(load("probe-rider-64"))
    PROBE.mkdir(exist_ok=True)
    for i, (cam, up) in enumerate(((6, 0), (24, 0), (38, 60), (60, 0), (80, 140))):
        f = render_frame(cam, palette, layers, backdrop, tones, bike, up, floors)
        f.resize((SCENE_W * 2, SCENE_H * 2), Image.NEAREST).save(PROBE / f"frame-{i}.png")


def assets():
    import json
    palette, backdrop, layers, tones = prepared()
    haze_rgb = haze_colour(backdrop)
    OUT.mkdir(parents=True, exist_ok=True)
    backdrop.convert("RGB").save(OUT / "backdrop.png")
    for n, (strip, _, _) in layers.items():
        strip.save(OUT / f"layer-{n}.png")
    # Ride loop: PixelLab animated the approved rider; every frame keeps one crop so they line up.
    ride = [Image.open(f).convert("RGBA") for f in sorted((RAW / "ride").glob("ride-*.png"))]
    boxes = [f.getbbox() for f in ride]
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    wheels = bottom_runs(ride[0])
    for i, f in enumerate(ride):
        round_wheel_bottoms(f, wheels).crop(box).save(OUT / f"bike-{i}.png")
    # Stopping: the rider takes the near foot off the peg and plants it. Frame 0 repeats the riding
    # pose, so it is left out.
    stand = [Image.open(f).convert("RGBA") for f in sorted((RAW / "stand").glob("stand-*.png"))][1:]
    for i, f in enumerate(stand):
        round_wheel_bottoms(f, wheels).crop(box).save(OUT / f"stand-{i}.png")
    (OUT / "bike.png").unlink(missing_ok=True)
    if (RAW / "gate.png").exists():
        snap(trimmed(load("gate")), palette).save(OUT / "gate.png")
    info = {
        "sand": tones, "rock": rock_tones(palette), "sky": backdrop.convert("RGB").getpixel((0, 0)),
        "sun": max(palette, key=sum), "rideFrames": len(ride), "standFrames": len(stand),
        "layers": {n: {"parallax": LAYERS[n][1], "baseAboveBottom": SCENE_H - LAYERS[n][3],
                       "floorRows": FLOOR_ROWS, "floor": floor_tones(n, palette, haze_rgb)[1]} for n in LAYERS},
    }
    (OUT / "art.json").write_text(json.dumps(info, indent=1))
    print("wrote", sorted(p.name for p in OUT.iterdir()))


if __name__ == "__main__":
    {"mock": mock, "assets": assets}[sys.argv[1] if len(sys.argv) > 1 else "mock"]()

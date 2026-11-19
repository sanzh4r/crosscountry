#!/usr/bin/env python3
"""Generates the Dune dusk raw art with PixelLab. Skips anything already in art/raw.

    python3 art/generate.py            # everything missing
    python3 art/generate.py bike sky   # only these labels
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import pixellab as pl  # noqa: E402

RAW = Path(__file__).resolve().parent / "raw"
STYLE = "16-bit pixel art, warm desert dusk light, limited palette of deep purple, magenta, burnt orange and sand"


def pixen(w, h, text, seed, transparent=False):
    body = {"description": f"{text}, {STYLE}", "image_size": {"width": w, "height": h}, "view": "side",
            "detail": "highly detailed", "seed": seed}
    if transparent:
        body["no_background"] = True
    return "/create-image-pixen", body


ASSETS = {
    "bike": pixen(64, 64, "game sprite of an off-road motocross rider on a dirt bike, strict side view facing right, "
                  "rider crouched in racing stance, teal and cream racing suit, teal helmet with dark visor, "
                  "knobby tyres, orange bike frame, both wheels fully visible on the ground line, "
                  "clean readable silhouette", 5101, True),
    "crash": pixen(64, 64, "game sprite of a motocross rider in teal and cream suit and teal helmet tumbling "
                   "head over heels in the air beside his fallen orange dirt bike, comic crash pose, dust, "
                   "side view", 5102, True),
    "sky": pixen(640, 360, "side-scrolling game sky backdrop only, deep purple sky with magenta and orange cloud "
                 "bands, huge low setting sun sitting on a hazy flat horizon in the lower third, glowing haze below "
                 "the horizon, no mountains, no ground objects, no characters, no text", 5103),
    "mesas": pixen(512, 128, "long horizontal strip of distant flat-topped desert mesas and rock buttes in hazy "
                   "dusty purple-brown silhouette with soft orange rim light, base of the strip is a straight line "
                   "at the bottom edge, parallax background layer for a side-scrolling game", 5104, True),
    "rocks": pixen(512, 128, "long horizontal strip of dark foreground desert boulders, saguaro cacti, dry bushes "
                   "and a broken fence post, deep maroon and dark purple silhouettes with orange rim light, base of "
                   "the strip is a straight line at the bottom edge, parallax layer for a side-scrolling game",
                   5105, True),
    "sand": pixen(64, 64, "seamless tileable texture of packed desert sand and small pebbles seen in cross-section, "
                  "orange-brown with darker specks, flat even pattern, no horizon, no objects", 5106),
    "rock": pixen(64, 64, "seamless tileable texture of layered red sandstone rock strata in cross-section, "
                  "cracks and bands, flat even pattern, no horizon, no objects", 5107),
    "cactus": pixen(64, 96, "game prop, a tall saguaro cactus with two arms, standing on the bottom edge", 5108, True),
    "skull": pixen(32, 32, "game prop, a sun-bleached cattle skull with horns lying on sand", 5109, True),
    "bush": pixen(48, 32, "game prop, a dry tumbleweed desert bush", 5110, True),
    "barrel": pixen(32, 32, "game prop, a rusty dented oil barrel standing upright", 5111, True),
    "gate": pixen(128, 128, "game prop, a motocross finish line arch made of two wooden poles with a black and "
                  "white chequered banner stretched between them at the top, bunting flags, no text, no letters, "
                  "poles standing on the bottom edge", 5112, True),
}


def main():
    wanted = sys.argv[1:] or list(ASSETS)
    RAW.mkdir(parents=True, exist_ok=True)
    for label in wanted:
        if (RAW / f"{label}.png").exists():
            print(label, "exists")
            continue
        endpoint, body = ASSETS[label]
        try:
            print(label, pl.generate(endpoint, body, RAW, label, expect=4))
        except pl.PixelLabError as e:
            print(label, "FAILED", str(e)[:400])
    print(f"booked {pl.spent()} of {pl.CAP}")


if __name__ == "__main__":
    main()

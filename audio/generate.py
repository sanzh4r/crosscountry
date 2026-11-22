#!/usr/bin/env python3
"""Generates the raw game sounds with ElevenLabs. Skips anything already in audio/raw.

    python3 audio/generate.py              # everything missing
    python3 audio/generate.py land crash   # only these labels
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import elevenlabs as el  # noqa: E402

RAW = Path(__file__).resolve().parent / "raw"
STYLE = "retro 16-bit console video game sound effect, clean, no voice, no music"

# label: (text, seconds, loop)
SOUNDS = {
    # Chosen from three candidates (audio/raw/candidates) as the steadiest; made with influence 0.8.
    "engine": ("continuous motorcycle engine drone held at one constant RPM, perfectly steady even hum and buzz, "
               "no revving, no pulses, no changes at all", 3.0, True),
    "boost": ("steady roaring jet afterburner flame with a bright hiss, constant intensity, " + STYLE, 2.5, True),
    "land": ("one short heavy thud of a motorbike landing on packed sand, soft suspension clunk, " + STYLE,
             0.6, False),
    "crash": ("motorbike crash, metal clatter and tumbling thuds ending in a dull thump, " + STYLE, 1.4, False),
    "stall": ("overheated engine sputters, coughs and dies, followed by a hiss of steam, " + STYLE, 1.6, False),
    "warn": ("two quick high-pitched alarm beeps, urgent dashboard warning, " + STYLE, 0.5, False),
    "pad": ("fast rising whoosh of a speed boost power-up, bright and punchy, " + STYLE, 0.8, False),
    "mud": ("wet muddy squelch and splash as a tyre ploughs through thick mud, " + STYLE, 0.8, False),
    "lane": ("one very short soft swish, quick sideways movement, " + STYLE, 0.5, False),
    "bump": ("one short dull rubbery knock of two tyres bumping, " + STYLE, 0.5, False),
}

MUSIC = {
    "theme": ("Instrumental 16-bit console chiptune racing theme for a desert dirt bike game at dusk. Driving "
              "bassline, punchy drums, twangy surf-rock style lead melody on square and saw waves, upbeat and "
              "adventurous, around 150 bpm. Starts at full energy with no intro and keeps the same energy to the "
              "end with no fade-out, so it can loop.", 64),
    # Played when the player finishes second or later.
    "finish": ("Instrumental victory sting for an off-road motocross racing game. Triumphant overdriven rock guitar "
               "power chords with a soaring lead guitar melody, pounding live drums and bass, a motorbike engine rev "
               "at the very start, building to one big final chord with a cymbal crash. Dusty desert rock feel, "
               "heroic and celebratory. Ends decisively on the final chord, no fade.", 10),
    # Played when the player wins.
    "win": ("Instrumental victory fanfare for a desert dirt bike racing game. Bold triumphant brass melody over "
            "driving rock drums and gritty electric guitar, a hint of twangy western surf guitar, heroic and "
            "celebratory, modern arcade game production. Ends decisively on a big final hit, no fade.", 10),
}


def main():
    wanted = sys.argv[1:] or list(SOUNDS) + list(MUSIC)
    start_used, start_booked = el.used(), el.spent()
    for label in wanted:
        if (RAW / f"{label}.mp3").exists():
            print(label, "exists")
            continue
        try:
            if label in MUSIC:
                prompt, seconds = MUSIC[label]
                print(label, *el.music(label, prompt, seconds, RAW))
            else:
                text, seconds, loop = SOUNDS[label]
                print(label, *el.sound(label, text, seconds, RAW, loop=loop))
        except el.ElevenLabsError as e:
            print(label, "FAILED", str(e)[:500])
    late = el.settle(start_used, start_booked)
    print(f"late billing {late}; booked {el.spent()} of {el.CAP} credits")


if __name__ == "__main__":
    main()

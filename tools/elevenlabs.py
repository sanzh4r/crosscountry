#!/usr/bin/env python3
"""Small ElevenLabs client for the dune bike game's sound.

The key is read from $ELEVENLABS_API_KEY or ~/.config/elevenlabs/api_key, sent only to
api.elevenlabs.io, and never printed or written anywhere.

Budget: every paid call is booked in audio/ledger.jsonl with the credits it used, measured as the
drop in the account's balance around the call. A call is refused when the booked total has
reached CAP.

    import elevenlabs as el
    el.sound("land", "short thud", seconds=0.6, out_dir=RAW)
    el.music("theme", "chiptune desert rock", seconds=60, out_dir=RAW)
    el.spent()
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.elevenlabs.io/v1"
REPO = Path(__file__).resolve().parent.parent
LEDGER = REPO / "audio" / "ledger.jsonl"
CAP = 15000


class ElevenLabsError(RuntimeError):
    pass


def _key():
    key = os.environ.get("ELEVENLABS_API_KEY")
    path = Path.home() / ".config" / "elevenlabs" / "api_key"
    if not key and path.exists():
        key = path.read_text().strip()
    if not key:
        sys.exit("No ElevenLabs key: set ELEVENLABS_API_KEY or create ~/.config/elevenlabs/api_key.")
    return key


def _request(method, path, body=None, timeout=600):
    """One request, never retried: a failed POST may still have been billed."""
    req = urllib.request.Request(
        API + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"xi-api-key": _key(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        raise ElevenLabsError(f"ElevenLabs {method} {path} -> HTTP {e.code}: {e.read().decode(errors='replace')[:600]}")
    except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
        raise ElevenLabsError(f"ElevenLabs {method} {path} -> {e}")


def used():
    """Credits used on the account in this billing period. Free to ask, so it is retried."""
    for attempt in range(6):
        try:
            return int(json.loads(_request("GET", "/user/subscription"))["character_count"])
        except ElevenLabsError as e:
            if "HTTP 429" not in str(e) or attempt == 5:
                raise
            time.sleep(10 * (attempt + 1))


def rows():
    if not LEDGER.exists():
        return []
    return [json.loads(line) for line in LEDGER.read_text().splitlines() if line.strip()]


def spent():
    return sum(int(r["cost"]) for r in rows())


def _paid(label, path, body, out_dir):
    if spent() >= CAP:
        raise ElevenLabsError(f"budget: {spent()} credits booked, cap is {CAP}")
    before = used()
    failed = None
    try:
        data = _request("POST", path, body)
    except ElevenLabsError as e:
        failed, data = str(e), None
    # The balance can lag a few seconds behind the call; `settle` books whatever shows up later.
    time.sleep(4)
    cost = max(used() - before, 0)
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    with LEDGER.open("a") as f:
        f.write(json.dumps({"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "label": label, "endpoint": path,
                            "cost": cost, "failed": bool(failed), "body": body}) + "\n")
    if failed:
        raise ElevenLabsError(failed)
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    target = out / f"{label}.mp3"
    target.write_bytes(data)
    return target, cost


def settle(start_used, start_booked):
    """Books credits that left the account during a batch but that no call's own row caught because
    the balance lagged. Takes the `used()` and `spent()` readings from before the batch."""
    time.sleep(15)
    missing = (used() - start_used) - (spent() - start_booked)
    if missing > 0:
        with LEDGER.open("a") as f:
            f.write(json.dumps({"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "label": "late billing",
                                "endpoint": "", "cost": missing, "failed": False, "body": {}}) + "\n")
    return max(missing, 0)


def sound(label, text, seconds, out_dir, loop=False, influence=0.5):
    body = {"text": text, "duration_seconds": seconds, "prompt_influence": influence,
            "model_id": "eleven_text_to_sound_v2"}
    if loop:
        body["loop"] = True
    return _paid(label, "/sound-generation?output_format=mp3_44100_128", body, out_dir)


def music(label, prompt, seconds, out_dir):
    body = {"prompt": prompt, "music_length_ms": int(seconds * 1000), "model_id": "music_v1",
            "force_instrumental": True}
    return _paid(label, "/music?output_format=mp3_44100_128", body, out_dir)


if __name__ == "__main__":
    print(f"booked {spent()} of {CAP} credits ({len(rows())} calls)")

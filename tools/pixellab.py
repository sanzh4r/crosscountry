#!/usr/bin/env python3
"""Small PixelLab REST v2 client for the dune bike game's art.

The key is read from $PIXELLAB_API_KEY or ~/.config/pixellab/api_key, sent only to
api.pixellab.ai, and never printed or written anywhere.

Budget: the owner's limit for this game is 5000 generations. Every paid call is booked in
art/ledger.jsonl from what PixelLab says it billed (or EXPECT when it says nothing), and a call
is refused when the booked total plus its expected cost would pass the cap.

Use as a library:
    import pixellab as pl
    paths = pl.generate("/create-image-pixen", body, out_dir, label="bike-probe-1", expect=2)
    pl.spent()
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.pixellab.ai/v2"
REPO = Path(__file__).resolve().parent.parent
LEDGER = REPO / "art" / "ledger.jsonl"
CAP = 5000.0


class PixelLabError(RuntimeError):
    def __init__(self, msg, status=None):
        super().__init__(msg)
        self.status = status


def _key():
    key = os.environ.get("PIXELLAB_API_KEY")
    path = Path.home() / ".config" / "pixellab" / "api_key"
    if not key and path.exists():
        key = path.read_text().strip()
    if not key:
        sys.exit("No PixelLab key: set PIXELLAB_API_KEY or create ~/.config/pixellab/api_key.")
    return key


def call(method, path, body=None, timeout=300):
    """One authenticated request. A POST is retried only on 429: any other failure may have
    been accepted and billed, and a retry would pay twice."""
    req = urllib.request.Request(
        API + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {_key()}", "Content-Type": "application/json"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")[:800]
            if (e.code == 429 or (method == "GET" and e.code in (502, 503, 504))) and attempt < 3:
                time.sleep(10 * (attempt + 1))
                continue
            raise PixelLabError(f"PixelLab {method} {path} -> HTTP {e.code}: {msg}", e.code)
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if method == "GET" and attempt < 3:
                time.sleep(5)
                continue
            raise PixelLabError(f"PixelLab {method} {path} -> {e}")


def balance():
    return float(call("GET", "/balance")["subscription"]["generations"])


def b64img(path):
    return {"type": "base64", "base64": base64.b64encode(Path(path).read_bytes()).decode(), "format": "png"}


def rows():
    if not LEDGER.exists():
        return []
    return [json.loads(line) for line in LEDGER.read_text().splitlines() if line.strip()]


def spent():
    return sum(float(r["cost"]) for r in rows())


def _billed(obj):
    if not isinstance(obj, dict):
        return None
    last = obj.get("last_response") if isinstance(obj.get("last_response"), dict) else {}
    for u in (obj.get("usage"), last.get("usage"), last.get("billing_usage")):
        if isinstance(u, dict) and u.get("generations") is not None:
            return float(u["generations"])
    return None


def _images(obj):
    found = []

    def walk(o, name):
        if isinstance(o, dict):
            if isinstance(o.get("base64"), str) and len(o["base64"]) > 64:
                found.append((name or "image", o["base64"]))
                return
            for k, v in o.items():
                walk(v, f"{name}_{k}" if name else k)
        elif isinstance(o, list):
            for i, v in enumerate(o):
                walk(v, f"{name}-{i}")
    walk(obj, "")
    return found


def wait(job_id, every=6, timeout=900):
    t0 = time.time()
    while True:
        job = call("GET", f"/background-jobs/{job_id}")
        if job.get("status") in ("completed", "failed", "cancelled"):
            return job
        if time.time() - t0 > timeout:
            raise PixelLabError(f"job {job_id} still {job.get('status')} after {timeout}s")
        time.sleep(every)


def generate(endpoint, body, out_dir, label, expect):
    """Run one paid call, save its images as <out_dir>/<label>[-n].png, book it, return paths."""
    if spent() + expect > CAP:
        raise PixelLabError(f"budget: {spent()} booked + {expect} expected would pass the cap of {CAP}")
    res = call("POST", endpoint, body)
    billed = _billed(res)
    job_id = res.get("background_job_id")
    if job_id:
        job = wait(job_id)
        if job.get("status") != "completed":
            _book(label, endpoint, billed, expect, job_id, body, failed=True)
            raise PixelLabError(f"job {job_id} {job.get('status')}: {str(job)[:400]}")
        billed = _billed(job) if _billed(job) is not None else billed
        res = job
    found = _images(res)
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    paths = []
    for i, (_, data) in enumerate(found):
        if data.startswith("data:"):
            data = data.split(",", 1)[1]
        p = out / (f"{label}.png" if len(found) == 1 else f"{label}-{i}.png")
        p.write_bytes(base64.b64decode(data))
        paths.append(str(p))
    _book(label, endpoint, billed, expect, job_id, body)
    return paths


def _book(label, endpoint, billed, expect, job_id, body, failed=False):
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    slim = {k: v for k, v in body.items() if not isinstance(v, (dict, list)) or k == "image_size"}
    row = {"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "label": label, "endpoint": endpoint,
           "cost": billed if billed is not None else expect, "billed": billed, "job": job_id,
           "failed": failed, "body": slim}
    with LEDGER.open("a") as f:
        f.write(json.dumps(row) + "\n")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "spent"
    if cmd == "balance":
        print(balance())
    else:
        print(f"booked {spent()} of {CAP} ({len(rows())} calls)")

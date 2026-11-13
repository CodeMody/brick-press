"""Repaint the drop-in background set as five DISTINCT paper stocks (the shipped look).

Each sheet is deliberately its own paper — laid cream with wire lines, dust-flecked
newsprint, warm kraft, mottled vellum, manila with a sheen — because BRICK PRESS
rotates them automatically, one per level (the old B-key cycle is retired).
Seeds are pinned per stock index, so re-running repaints byte-identical sheets.
Run with the bundled runtime Python (numpy + Pillow):
    python tools/paint_bgs.py
"""
import os
import numpy as np
from PIL import Image

W, H = 1600, 1000
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
U, V = xx / W, yy / H

BASES = ["#f5ecd9", "#eee8dc", "#e3c79b", "#f3eee2", "#efdfae"]
NAMES = ["bg1.png laid cream", "bg2.png newsprint", "bg3.png kraft", "bg4.png vellum", "bg5.png manila"]


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], np.float32)


def flat(h):
    return np.tile(hexrgb(h), (H, W, 1)).copy()


def glow(img, cx, cy, rx, ry, color, amp):
    d = ((U - cx) / rx) ** 2 + ((V - cy) / ry) ** 2
    img += (np.exp(-d) * amp)[..., None] * (np.array(color, np.float32) / 255.0)
    return img


def vignette(img, amp=0.05):
    d = ((U - 0.5) / 0.72) ** 2 + ((V - 0.54) / 0.68) ** 2
    k = (1.0 - amp * np.clip(d - 0.32, 0.0, None) ** 1.2).astype(np.float32)
    return img * k[..., None]


def grain(img, amt, rng):
    return img + rng.normal(0, amt, (H, W, 1)).astype(np.float32)


def specks(img, n, color, lo, hi, mul, rng, size_p=0.18):
    """Fine dark fibers composited into the numpy buffer (subtractive-ish, like print dust)."""
    for _ in range(n):
        x, y = int(rng.uniform(0, W)), int(rng.uniform(0, H))
        b = rng.uniform(lo, hi)
        r = 2 if rng.random() < size_p else 1
        img[y:y + r, x:x + r] += np.array(color, np.float32) * (b / 255.0) * mul
    return img


def laid(img, rng):
    """Laid paper: fine horizontal wire lines, a heavier vertical chain line every so often."""
    img[::9, :, :] *= 0.988
    img[:, ::64, :] *= 0.978
    return img


def blotches(img, n, rng):
    """Vellum cloud: soft light glows crossed with soft warm shade patches."""
    for _ in range(n):
        img = glow(img, rng.uniform(0.1, 0.9), rng.uniform(0.1, 0.9), rng.uniform(0.3, 0.65),
                   rng.uniform(0.25, 0.5), (255, 252, 240), rng.uniform(5, 10))
        img = glow(img, rng.uniform(0.1, 0.9), rng.uniform(0.1, 0.9), rng.uniform(0.25, 0.55),
                   rng.uniform(0.2, 0.45), (120, 105, 85), rng.uniform(3, 7))
    return img


def streaks(img, rng, n):
    """Kraft paper long fibers: a few wide, soft bands — random enough to never read as corduroy."""
    for _ in range(n):
        img = glow(img, rng.uniform(0, 1), rng.uniform(0.05, 0.95), 2.2, rng.uniform(0.02, 0.05),
                   (255, 248, 228), rng.uniform(3, 7))
        img = glow(img, rng.uniform(0, 1), rng.uniform(0.05, 0.95), 2.4, rng.uniform(0.016, 0.04),
                   (120, 95, 60), rng.uniform(2, 4))
    return img


def sheen(img, rng):
    """Manila folder: a broad diagonal lit corner over the yellowed stock."""
    d = (((U * 0.9 + V * 0.55) - 0.35) / 0.5) ** 2
    img += (np.exp(-d) * 9.0)[..., None] * (np.array([255, 250, 225], np.float32) / 255.0)
    return img


def paper_bg(i, rng):
    img = flat(BASES[i])
    if i == 0:   # laid cream — wire lines plus a soft lift up top
        img = glow(img, 0.5, 0.28, 0.8, 0.5, (255, 250, 235), 8)
        img = laid(img, rng)
        img = specks(img, 420, (90, 80, 65), 30, 90, 0.10, rng)
        return vignette(grain(img, 2.0, rng), 0.05)
    if i == 1:   # newsprint — cool light grey, dense print dust, nervous grain
        img = glow(img, 0.5, 0.35, 0.9, 0.55, (255, 253, 245), 6)
        img = specks(img, 1500, (85, 78, 68), 25, 85, 0.11, rng, size_p=0.10)
        return vignette(grain(img, 3.1, rng), 0.05)
    if i == 2:   # kraft — deeper tan with long mill fibers, a touch more edge darkening
        img = streaks(img, rng, 16)
        img += rng.normal(0, 1.4, (H, 1, 1)).astype(np.float32) * np.array([1, 1, 0.8], np.float32)   # per-row drift: bands become uneven fibers, never corduroy
        img = specks(img, 520, (80, 62, 42), 30, 95, 0.12, rng)
        return vignette(grain(img, 2.4, rng), 0.06)
    if i == 3:   # vellum — near-white ivory with soft cloudy mottling
        img = blotches(img, 4, rng)
        img = specks(img, 260, (105, 95, 80), 25, 70, 0.08, rng)
        return vignette(grain(img, 1.6, rng), 0.05)
    # manila — yellowed folder stock with a broad lit corner and quiet specks
    img = sheen(img, rng)
    img = specks(img, 380, (110, 92, 55), 28, 80, 0.10, rng)
    return vignette(grain(img, 2.0, rng), 0.05)


def save(img, name):
    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backgrounds", name)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").save(out, optimize=True)
    print(name, os.path.getsize(out) // 1024, "KB")


for i in range(5):
    save(paper_bg(i, np.random.default_rng(3000 + i)), NAMES[i].split()[0])
    print("  ^", NAMES[i])

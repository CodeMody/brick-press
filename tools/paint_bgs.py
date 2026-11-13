"""Repaint the drop-in background set as pressed-paper stocks (the shipped risograph look).

Five cream/kraft stocks — soft cloud blotches, fine dark fibers, paper grain, gentle
vignette. These replaced the old navy night skies when the game became BRICK PRESS
(pressed-paper redesign; no starfields anywhere). Seeds are pinned per stock index,
so re-running repaints byte-identical sheets.
Run with the bundled runtime Python (numpy + Pillow):
    python tools/paint_bgs.py
"""
import os
import numpy as np
from PIL import Image

W, H = 1600, 1000
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
U, V = xx / W, yy / H

BASES = ["#f4ead7", "#efe3cc", "#ead9ba", "#e9e2d2", "#f1e2cc"]  # 5 stocks: cream → kraft


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], np.float32)


def flat(h):
    return np.tile(hexrgb(h), (H, W, 1)).copy()


def glow(img, cx, cy, rx, ry, color, amp):
    d = ((U - cx) / rx) ** 2 + ((V - cy) / ry) ** 2
    img += (np.exp(-d) * amp)[..., None] * (np.array(color, np.float32) / 255.0)
    return img


def vignette(img, amp=0.10):
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


def paper_bg(i, rng):
    img = flat(BASES[i])
    for _ in range(3):
        img = glow(img, rng.uniform(0.2, 0.8), rng.uniform(0.2, 0.8), rng.uniform(0.25, 0.5),
                   rng.uniform(0.2, 0.4), (255, 250, 235), rng.uniform(6, 14))
    img = specks(img, 420, (90, 80, 65), 30, 90, 0.10, rng)  # paper fibers
    return vignette(grain(img, 2.2, rng), 0.10)


def save(img, name):
    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backgrounds", name)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").save(out, optimize=True)
    print(name, os.path.getsize(out) // 1024, "KB")


for i in range(5):
    save(paper_bg(i, np.random.default_rng(3000 + i)), f"bg{i + 1}.png")

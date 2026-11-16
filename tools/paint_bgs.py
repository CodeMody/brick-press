"""Paint the all-new background set: eight soft, eye-friendly sheets — no brown, tan or kraft.

Everything stays light enough for the dark earth-ink bricks and HUD text to read cleanly.
Each sheet is built from a pale base plus gentle radial washes, a whisper of grain and a
soft vignette; a couple add a faint weave or grid. Seeds are pinned per sheet index, so
re-running repaints byte-identical files. Run with numpy + Pillow:
    python tools/paint_bgs.py
"""
import os
import numpy as np
from PIL import Image

W, H = 1600, 1000
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
U, V = xx / W, yy / H

BASES = ["#e8eef2", "#e3f0ec", "#ede9f4", "#f7eaee", "#f1f1ee", "#e9f0e7", "#e7eef6", "#f4f2ec"]
NAMES = ["bg1.png morning mist", "bg2.png sea glass", "bg3.png soft lilac", "bg4.png blush",
         "bg5.png pearl", "bg6.png pale sage", "bg7.png powder blue grid", "bg8.png cool ivory"]


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], np.float32)


def flat(h):
    return np.tile(hexrgb(h), (H, W, 1)).copy()


def glow(img, cx, cy, rx, ry, color, amp):
    d = ((U - cx) / rx) ** 2 + ((V - cy) / ry) ** 2
    img += (np.exp(-d) * amp)[..., None] * (np.array(color, np.float32) / 255.0)
    return img


def vignette(img, amp=0.04):
    d = ((U - 0.5) / 0.74) ** 2 + ((V - 0.52) / 0.70) ** 2
    k = (1.0 - amp * np.clip(d - 0.30, 0.0, None) ** 1.2).astype(np.float32)
    return img * k[..., None]


def grain(img, amt, rng):
    return img + rng.normal(0, amt, (H, W, 1)).astype(np.float32)


def specks(img, n, color, lo, hi, mul, rng, size_p=0.14):
    """A few fine, soft flecks — print dust rather than noise."""
    for _ in range(n):
        x, y = int(rng.uniform(0, W)), int(rng.uniform(0, H))
        b = rng.uniform(lo, hi)
        r = 2 if rng.random() < size_p else 1
        img[y:y + r, x:x + r] += np.array(color, np.float32) * (b / 255.0) * mul
    return img


def wash(img, rng, n, light, shade, amp):
    """Slow cloud-like washes: a soft light bloom crossed with an even softer cool shade."""
    for _ in range(n):
        img = glow(img, rng.uniform(0.08, 0.92), rng.uniform(0.08, 0.92),
                   rng.uniform(0.30, 0.70), rng.uniform(0.22, 0.52), light, rng.uniform(7, 13) * amp)
        img = glow(img, rng.uniform(0.08, 0.92), rng.uniform(0.08, 0.92),
                   rng.uniform(0.28, 0.62), rng.uniform(0.20, 0.45), shade, rng.uniform(4, 8) * amp)
    return img


def weave(img):
    """Pale sage: a barely-there linen weave."""
    img[::7, :, :] *= 0.994
    img[:, ::7, :] *= 0.993
    return img


def grid(img):
    """Powder blue: quiet graph-paper squares, a touch stronger every fifth line."""
    img[::48, :, :] *= 0.976
    img[:, ::48, :] *= 0.976
    img[::240, :, :] *= 0.958
    img[:, ::240, :] *= 0.958
    return img


def sheen(img):
    """Pearl / ivory: a broad diagonal sheen, very low contrast."""
    d = (((U * 0.85 + V * 0.5) - 0.42) / 0.55) ** 2
    img += (np.exp(-d) * 6.0)[..., None] * (np.array([255, 255, 252], np.float32) / 255.0)
    return img


def paper_bg(i, rng):
    img = flat(BASES[i])
    if i == 0:   # morning mist — cool blue-grey, soft white light up top, grey-blue wisps
        img = glow(img, 0.42, 0.22, 0.95, 0.65, (255, 255, 255), 9)
        img = wash(img, rng, 3, (250, 253, 255), (150, 172, 188), 1.0)
        img = specks(img, 160, (140, 158, 172), 20, 60, 0.08, rng)
        return vignette(grain(img, 1.3, rng), 0.045)
    if i == 1:   # sea glass — pale aqua with a gentle turquoise bloom
        img = glow(img, 0.55, 0.34, 0.9, 0.6, (250, 255, 252), 8)
        img = wash(img, rng, 3, (240, 255, 250), (130, 185, 175), 1.0)
        img = specks(img, 180, (120, 175, 165), 20, 60, 0.09, rng)
        return vignette(grain(img, 1.5, rng), 0.045)
    if i == 2:   # soft lilac — pale violet, cloudier toward one corner
        img = glow(img, 0.68, 0.28, 0.85, 0.6, (253, 250, 255), 9)
        img = wash(img, rng, 4, (250, 246, 255), (165, 150, 195), 1.0)
        img = specks(img, 140, (155, 145, 180), 20, 55, 0.07, rng)
        return vignette(grain(img, 1.4, rng), 0.04)
    if i == 3:   # blush — pale pink with a warm coral lift (not brown)
        img = glow(img, 0.32, 0.26, 0.9, 0.62, (255, 250, 250), 9)
        img = wash(img, rng, 3, (255, 246, 248), (205, 155, 170), 1.0)
        img = specks(img, 150, (190, 145, 160), 20, 55, 0.07, rng)
        return vignette(grain(img, 1.4, rng), 0.04)
    if i == 4:   # pearl — near-white with a whisper of pink, blue and cream
        img = glow(img, 0.28, 0.30, 0.7, 0.55, (255, 247, 250), 5)
        img = glow(img, 0.74, 0.62, 0.7, 0.55, (244, 249, 255), 5)
        img = sheen(img)
        img = specks(img, 120, (170, 172, 180), 18, 50, 0.06, rng)
        return vignette(grain(img, 1.0, rng), 0.03)
    if i == 5:   # pale sage — soft green-grey linen
        img = glow(img, 0.46, 0.30, 0.9, 0.62, (251, 255, 248), 7)
        img = wash(img, rng, 2, (246, 253, 242), (155, 180, 158), 0.7)
        img = weave(img)
        img = specks(img, 150, (140, 165, 145), 20, 55, 0.07, rng)
        return vignette(grain(img, 1.3, rng), 0.045)
    if i == 6:   # powder blue grid — light blue with quiet squares
        img = glow(img, 0.5, 0.28, 0.9, 0.6, (252, 254, 255), 7)
        img = grid(img)
        img = specks(img, 130, (155, 175, 195), 20, 55, 0.07, rng)
        return vignette(grain(img, 1.2, rng), 0.04)
    # cool ivory — very light neutral with a soft sheen and sparse cool flecks
    img = sheen(img)
    img = glow(img, 0.5, 0.36, 0.9, 0.62, (255, 255, 255), 6)
    img = specks(img, 160, (165, 170, 178), 20, 55, 0.07, rng)
    return vignette(grain(img, 1.2, rng), 0.035)


def save(img, name):
    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backgrounds", name)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").save(out, optimize=True)
    print(name, os.path.getsize(out) // 1024, "KB")


# Pass sheet indices on the CLI to repaint only some (0-based). No arguments repaints all.
if __name__ == "__main__":
    import sys
    only = set(int(a) for a in sys.argv[1:])
    for i in range(len(BASES)):
        if only and i not in only:
            continue
        save(paper_bg(i, np.random.default_rng(9000 + i)), NAMES[i].split()[0])
        print("  ^", NAMES[i])

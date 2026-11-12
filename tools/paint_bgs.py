"""Repaint the drop-in background set (bg2..bg5) as tasteful procedural night skies.

bg1 (starry night) stays the user's. All four replacements share the game's mood:
dark, low-saturation, gentle vignette, fine stars — nothing to fight the bricks for attention.
Run with the bundled runtime Python (numpy + Pillow):
    python tools/paint_bgs.py
"""
import os
import numpy as np
from PIL import Image, ImageDraw

W, H = 1600, 1000
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
U = xx / W
V = yy / H
rng = np.random.default_rng(11)


def grad3(stops):
    """Vertical gradient through (v_pos, (r,g,b)) stops with smoothstep segments."""
    poss = np.array([s[0] for s in stops], np.float32)
    cols = np.array([s[1] for s in stops], np.float32)
    t = np.clip((V - poss[0]) / (poss[-1] - poss[0]), 0.0, 1.0)
    seg = np.clip(np.searchsorted(poss, t.ravel(), side="right") - 1, 0, len(stops) - 2).reshape(t.shape)
    tt = (t - poss[seg]) / (poss[seg + 1] - poss[seg])
    tt = (tt * tt * (3 - 2 * tt))[..., None]
    a, b = cols[seg], cols[seg + 1]
    return (a + (b - a) * tt).astype(np.float32)


def glow(img, cx, cy, rx, ry, color, amp):
    """Add an elliptical gaussian light of `color` (0-255 rgb); `amp` is the 0-255 brightness delta at the centre."""
    d = ((U - cx) / rx) ** 2 + ((V - cy) / ry) ** 2
    img += (np.exp(-d) * amp)[..., None] * (np.array(color, np.float32) / 255.0)
    return img


def vignette(img, amp=0.38):
    d = ((U - 0.5) / 0.72) ** 2 + ((V - 0.54) / 0.68) ** 2
    k = (1.0 - amp * np.clip(d - 0.32, 0.0, None) ** 1.2).astype(np.float32)
    return img * k[..., None]


def grain(img, amt=2.4, rng=rng):
    return img + rng.normal(0, amt, (H, W, 1)).astype(np.float32)


def to_img(img):
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def specks(img, n, ymax=1.0, lo=90, hi=250, rng=rng):
    """Fine 1px-ish stars composited straight into the numpy buffer (additive-ish white)."""
    for _ in range(n):
        x = int(rng.uniform(0, W))
        y = int(rng.uniform(0, H * ymax))
        b = rng.uniform(lo, hi)
        r = 1 if rng.random() < 0.75 else 2
        img[y:y + r, x:x + r] += np.array([b, b, min(255, b + 8)], np.float32) * 0.55
    return img


def save(img, name):
    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backgrounds", name)
    to_img(img).save(out, optimize=True)
    print(name, os.path.getsize(out) // 1024, "KB")


# ---- bg2: "Amethyst Cathedral" — deep purple night with soft stained-glass light shafts (the
# sunset-era "Dusk Mirror" was retired by player request; its own rng keeps bg3..bg5 byte-identical)
rng2 = np.random.default_rng(2026)
img = grad3([(0.00, (24, 10, 46)), (0.28, (46, 20, 84)), (0.58, (74, 36, 116)),
             (0.80, (42, 19, 72)), (1.00, (18, 8, 38))])
for sx, sw, ph, amp in [(0.17, 0.052, 0.0, 30.0), (0.47, 0.078, 1.4, 40.0), (0.80, 0.046, 2.9, 24.0)]:
    shaft = np.exp(-(((U - sx - 0.04 * np.sin(3.6 * V + ph)) / sw) ** 2))          # soft, faintly tilted vertical
    img += (shaft * (1.0 - 0.72 * V) * amp)[..., None] * (np.array([168, 120, 232], np.float32) / 255.0)
img = glow(img, 0.47, 0.30, 0.30, 0.34, (140, 92, 200), 18)                        # broad violet heart
img = glow(img, 0.50, 1.02, 0.70, 0.18, (205, 92, 150), 18)                        # faint rose rim at the base
img = glow(img, 0.10, 0.06, 0.26, 0.20, (95, 70, 190), 12)                         # cool corner breath
specks(img, 130, ymax=0.78, lo=90, hi=240, rng=rng2)
img = vignette(grain(img, 2.1, rng=rng2), 0.34)
save(img, "bg2.png")

# ---- bg3: "Aurora Night" — curtains of light over a deep blue field ----
img = grad3([(0.00, (5, 9, 28)), (0.55, (10, 22, 52)), (0.85, (15, 36, 68)), (1.00, (10, 22, 46))])
specks(img, 150, ymax=0.85, lo=80, hi=240)
for cy, thick, col, amp, ph in [(0.20, 0.042, (70, 225, 150), 0.34, 0.0),
                                (0.33, 0.055, (60, 190, 215), 0.26, 2.1),
                                (0.46, 0.040, (130, 235, 175), 0.17, 4.2)]:
    yc = cy + 0.055 * np.sin(2 * np.pi * (U * 1.3) + ph) + 0.022 * np.sin(2 * np.pi * (U * 3.1) + ph * 1.7)
    d = (V - yc) / thick
    curtain = np.exp(-d * d) * (0.55 + 0.45 * np.sin(U * 9.0 + ph))
    img += curtain[..., None] * np.array(col, np.float32) * amp
img = glow(img, 0.5, 1.06, 0.9, 0.22, (150, 110, 70), 24)        # faint amber horizon haze
img = vignette(grain(img, 2.2), 0.38)
save(img, "bg3.png")

# ---- bg4: "Nebula" — soft cloud-blobs and a dusting of stars ----
img = grad3([(0.00, (10, 8, 26)), (0.50, (18, 14, 46)), (1.00, (9, 12, 28))])
# the nebula is built purely from soft overlapping glows — noise-cloud attempts kept reading as dirt
img = glow(img, 0.30, 0.34, 0.34, 0.30, (210, 85, 155), 46)
img = glow(img, 0.72, 0.55, 0.40, 0.34, (75, 115, 225), 42)
img = glow(img, 0.52, 0.14, 0.24, 0.20, (45, 155, 175), 22)
img = glow(img, 0.86, 0.22, 0.18, 0.16, (155, 95, 225), 20)
img = glow(img, 0.12, 0.62, 0.16, 0.20, (120, 60, 160), 16)
img = glow(img, 0.44, 0.74, 0.22, 0.16, (60, 90, 190), 18)
img = glow(img, 0.66, 0.30, 0.14, 0.13, (205, 95, 145), 14)
img = glow(img, 0.90, 0.70, 0.15, 0.18, (50, 140, 180), 12)
specks(img, 420, ymax=1.0, lo=70, hi=250)
img = vignette(grain(img, 2.6), 0.46)
save(img, "bg4.png")

# ---- bg5: "Moonlit Sea" — the synth sun replaced by a calm night ocean ----
HOR = 0.60
img = grad3([(0.00, (4, 8, 22)), (0.42, (10, 18, 42)), (HOR - 0.01, (32, 48, 88)),
             (HOR, (26, 36, 66)), (HOR + 0.02, (13, 23, 48)), (0.85, (8, 15, 34)), (1.00, (6, 11, 26))])
img = glow(img, 0.62, 0.24, 0.34, 0.30, (165, 185, 235), 30)     # moon halo
img = glow(img, 0.62, 0.24, 0.075, 0.07, (235, 240, 250), 120)   # near-disc glow
img = glow(img, 0.62, HOR + 0.16, 0.10, 0.24, (215, 190, 150), 26)  # moon path on the water
img = glow(img, 0.50, HOR, 0.95, 0.045, (170, 140, 120), 16)    # horizon haze
for _ in range(110):                                             # wave glints, brighter near the horizon
    depth = rng.uniform(0.0, 1.0) ** 1.4
    y = int(H * HOR + 6 + depth * (H * (1 - HOR) - 10))
    x = int(rng.uniform(0, W - 120))
    ln = int(rng.uniform(26, 110))
    b = (1 - depth) * rng.uniform(50, 110)
    img[y - 1:y + 1, x:x + ln] += np.array([b * 0.9, b, b * 1.05], np.float32) * 0.5
specks(img, 120, ymax=HOR - 0.04, lo=90, hi=240)
img = vignette(grain(img, 2.2), 0.40)
im = to_img(img)
dr = ImageDraw.Draw(im)
mx, my, mr = int(0.62 * W), int(0.24 * H), 16                    # the little moon disc
dr.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=(238, 242, 250))
dr.ellipse([mx - mr + 5, my - mr + 2, mx + mr - 3, my + mr - 4], fill=(246, 248, 253))
dr.line([0, int(H * HOR), W, int(H * HOR)], fill=(105, 120, 160))
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backgrounds", "bg5.png")
im.save(out, optimize=True)
print("bg5.png", os.path.getsize(out) // 1024, "KB")

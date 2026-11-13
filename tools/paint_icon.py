"""Draw the BRICK PRESS app icon — the game itself in miniature, pressed-paper style.

Cream paper sheet (rounded corners, transparent outside), a faint hand-cut keyline,
a two-row wall of six flat ink bricks wearing the game's real riso palette, the ink
paddle, and an ink ball resting on the corner brick with a paper highlight. Rendered
4x and LANCZOS-downscaled for smooth edges at every size; paper grain is baked in.
Re-runnable and deterministic. Run with the bundled runtime Python (numpy + Pillow):
    python tools/paint_icon.py
"""
import os
import random
import numpy as np
from PIL import Image, ImageDraw

S = 1024          # work resolution; final icon.png is 256
OUT = 256
PAPER = (244, 236, 219)      # #f4ecdb — the game's card paper
INK = (43, 38, 32)           # #2b2620 — the game's ink
KEY = (122, 92, 73)          # #7a5c49 — the card border brown
BRICKS = [                   # both rows wear the game's BLOCK_TYPES palette hexes
    ["#c8402e", "#c9a227", "#2a5f8f"],   # terracotta, mustard, cobalt
    ["#4c8a54", "#c96f2a", "#7b5e8c"],   # moss, burnt orange, plum
]

random.seed(7)
rng = np.random.default_rng(11)


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rrect(d, x, y, w, h, r, fill=None, outline=None, width=1):
    d.rounded_rectangle([x, y, x + w, y + h], radius=r, fill=fill, outline=outline, width=width)


# ---- paper sheet ----
mask = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(mask)
rrect(md, 48, 48, S - 96, S - 96, 190, fill=255)
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
img.paste(Image.new("RGBA", (S, S), PAPER + (255,)), (0, 0), mask)

# grain: one soft noise pass over the sheet (the rounded mask keeps the corners clean)
noise = rng.normal(0, 3.0, (S, S, 1)).astype(np.float32)
arr = np.array(img, np.float32)
rgb = np.clip(arr[..., :3] + noise * (arr[..., 3:4] / 255.0), 0, 255)
arr[..., :3] = rgb
img = Image.fromarray(arr.astype(np.uint8), "RGBA")

# ---- keyline ----
d = ImageDraw.Draw(img)
rrect(d, 108, 108, S - 216, S - 216, 130, outline=KEY + (85,), width=10)

# ---- brick wall (rows of 3, paper gaps between = grout) ----
BW, BH, GAP = 232, 104, 28
wall_w = 3 * BW + 2 * GAP
x0 = (S - wall_w) // 2             # centered inside the keyline — nothing may cross the printed margin
y0 = 240
for ri, row in enumerate(BRICKS):
    for ci, hexc in enumerate(row):
        rrect(d, x0 + ci * (BW + GAP), y0 + ri * (BH + GAP), BW, BH, 20, fill=hexrgb(hexc) + (255,))

# ---- paddle ----
PW, PH = 330, 46
rrect(d, (S - PW) // 2, 742, PW, PH, 23, fill=INK + (255,))

# ---- ink ball resting on the top-right (cobalt) brick ----
BX, BY, BR = 790, 236, 66           # centre: landed on the wall's right-hand brick, inside every margin
d.ellipse([BX - BR + 8, BY - BR + 12, BX + BR + 8, BY + BR + 12], fill=(40, 35, 28, 46))  # soft drop shadow
d.ellipse([BX - BR, BY - BR, BX + BR, BY + BR], fill=INK + (255,))
d.ellipse([BX - 40, BY - 42, BX - 8, BY - 10], fill=(250, 246, 232, 215))  # paper highlight

# ---- downscale ----
icon = img.resize((OUT, OUT), Image.LANCZOS)
out_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "icon.png")
icon.save(out_path, optimize=True)
print("icon.png", os.path.getsize(out_path), "bytes", icon.size)

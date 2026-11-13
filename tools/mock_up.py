"""mock_up.py — render mockups of four reskin directions end-to-end.

For each direction (and the untouched baseline "Now"): patch main.gd's palette
(COLOR_SLOTS block + global hex swaps + inline color literals), repaint the five
background PNGs, run tools/shot_on_boot.gd headless, and copy the resulting
shots into _mocks/<id>/. Everything is restored from the in-memory originals,
so the working tree ends exactly where it began.

    python tools/mock_up.py

Requires the bundled runtime Python (numpy + Pillow).
"""
import os
import re
import shutil
import subprocess
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
GODOT = r"C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe"
MOCKS = os.path.join(PROJ, "_mocks")
SHOTS = os.path.join(PROJ, ".shots")
W, H = 1600, 1000

# ---------------------------------------------------------------- palettes

SLOT_KEYS = ["white", "white70", "dim_white", "dark_white", "dark_overlay",
             "dim_overlay", "banner_overlay", "hud_dim", "hud_green", "hud_red",
             "glow_blue", "glow_teal", "glow_red", "glow_lava", "brown_label",
             "grad_top", "grad_bottom", "black"]

def slot_lines(sl):
    w = sl["white"]
    vals = [
        f'Color("{w}", 1.0)', f'Color("{w}", 0.70)', f'Color("{w}", 0.4)', f'Color("{w}", 0.25)',
        sl["dark_overlay"], sl["dim_overlay"], sl["banner_overlay"],
        sl["hud_dim"], sl["hud_green"], sl["hud_red"],
        sl["glow_blue"], sl["glow_teal"], sl["glow_red"], sl["glow_lava"],
        sl["brown"], sl["grad_top"], sl["grad_bottom"], "Color(0, 0, 0, 1.0)",
    ]
    vals = [(f'Color("{v}", 1.0)' if str(v).startswith("#") else v) for v in vals]
    out = ["const COLOR_SLOTS := {"]
    for k, v in zip(SLOT_KEYS, vals):
        out.append(f'\t"{k}": {v},')
    out.append("}")
    return "\n".join(out)

INK3 = "Color(0.20, 0.18, 0.15,"     # pressed-paper ink for every white-literal
DIN3 = "Color(0.10, 0.10, 0.10,"     # toybox ink
LIGHT_SPECIALS = {  # applied for the light directions (A, C)
    "Color(1, 1, 1,": None,  # value filled per direction
    "Color(1.0, 0.86, 0.55, 1.0)": "Color(0.72, 0.50, 0.15, 1.0)",
    "Color(1.0, 0.97, 0.88, 1.0)": "Color(0.23, 0.20, 0.16, 1.0)",
    "Color(1.0, 0.78, 0.76,": "Color(0.62, 0.26, 0.22,",
    "Color(0.26, 0.65, 0.96,": "Color(0.10, 0.32, 0.50,",
    "Color(0.72, 0.9, 1.0,": "Color(0.09, 0.28, 0.44,",
    "Color(0.62, 0.72, 0.88,": "Color(0.28, 0.30, 0.28,",
    "Color(0, 0, 0, 0.30)": "Color(0.97, 0.94, 0.88, 0.88)",
    "Color(0.45, 0.05, 0.10,": "Color(0.66, 0.10, 0.08,",
    "Color(0, 0, 0, 0.26)": "Color(0.97, 0.94, 0.88, 0.86)",
    "Color(1.0, 0.53, 0.20,": "Color(0.87, 0.47, 0.10,",
}

DIRS = {
    "A": {
        "name": "Pressed paper",
        "ink": INK3,
        "specials": "light",
        "hexmap": {
            "#ef5350": "#c8402e", "#ffa726": "#c96f2a", "#ffeb3b": "#c9a227",
            "#66bb6a": "#4c8a54", "#42a5f5": "#2a5f8f", "#ab47bc": "#7b5e8c",
            "#8d6e63": "#7a5c49", "#546e7a": "#3f5a66", "#ffee58": "#d8c24a",
            "#78909c": "#67757a", "#ff6f00": "#a05210", "#ff8f00": "#a05210",
            "#ffd54f": "#c9971f", "#ffcc80": "#8a5a1d", "#ffb74d": "#8f5f1f",
            "#ff8a50": "#b8541c", "#ff5722": "#a83c15", "#ff7043": "#b8501e",
            "#26a696": "#1e7268", "#80cbc4": "#25756b", "#e53935": "#a83326",
            "#ef9a9a": "#9c4a3e", "#ff1744": "#93202f", "#5d4037": "#4a3826",
            "#0b1026": "#f2e8d5", "#1a2340": "#e6d7ba", "#ffffff": "#2b2620",
            "#8fa8d8": "#6f6757", "#6f87b8": "#5b5347", "#5d74a8": "#4c463b",
            "#9fb4e0": "#6f6757",
        },
        "slots": {"white": "#2b2620", "dark_overlay": "Color(0, 0, 0, 0.5)",
                  "dim_overlay": "Color(0, 0, 0, 0.28)",
                  "banner_overlay": "Color(0.96, 0.93, 0.86, 0.92)",
                  "hud_dim": "#67757a", "hud_green": "#25756b", "hud_red": "#9c4a3e",
                  "glow_blue": "#2a5f8f", "glow_teal": "#1e7268", "glow_red": "#93202f",
                  "glow_lava": "#b8501e", "brown": "#4a3826",
                  "grad_top": "#f2e8d5", "grad_bottom": "#e6d7ba"},
    },
    "B": {
        "name": "Slate & chalk",
        "ink": None,
        "specials": [
            ("Color(0.26, 0.65, 0.96,", "Color(0.42, 0.72, 0.66,"),
            ("Color(0.72, 0.9, 1.0,", "Color(0.80, 0.90, 0.84,"),
        ],
        "hexmap": {
            "#ef5350": "#e08a7e", "#ffa726": "#e5ae7e", "#ffeb3b": "#e3d48b",
            "#66bb6a": "#94c99a", "#42a5f5": "#9fc7bd", "#ab47bc": "#b498c9",
            "#8d6e63": "#b99c8b", "#546e7a": "#93aeb3", "#ffee58": "#efe3a0",
            "#78909c": "#93a89d", "#ff6f00": "#c98a3f", "#ff8f00": "#c98a3f",
            "#ffd54f": "#e3c878", "#ffcc80": "#d5b283", "#ffb74d": "#d9a05c",
            "#ff8a50": "#d99060", "#ff5722": "#cf7a4e", "#ff7043": "#d98a5c",
            "#26a696": "#8fbfae", "#80cbc4": "#a9d0c2", "#e53935": "#cf7f74",
            "#ef9a9a": "#e0aea6", "#ff1744": "#d9576e", "#5d4037": "#8d7757",
            "#0b1026": "#31423c", "#1a2340": "#3b4c44", "#ffffff": "#f2efe4",
            "#8fa8d8": "#b8c9c0", "#6f87b8": "#9fb2a8", "#5d74a8": "#8aa096",
            "#9fb4e0": "#c3d2c8",
        },
        "slots": {"white": "#f2efe4", "dark_overlay": "Color(0, 0, 0, 0.5)",
                  "dim_overlay": "Color(0, 0, 0, 0.28)",
                  "banner_overlay": "Color(0, 0, 0, 0.65)",
                  "hud_dim": "#93a89d", "hud_green": "#a9d0c2", "hud_red": "#e0aea6",
                  "glow_blue": "#9fc7bd", "glow_teal": "#8fbfae", "glow_red": "#d9576e",
                  "glow_lava": "#d98a5c", "brown": "#8d7757",
                  "grad_top": "#31423c", "grad_bottom": "#3b4c44"},
    },
    "C": {
        "name": "Bauhaus toybox",
        "ink": DIN3,
        "specials": "light_nocards",
        "hexmap": {
            "#ef5350": "#d7263d", "#ffa726": "#e97c0b", "#ffeb3b": "#f2c400",
            "#66bb6a": "#2e8b57", "#42a5f5": "#1f57a6", "#ab47bc": "#262626",
            "#8d6e63": "#a9714b", "#546e7a": "#55707f", "#ffee58": "#f7e733",
            "#78909c": "#8c8c8c", "#ff6f00": "#a85f00", "#ff8f00": "#b8770a",
            "#ffd54f": "#f0b429", "#ffcc80": "#c98a2e", "#ffb74d": "#a87b12",
            "#ff8a50": "#e07818", "#ff5722": "#d95f02", "#ff7043": "#e07818",
            "#26a696": "#2e8b57", "#80cbc4": "#2e8b57", "#e53935": "#d7263d",
            "#ef9a9a": "#a8262f", "#ff1744": "#d7263d", "#5d4037": "#3d2c1c",
            "#0b1026": "#f7f4ef", "#1a2340": "#e9e2d5", "#ffffff": "#141414",
            "#8fa8d8": "#6e6a5e", "#6f87b8": "#585449", "#5d74a8": "#454138",
            "#9fb4e0": "#6e6a5e",
        },
        "slots": {"white": "#141414", "dark_overlay": "Color(0, 0, 0, 0.5)",
                  "dim_overlay": "Color(0, 0, 0, 0.28)",
                  "banner_overlay": "Color(0.94, 0.92, 0.86, 0.95)",
                  "hud_dim": "#8c8c8c", "hud_green": "#2e8b57", "hud_red": "#a8262f",
                  "glow_blue": "#1f57a6", "glow_teal": "#2e8b57", "glow_red": "#d7263d",
                  "glow_lava": "#e07818", "brown": "#3d2c1c",
                  "grad_top": "#f7f4ef", "grad_bottom": "#e9e2d5"},
    },
    "D": {
        "name": "The Depths",
        "ink": None,
        "specials": [
            ("Color(0.26, 0.65, 0.96,", "Color(0.33, 0.70, 0.74,"),
            ("Color(0.72, 0.9, 1.0,", "Color(0.75, 0.90, 0.90,"),
        ],
        "hexmap": {
            "#ef5350": "#e76f51", "#ffa726": "#f4a259", "#ffeb3b": "#e9c46a",
            "#66bb6a": "#74b09b", "#42a5f5": "#6fb7c9", "#ab47bc": "#9d87b5",
            "#8d6e63": "#a08266", "#546e7a": "#5e8a97", "#ffee58": "#f0dd8c",
            "#78909c": "#7d9a95", "#ff6f00": "#c97a1e", "#ff8f00": "#c97a1e",
            "#ffd54f": "#e9c46a", "#ffcc80": "#d8ab70", "#ffb74d": "#d89a45",
            "#ff8a50": "#e08a5a", "#ff5722": "#d95f33", "#ff7043": "#e07a4a",
            "#26a696": "#57b39a", "#80cbc4": "#8fbfae", "#e53935": "#d95f50",
            "#ef9a9a": "#e8a08e", "#ff1744": "#ef6a5a", "#5d4037": "#6b5a48",
            "#0b1026": "#1e5157", "#1a2340": "#0d2b30", "#ffffff": "#efe6d0",
            "#8fa8d8": "#a4c2bb", "#6f87b8": "#8dafa7", "#5d74a8": "#779890",
            "#9fb4e0": "#b3cfc6",
        },
        "slots": {"white": "#efe6d0", "dark_overlay": "Color(0, 0, 0, 0.5)",
                  "dim_overlay": "Color(0, 0, 0, 0.28)",
                  "banner_overlay": "Color(0, 0, 0, 0.65)",
                  "hud_dim": "#7d9a95", "hud_green": "#8fbfae", "hud_red": "#e8a08e",
                  "glow_blue": "#6fb7c9", "glow_teal": "#57b39a", "glow_red": "#ef6a5a",
                  "glow_lava": "#e07a4a", "brown": "#6b5a48",
                  "grad_top": "#1e5157", "grad_bottom": "#0d2b30"},
    },
}

# ---------------------------------------------------------------- backgrounds

yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
U, V = xx / W, yy / H

def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], np.float32)

def flat(h):
    return np.tile(hexrgb(h), (H, W, 1)).copy()

def vgrad(a, b):
    t = V[..., None]
    return (hexrgb(a) * (1 - t) + hexrgb(b) * t).astype(np.float32) * np.ones((1, 1, 1), np.float32)

def glow(img, cx, cy, rx, ry, color, amp):
    d = ((U - cx) / rx) ** 2 + ((V - cy) / ry) ** 2
    img += (np.exp(-d) * amp)[..., None] * (np.array(color, np.float32) / 255.0)
    return img

def beam(img, off, slope, amp, color=(235, 250, 245)):
    d = (U - off - slope * V) ** 2
    img += (np.exp(-d * 30.0) * amp)[..., None] * (np.array(color, np.float32) / 255.0)
    return img

def vignette(img, amp):
    d = ((U - 0.5) / 0.72) ** 2 + ((V - 0.54) / 0.68) ** 2
    k = (1.0 - amp * np.clip(d - 0.32, 0.0, None) ** 1.2).astype(np.float32)
    return img * k[..., None]

def grain(img, amt, rng):
    return img + rng.normal(0, amt, (H, W, 1)).astype(np.float32)

def specks(img, n, color, lo, hi, mul, rng, size_p=0.18):
    for _ in range(n):
        x, y = int(rng.uniform(0, W)), int(rng.uniform(0, H))
        b = rng.uniform(lo, hi)
        r = 2 if rng.random() < size_p else 1
        img[y:y + r, x:x + r] += np.array(color, np.float32) * (b / 255.0) * mul
    return img

def paper_bg(i, rng):
    img = flat(["#f4ead7", "#efe3cc", "#ead9ba", "#e9e2d2", "#f1e2cc"][i])
    for k in range(3):
        img = glow(img, rng.uniform(0.2, 0.8), rng.uniform(0.2, 0.8), rng.uniform(0.25, 0.5),
                   rng.uniform(0.2, 0.4), (255, 250, 235), rng.uniform(6, 14))
    img = specks(img, 420, (90, 80, 65), 30, 90, 0.10, rng)      # paper fibers
    return vignette(grain(img, 2.2, rng), 0.10)

def slate_bg(i, rng):
    img = flat(["#2f3e38", "#33463e", "#2a3833", "#37493f", "#2d4038"][i])
    for k in range(3):
        img = glow(img, rng.uniform(0.15, 0.85), rng.uniform(0.15, 0.85), rng.uniform(0.3, 0.55),
                   rng.uniform(0.2, 0.4), (205, 225, 215), rng.uniform(5, 10))
    img = specks(img, 260, (235, 240, 230), 60, 200, 0.30, rng)  # chalk dust
    return vignette(grain(img, 2.4, rng), 0.28)

TOY_CHIPS = ["#e8d9b8", "#dcd0ba", "#cfd6d4", "#e7cfc2", "#d9d3c4", "#e3dcc9"]

def toybox_bg(i, rng):
    img = flat(["#f7f4ee", "#f4efe5", "#f2ecdd", "#f6f1e8", "#efe9db"][i])
    for k in range(3):  # giant soft tonal shapes
        cx, cy = rng.uniform(0.15, 0.85), rng.uniform(0.15, 0.85)
        d = np.sqrt((U - cx) ** 2 + ((V - cy) * 1.25) ** 2)
        img += (d < rng.uniform(0.22, 0.4))[..., None] * np.array(
            [[rng.uniform(-7, 9) * 0.4, rng.uniform(-7, 9) * 0.5, rng.uniform(-7, 9) * 0.9]], np.float32)
    img = grain(img, 1.8, rng)
    pil = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    ol = Image.new("RGBA", pil.size, (0, 0, 0, 0))
    dr = ImageDraw.Draw(ol)
    for _ in range(80):
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        a, b = rng.uniform(7, 20), rng.uniform(5, 14)
        col = hexrgb(TOY_CHIPS[int(rng.integers(0, len(TOY_CHIPS)))]).astype(int)
        dr.ellipse([x, y, x + a, y + b], fill=(*col, int(rng.uniform(70, 150))))
    return Image.alpha_composite(pil, ol).convert("RGB")

def depths_bg(i, rng):
    tops = ["#2a6066", "#27585e", "#2d6469", "#24535a", "#316a6e"]
    bots = ["#0e2f35", "#102f36", "#0d2a30", "#0f333a", "#123539"]
    img = vgrad(tops[i], bots[i])
    img = glow(img, 0.5, -0.25, 0.9, 0.55, (200, 235, 230), 26)
    for k in range(2):
        img = beam(img, rng.uniform(0.2, 0.75), rng.uniform(0.10, 0.22), rng.uniform(14, 22))
    img = specks(img, 380, (170, 225, 215), 40, 160, 0.30, rng)  # plankton
    return vignette(grain(img, 2.0, rng), 0.34)

BG_FN = {"A": paper_bg, "B": slate_bg, "C": toybox_bg, "D": depths_bg}

# ---------------------------------------------------------------- pipeline

def paint_bgs(key):
    fn = BG_FN[key]
    for i in range(5):
        out = os.path.join(PROJ, "backgrounds", f"bg{i + 1}.png")
        rng = np.random.default_rng(3000 + i)
        img = fn(i, rng)
        if isinstance(img, np.ndarray):
            img = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
        img.save(out, optimize=True)
        print(f"  bg{i + 1}.png repainted ({key}) {os.path.getsize(out) // 1024} KB", flush=True)

def patch_main(key):
    text = ORIG_MAIN
    d = DIRS[key]
    for src, dst in d["hexmap"].items():
        text = text.replace(src, dst)
    sp = d["specials"]
    if sp in ("light", "light_nocards"):
        for src, dst in LIGHT_SPECIALS.items():
            if src == "Color(1, 1, 1,":
                dst = d["ink"]
            if src in ("Color(0, 0, 0, 0.30)", "Color(0, 0, 0, 0.26)") and sp == "light_nocards":
                continue  # ink cards on cream read fine in the toybox direction
            text = text.replace(src, dst)
        if sp == "light_nocards":  # direction C keeps its own fever/lives/shield triples
            for src, dst in [("Color(1.0, 0.86, 0.55, 1.0)", "Color(0.88, 0.68, 0.10, 1.0)"),
                             ("Color(1.0, 0.97, 0.88, 1.0)", "Color(0.15, 0.15, 0.15, 1.0)"),
                             ("Color(1.0, 0.78, 0.76,", "Color(0.72, 0.14, 0.20,"),
                             ("Color(0.26, 0.65, 0.96,", "Color(0.12, 0.34, 0.65,"),
                             ("Color(0.72, 0.9, 1.0,", "Color(0.10, 0.28, 0.55,"),
                             ("Color(0.62, 0.72, 0.88,", "Color(0.15, 0.15, 0.15,")]:
                text = text.replace(src, dst)
    elif isinstance(sp, list):
        for src, dst in sp:
            text = text.replace(src, dst)
    block = slot_lines(d["slots"])
    text, n = re.subn(r"const COLOR_SLOTS := \{.*?\n\}", block, text, count=1, flags=re.S)
    assert n == 1, "COLOR_SLOTS block not replaced"
    with open(os.path.join(PROJ, "main.gd"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

def run_godot(args, log, timeout=420):
    with open(log, "wb") as f:
        r = subprocess.run([GODOT] + args, stdout=f, stderr=subprocess.STDOUT, timeout=timeout)
    print(f"  godot exit={r.returncode} log={os.path.basename(log)}", flush=True)
    return r.returncode

def first_shot(names, prefixes):
    for p in prefixes:
        for n in names:
            if n.startswith(p):
                return n
    return None

def run_direction(key):
    dst = os.path.join(MOCKS, key)
    os.makedirs(dst, exist_ok=True)
    if key != "NOW":
        patch_main(key)
        paint_bgs(key)
    # real window (NOT --headless): the shot tool snapshots the real GPU viewport,
    # which the dummy headless renderer does not back with a texture
    rc = run_godot(["--path", PROJ, "-s", "res://tools/shot_on_boot.gd"],
                   os.path.join(dst, "shots.log"))
    names = sorted(os.listdir(SHOTS))
    copies = {
        "menu": first_shot(names, ("1_",)),
        "fun": "5_fun.png" if "5_fun.png" in names else first_shot(names, ("5_",)),
        "pause": "9_pause.png" if "9_pause.png" in names else first_shot(names, ("9_", "6_", "3_")),
    }
    for role, n in copies.items():
        if n:
            src = os.path.join(SHOTS, n)
            dstp = os.path.join(dst, role + n[1:])
            shutil.copyfile(src, dstp)
    print(f"  {key} shots: " + ", ".join(f"{r}={v}" for r, v in copies.items()), flush=True)
    return copies

# ---------------------------------------------------------------- montage

def montage(rows, labels, out, cell_w=520):
    fonts = {}
    for sz in (30, 22):
        try:
            fonts[sz] = ImageFont.truetype("arial.ttf", sz)
        except Exception:
            try:
                fonts[sz] = ImageFont.load_default(size=sz)
            except TypeError:
                fonts[sz] = ImageFont.load_default()
    def scaled(p):
        im = Image.open(p)
        w = cell_w
        h = int(im.height * w / im.width)
        return im.resize((w, h), Image.LANCZOS)
    pad, head = 14, 46
    cw = cell_w
    ch = max(scaled(p).height for row in rows for p in row if p)
    canvas = Image.new("RGB", (pad + (cw + pad) * len(rows[0]) + pad, head + pad + (ch + pad) * len(rows)), (26, 26, 30))
    dr = ImageDraw.Draw(canvas)
    for j, lab in enumerate(labels):
        dr.text((pad + j * (cw + pad) + 4, 10), lab, font=fonts[30], fill=(240, 240, 235))
    for i, row in enumerate(rows):
        for j, p in enumerate(row):
            if not p:
                continue
            x, y = pad + j * (cw + pad), head + pad + i * (ch + pad)
            canvas.paste(scaled(p), (x, y))
    canvas.save(out, optimize=True)
    print("  saved", out, canvas.size, flush=True)

def strip(paths, labels, out):
    fonts = {}
    for sz in (34,):
        try:
            fonts[sz] = ImageFont.truetype("arial.ttf", sz)
        except Exception:
            fonts[sz] = ImageFont.load_default()
    ims = [Image.open(p) for p in paths]
    cw, ch = 1280, 720
    head, pad = 56, 0
    canvas = Image.new("RGB", (cw * len(paths) + pad * (len(paths) - 1), ch + head), (26, 26, 30))
    dr = ImageDraw.Draw(canvas)
    for k, (im, lab) in enumerate(zip(ims, labels)):
        x = k * (cw + pad)
        canvas.paste(im.convert("RGB").resize((cw, ch), Image.LANCZOS), (x, head))
        dr.text((x + 10, 12), lab, font=fonts[sz], fill=(240, 240, 235))
    canvas.save(out, optimize=True)
    print("  saved", out, canvas.size, flush=True)

# ---------------------------------------------------------------- main

def main():
    os.makedirs(MOCKS, exist_ok=True)
    global ORIG_MAIN, ORIG_BGS
    with open(os.path.join(PROJ, "main.gd"), encoding="utf-8") as f:
        ORIG_MAIN = f.read()
    ORIG_BGS = {}
    for i in range(1, 6):
        p = os.path.join(PROJ, "backgrounds", f"bg{i}.png")
        with open(p, "rb") as f:
            ORIG_BGS[p] = f.read()
    order = ["NOW", "A", "B", "C", "D"]
    only = [a.strip().upper() for a in sys.argv[1:] if a.strip().upper() in ("NOW", "A", "B", "C", "D")]
    if only:
        order = [k for k in order if k in only]
    try:
        for key in order:
            print(f"== {key} ==", flush=True)
            run_direction(key)
            if key != "NOW":
                with open(os.path.join(PROJ, "main.gd"), "w", encoding="utf-8", newline="\n") as f:
                    f.write(ORIG_MAIN)
                for p, data in ORIG_BGS.items():
                    with open(p, "wb") as f:
                        f.write(data)
    finally:
        with open(os.path.join(PROJ, "main.gd"), "w", encoding="utf-8", newline="\n") as f:
            f.write(ORIG_MAIN)
        for p, data in ORIG_BGS.items():
            with open(p, "wb") as f:
                f.write(data)
    def m(key, role):
        d = os.path.join(MOCKS, key)
        for n in sorted(os.listdir(d)):
            if n.startswith(role):
                return os.path.join(d, n)
        return None
    names = {"NOW": "Now (navy night)", "A": "A - Pressed paper", "B": "B - Slate & chalk",
             "C": "C - Bauhaus toybox", "D": "D - The Depths"}
    labels = [names[k] for k in order]
    montage([[m(k, r) for k in order] for r in ("menu", "fun", "pause")],
            labels, os.path.join(MOCKS, "contact_sheet.png"))
    for r in ("menu", "fun"):
        strip([m(k, r) for k in order], labels, os.path.join(MOCKS, f"strip_{r}.png"))
    print("DONE", flush=True)

if __name__ == "__main__":
    main()

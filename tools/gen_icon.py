# One-off: generate breakout-game-godot/icon.png — a mini brick-breaker scene for the Windows app icon.
from PIL import Image, ImageDraw

S = 128
img = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(img)

# dark blue vertical gradient, like the game background
top = (11, 16, 38)
bot = (26, 35, 64)
for y in range(S):
    t = y / (S - 1)
    d.line([(0, y), (S, y)], fill=(*[int(top[i] + (bot[i] - top[i]) * t) for i in range(3)], 255))

# brick grid (like the game's 12-col grid, shrunk to 5 wide, 3 rows)
pal = ["#ef5350", "#ffa726", "#ffeb3b", "#66bb6a", "#42a5f5", "#ab47bc"]
for r in range(3):
    for c in range(5):
        col = pal[(r * 5 + c) % len(pal)]
        x, y = 8 + c * 23, 14 + r * 14
        d.rounded_rectangle([x, y, x + 21, y + 12], radius=3, fill=col)

# ball with halo
d.ellipse([S / 2 - 11, 74 - 11, S / 2 + 11, 74 + 11], fill=(255, 255, 255, 110))
d.ellipse([S / 2 - 7, 74 - 7, S / 2 + 7, 74 + 7], fill=(255, 255, 255, 255))

# paddle
d.rounded_rectangle([S / 2 - 26, 100, S / 2 + 26, 112], radius=5, fill=(255, 255, 255, 255))

img.save("breakout-game-godot/icon.png")
print("icon written")

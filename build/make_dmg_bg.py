#!/usr/bin/env python3
"""Generate a cyberpunk DMG background (660x400 logical → 1320x800 @2x Retina)."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, random, os

W, H = 1320, 800
# Icons sit at logical (160,240) and (500,240) → 2x: (320,480) and (1000,480)
# Horizon line at ~55% height keeps upper area clean for title

rng = random.Random(7)

# ── base gradient: deep space indigo ─────────────────────────────────────────
img = Image.new("RGB", (W, H), (3, 3, 12))
draw = ImageDraw.Draw(img)
for y in range(H):
    t = y / H
    draw.line([(0, y), (W, y)], fill=(
        int(3  + t *  4),
        int(3  + t *  6),
        int(12 + t * 14),
    ))

# ── perspective grid (vanishing point top-center) ────────────────────────────
HOR = int(H * 0.55)   # horizon at 55% → icons at y=560/800 (70%) are in the grid floor
VP  = (W // 2, HOR)
CYAN = (0, 240, 210)

# horizontal floor lines
N_HORIZ = 18
for i in range(N_HORIZ):
    t = (i / (N_HORIZ - 1)) ** 1.6   # perspective compression
    y = int(HOR + t * (H - HOR))
    brightness = int(18 + t * 90)
    col = tuple(min(255, int(c * brightness / 100)) for c in CYAN)
    w = 1 if i < N_HORIZ - 2 else 2
    draw.line([(0, y), (W, y)], fill=col, width=w)

# radiating floor lines from VP
N_VERT = 36
for i in range(N_VERT + 1):
    t = i / N_VERT
    x_bot = int(t * W)
    dist = abs(t - 0.5) * 2   # 0=center, 1=edge
    brightness = int(30 + (1 - dist) * 60)
    col = tuple(min(255, int(c * brightness / 100)) for c in CYAN)
    draw.line([VP, (x_bot, H)], fill=col, width=1)

# ── horizon glow line ─────────────────────────────────────────────────────────
glow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow_layer)
for offset, alpha in [(6, 15), (4, 30), (2, 60), (1, 120), (0, 200)]:
    gd.line([(0, HOR + offset), (W, HOR + offset)], fill=(0, 255, 210, alpha), width=1)
    gd.line([(0, HOR - offset), (W, HOR - offset)], fill=(180, 0, 255, alpha // 2), width=1)
img = Image.alpha_composite(img.convert("RGBA"), glow_layer).convert("RGB")
draw = ImageDraw.Draw(img)

# ── scanlines (subtle) ───────────────────────────────────────────────────────
scan = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sd   = ImageDraw.Draw(scan)
for y in range(0, H, 2):
    sd.line([(0, y), (W, y)], fill=(0, 0, 0, 28))
img = Image.alpha_composite(img.convert("RGBA"), scan).convert("RGB")
draw = ImageDraw.Draw(img)

# ── star field (upper sky only) ───────────────────────────────────────────────
for _ in range(320):
    sx = rng.randint(0, W)
    sy = rng.randint(0, HOR - 20)
    sb = rng.randint(60, 200)
    sc = rng.choice([(sb, sb, sb), (sb, 255, 240), (200, sb, 255)])
    draw.point((sx, sy), fill=sc)

# ── neon corner brackets ──────────────────────────────────────────────────────
PAD, ARM = 24, 50
for (x, y), flip_x, flip_y, col in [
    ((PAD, PAD),         False, False, (0, 255, 210)),
    ((W - PAD, PAD),     True,  False, (0, 255, 210)),
    ((PAD, H - PAD),     False, True,  (200, 0, 255)),
    ((W - PAD, H - PAD), True,  True,  (200, 0, 255)),
]:
    sx = -1 if flip_x else 1
    sy = -1 if flip_y else 1
    draw.line([(x, y), (x + sx * ARM, y)], fill=col, width=2)
    draw.line([(x, y), (x, y + sy * ARM)], fill=col, width=2)

# thin border
draw.rectangle([PAD, PAD, W - PAD, H - PAD], outline=(0, 60, 55), width=1)

# ── side accent lines ─────────────────────────────────────────────────────────
for x_pos, col in [(PAD + 20, (0, 180, 255)), (W - PAD - 20, (180, 0, 255))]:
    draw.line([(x_pos, PAD + ARM + 10), (x_pos, HOR - 10)], fill=col, width=1)

# ── glitch pixel scatter ──────────────────────────────────────────────────────
glitch = Image.new("RGBA", (W, H), (0, 0, 0, 0))
glit_d = ImageDraw.Draw(glitch)
for _ in range(300):
    gx = rng.randint(0, W)
    gy = rng.randint(0, HOR)
    gc = rng.choice([(0, 255, 200), (200, 0, 255), (255, 220, 0), (0, 200, 255)])
    ga = rng.randint(50, 180)
    glit_d.point((gx, gy), fill=(*gc, ga))
img = Image.alpha_composite(img.convert("RGBA"), glitch).convert("RGB")
draw = ImageDraw.Draw(img)

# ── title text with neon glow ─────────────────────────────────────────────────
font_candidates = [
    "/System/Library/Fonts/Supplemental/Courier New Bold.ttf",
    "/System/Library/Fonts/Monaco.ttf",
    "/System/Library/Fonts/Menlo.ttc",
]
title_font = sub_font = None
for fc in font_candidates:
    if os.path.exists(fc):
        try:
            title_font = ImageFont.truetype(fc, 68)
            sub_font   = ImageFont.truetype(fc, 22)
            break
        except Exception:
            pass

TITLE = "MUSIC TOOLS"
SUB   = "drag  →  /Applications"

if title_font:
    tw = draw.textlength(TITLE, font=title_font)
    tx, ty = (W - tw) / 2, 72

    # multi-layer glow
    for spread, alpha in [(12, 8), (8, 18), (4, 45), (2, 90)]:
        gl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        gld = ImageDraw.Draw(gl)
        for dx in range(-spread, spread + 1, max(1, spread // 3)):
            for dy in range(-spread, spread + 1, max(1, spread // 3)):
                gld.text((tx + dx, ty + dy), TITLE, font=title_font,
                         fill=(0, 255, 210, alpha))
        img = Image.alpha_composite(img.convert("RGBA"), gl).convert("RGB")
        draw = ImageDraw.Draw(img)

    draw.text((tx, ty), TITLE, font=title_font, fill=(0, 255, 210))

    # decorative rule
    rule_y = ty + 90
    draw.line([(W // 2 - 260, rule_y), (W // 2 + 260, rule_y)],
              fill=(0, 140, 120), width=1)
    draw.line([(W // 2 - 260, rule_y + 3), (W // 2 + 260, rule_y + 3)],
              fill=(160, 0, 200, ), width=1)

    if sub_font:
        sw = draw.textlength(SUB, font=sub_font)
        draw.text(((W - sw) / 2, rule_y + 12), SUB, font=sub_font,
                  fill=(60, 160, 140))

out = os.path.join(os.path.dirname(__file__), "dmg_bg.png")
# 144 DPI tells macOS to treat this as @2x Retina (logical size = 660x400)
img.save(out, "PNG", dpi=(144, 144))
print(f"Saved {out}  ({W}x{H} @ 144 DPI → 660x400 logical)")

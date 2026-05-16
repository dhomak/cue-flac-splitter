#!/usr/bin/env python3
"""Cartoonish cyberpunk skull icon — bright, bold, chunky."""

import math, os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT  = os.path.join(os.path.dirname(__file__), "icon_1024.png")

# ── Palette ──────────────────────────────────────────────────────────────────
BG1       = ( 14,   6,  34)   # deep purple-black
BG2       = ( 28,  12,  58)
PINK      = (255,  50, 140)
PINK_LT   = (255, 130, 200)
CYAN      = (  0, 230, 255)
CYAN_LT   = (140, 245, 255)
PURPLE    = (180,  60, 255)
YELLOW    = (255, 230,  50)
SKULL_BG  = ( 30,  18,  65)
WHITE     = (255, 255, 255)
OUTLINE   = ( 20,   8,  45)   # near-black for cartoon outlines
BONE_COL  = (220, 180, 255)   # lavender bone color

def rgba(rgb, a=255): return (*rgb, a)

img  = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# ── Background ────────────────────────────────────────────────────────────────
draw.rounded_rectangle([0, 0, SIZE, SIZE], radius=200, fill=rgba(BG1))

# gradient-ish bg with two radial blobs
glow = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
gd   = ImageDraw.Draw(glow)
for i in range(16):
    r = 500 - i*28
    a = 5 + i*2
    gd.ellipse([512-r, 512-r, 512+r, 512+r], fill=(40,10,90,a))
for i in range(10):
    r = 360 - i*32
    a = 8
    gd.ellipse([180-r, 900-r, 180+r, 900+r], fill=(*PINK, a))
    gd.ellipse([844-r, 160-r, 844+r, 160+r], fill=(*CYAN, a))
glow = glow.filter(ImageFilter.GaussianBlur(50))
img  = Image.alpha_composite(img, glow)
draw = ImageDraw.Draw(img)

# grid lines
for x in range(0, SIZE, 52):
    draw.line([(x,0),(x,SIZE)], fill=(0,200,255,18), width=1)
for y in range(0, SIZE, 52):
    draw.line([(0,y),(SIZE,y)], fill=(255,40,120,14), width=1)

# ── Helper: fat outlined shape ────────────────────────────────────────────────
OL = 10   # outline thickness

def fat_ellipse(draw, box, fill, outline=OUTLINE, width=OL):
    draw.ellipse(box, fill=rgba(outline), )
    x0,y0,x1,y1 = box
    draw.ellipse([x0+width,y0+width,x1-width,y1-width], fill=rgba(fill))

def fat_poly(draw, pts, fill, outline=OUTLINE, width=OL):
    # expand outline by drawing thick version first
    draw.polygon(pts, fill=rgba(outline))
    # shrink inward (approximate by scaling toward centroid)
    cx = sum(p[0] for p in pts)/len(pts)
    cy = sum(p[1] for p in pts)/len(pts)
    inner = [(cx+(p[0]-cx)*(1-width/120), cy+(p[1]-cy)*(1-width/120)) for p in pts]
    draw.polygon(inner, fill=rgba(fill))

def fat_rect(draw, box, fill, outline=OUTLINE, width=OL, r=0):
    x0,y0,x1,y1 = box
    if r:
        draw.rounded_rectangle([x0,y0,x1,y1], radius=r+width, fill=rgba(outline))
        draw.rounded_rectangle([x0+width,y0+width,x1-width,y1-width],
                                radius=r, fill=rgba(fill))
    else:
        draw.rectangle([x0,y0,x1,y1], fill=rgba(outline))
        draw.rectangle([x0+width,y0+width,x1-width,y1-width], fill=rgba(fill))

# ── CROSSBONES ────────────────────────────────────────────────────────────────
BW = 52   # bone width
BL = OL   # bone outline

def draw_bone(draw, x1, y1, x2, y2):
    # outline pass
    draw.line([(x1,y1),(x2,y2)], fill=rgba(OUTLINE), width=BW+BL*2)
    draw.line([(x1,y1),(x2,y2)], fill=rgba(BONE_COL), width=BW)
    for cx,cy in [(x1,y1),(x2,y2)]:
        # 2 knuckle bumps per end
        ang = math.atan2(y2-y1, x2-x1)
        perp = ang + math.pi/2
        for side in [-1, 1]:
            kx = cx + side * math.cos(perp) * 28
            ky = cy + side * math.sin(perp) * 28
            kr = BW//2 + 10
            draw.ellipse([kx-kr-BL, ky-kr-BL, kx+kr+BL, ky+kr+BL], fill=rgba(OUTLINE))
            draw.ellipse([kx-kr, ky-kr, kx+kr, ky+kr], fill=rgba(BONE_COL))

sk = 512
# /  bone
draw_bone(draw, sk-260, sk+310, sk+260, sk+50)
# \  bone
draw_bone(draw, sk-260, sk+50,  sk+260, sk+310)

# ── SKULL ─────────────────────────────────────────────────────────────────────
# cranium — big round dome
CR = 215   # cranium radius x
CRY = 200  # cranium radius y
CX, CY = 512, 400

# outline halo glow
for i in range(5):
    r = i * 12
    a = 40 - i*7
    draw.ellipse([CX-CR-r, CY-CRY-r, CX+CR+r, CY+CRY+r],
                 fill=(*PURPLE, a))

# cranium fill
draw.ellipse([CX-CR-OL, CY-CRY-OL, CX+CR+OL, CY+CRY+OL], fill=rgba(OUTLINE))
draw.ellipse([CX-CR,    CY-CRY,    CX+CR,    CY+CRY],    fill=rgba(SKULL_BG))

# cheekbones — two side bumps
for side, sx in [(-1, CX-CR+18), (1, CX+CR-18)]:
    fat_ellipse(draw, [sx-52, CY+40, sx+52, CY+140], SKULL_BG)

# jaw block — chunky rectangle
JT = CY + 115   # jaw top
JB = CY + 270   # jaw bottom
JW = 185        # jaw half-width
draw.rounded_rectangle([CX-JW-OL, JT-OL, CX+JW+OL, JB+OL],
                        radius=28, fill=rgba(OUTLINE))
draw.rounded_rectangle([CX-JW, JT, CX+JW, JB], radius=20, fill=rgba(SKULL_BG))

# cover seam
draw.rectangle([CX-CR+20, JT-4, CX+CR-20, JT+20], fill=rgba(SKULL_BG))

# ── teeth ─────────────────────────────────────────────────────────────────────
tw, th, tgap = 46, 60, 10
n_teeth = 5
total_w = n_teeth*tw + (n_teeth-1)*tgap
tx0 = CX - total_w//2
for i in range(n_teeth):
    tx = tx0 + i*(tw+tgap)
    ty = JT + 30
    draw.rounded_rectangle([tx-OL, ty-OL, tx+tw+OL, ty+th+OL],
                            radius=10, fill=rgba(OUTLINE))
    draw.rounded_rectangle([tx, ty, tx+tw, ty+th], radius=8, fill=rgba(WHITE))

# ── EYE SOCKETS — big round hollow eyes with neon glow ────────────────────────
ER = 72   # eye radius
EY = CY - 35
for ex in [CX-100, CX+100]:
    # pink glow halo
    for i in range(6):
        r = i*12
        a = 55 - i*8
        draw.ellipse([ex-ER-r, EY-ER-r, ex+ER+r, EY+ER+r],
                     fill=(*PINK, max(0,a)))
    # outline ring
    draw.ellipse([ex-ER-OL, EY-ER-OL, ex+ER+OL, EY+ER+OL], fill=rgba(OUTLINE))
    # dark void
    draw.ellipse([ex-ER, EY-ER, ex+ER, EY+ER], fill=(5,2,15,255))
    # neon pink iris ring
    draw.ellipse([ex-ER+10, EY-ER+10, ex+ER-10, EY+ER-10],
                 fill=(*PINK, 255))
    # inner dark pupil
    draw.ellipse([ex-ER+30, EY-ER+30, ex+ER-30, EY+ER-30],
                 fill=(5,2,15,255))
    # tiny cyan glint
    draw.ellipse([ex-14, EY-20, ex+4, EY-4], fill=rgba(CYAN_LT))

# ── Nose — heart-shaped cavity ────────────────────────────────────────────────
NX, NY = CX, CY+75
draw.ellipse([NX-28-OL, NY-OL, NX-4+OL,    NY+32+OL], fill=rgba(OUTLINE))
draw.ellipse([NX+4-OL,  NY-OL, NX+28+OL,   NY+32+OL], fill=rgba(OUTLINE))
draw.polygon([(NX-36,NY+16),(NX,NY+60),(NX+36,NY+16)], fill=rgba(OUTLINE))
draw.ellipse([NX-28, NY, NX-4,  NY+32], fill=(5,2,15,255))
draw.ellipse([NX+4,  NY, NX+28, NY+32], fill=(5,2,15,255))
draw.polygon([(NX-36,NY+18),(NX,NY+58),(NX+36,NY+18)], fill=(5,2,15,255))

# ── Eyebrow arches — angry sharp brows ────────────────────────────────────────
for side, ex in [(-1, CX-100), (1, CX+100)]:
    brow = [
        (ex - side*80, EY - ER - 10),
        (ex + side*15, EY - ER - 40),
        (ex + side*15, EY - ER - 18),
        (ex - side*80, EY - ER + 14),
    ]
    draw.polygon(brow, fill=rgba(OUTLINE))
    inner = [(cx + side*3, cy+4) for cx,cy in brow]
    draw.polygon(inner, fill=rgba(PINK))

# ── Forehead cracks / circuit ─────────────────────────────────────────────────
crack1 = [(CX+8,CY-185),(CX+22,CY-140),(CX+8,CY-110),(CX+18,CY-70)]
crack2 = [(CX-40,CY-160),(CX-20,CY-130),(CX-30,CY-100)]
for crack in [crack1, crack2]:
    draw.line(crack, fill=(*CYAN, 90), width=9)
    draw.line(crack, fill=(*CYAN, 200), width=4)

# small circuit nodes on forehead
for px,py in [(CX-70,CY-155),(CX+60,CY-145),(CX+30,CY-60)]:
    draw.ellipse([px-7,py-7,px+7,py+7], fill=(*CYAN,200))
    draw.line([(px,py),(px+30,py)], fill=(*CYAN,120), width=3)

# ── Neon skull outline glow ───────────────────────────────────────────────────
glow3 = Image.new("RGBA",(SIZE,SIZE),(0,0,0,0))
gd3   = ImageDraw.Draw(glow3)
gd3.ellipse([CX-CR-20, CY-CRY-20, CX+CR+20, CY+CRY+20],
            fill=(*PURPLE, 40))
glow3 = glow3.filter(ImageFilter.GaussianBlur(22))
img   = Image.alpha_composite(img, glow3)
draw  = ImageDraw.Draw(img)

# ── Neon border ───────────────────────────────────────────────────────────────
draw.rounded_rectangle([5,5,SIZE-5,SIZE-5],   radius=197, outline=(*PINK,240),   width=7)
draw.rounded_rectangle([18,18,SIZE-18,SIZE-18], radius=186, outline=(*CYAN,140), width=4)
draw.rounded_rectangle([30,30,SIZE-30,SIZE-30], radius=176, outline=(*PURPLE,60),width=2)

# ── Corner neon dots ──────────────────────────────────────────────────────────
for cx2,cy2,col in [(80,80,CYAN),(SIZE-80,80,PINK),(80,SIZE-80,PINK),(SIZE-80,SIZE-80,CYAN)]:
    draw.ellipse([cx2-12,cy2-12,cx2+12,cy2+12], fill=(*col,255))
    draw.ellipse([cx2-6,cy2-6,cx2+6,cy2+6], fill=rgba(WHITE))

img.save(OUT)
print(f"Saved {OUT}")

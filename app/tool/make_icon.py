"""Generates the By the People app icon (crowd ring around a check mark).
Geometry mirrors lib/core/widgets/brand_mark.dart. Run: python3 tool/make_icon.py"""
import math, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # supersample canvas, downscaled to 1024
K = S / 1024.0
OUT = os.path.join(os.path.dirname(__file__), '..')

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def background():
    # diagonal ember gradient with a dark corner, like the app's hero
    img = Image.new('RGB', (S, S))
    px = img.load()
    stops = [(0.0, (255, 190, 80)), (0.45, (255, 90, 54)), (0.8, (190, 40, 24)), (1.0, (40, 14, 18))]
    for y in range(0, S):
        for x in range(0, S, 1):
            t = (x * 0.35 + y * 0.65) / S
            for i in range(len(stops) - 1):
                if stops[i][0] <= t <= stops[i + 1][0]:
                    u = (t - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
                    px[x, y] = lerp(stops[i][1], stops[i + 1][1], u)
                    break
    return img

def person(draw, cx, cy, theta, head_r, ring_r, color):
    u = (math.sin(theta), -math.cos(theta))          # outward
    t = (math.cos(theta), math.sin(theta))           # tangent
    hx, hy = cx + u[0] * (ring_r + 50 * K), cy + u[1] * (ring_r + 50 * K)
    draw.ellipse([hx - head_r, hy - head_r, hx + head_r, hy + head_r], fill=color)
    bx, by = cx + u[0] * (ring_r - 52 * K), cy + u[1] * (ring_r - 52 * K)
    rs = 80 * K
    pts = []
    for i in range(0, 61):
        phi = math.pi * i / 60
        pts.append((bx + t[0] * rs * math.cos(phi) + u[0] * rs * 0.95 * math.sin(phi),
                    by + t[1] * rs * math.cos(phi) + u[1] * rs * 0.95 * math.sin(phi)))
    draw.polygon(pts, fill=color)

def main():
    img = background().convert('RGBA')
    c = S / 2

    # soft glow behind the ring
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([c - 400 * K, c - 400 * K, c + 400 * K, c + 400 * K], fill=(255, 235, 200, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(70 * K))
    img = Image.alpha_composite(img, glow)

    # shadow of the crowd
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    ring = 262 * K
    for k in range(8):
        person(sd, c, c + 14 * K, math.radians(k * 45), 50 * K, ring, (60, 10, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * K))
    img = Image.alpha_composite(img, shadow)

    # the crowd: 8 people facing outward, alternating cream / white
    crowd = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    cd = ImageDraw.Draw(crowd)
    for k in range(8):
        col = (255, 255, 255, 255) if k % 2 == 0 else (255, 236, 214, 255)
        person(cd, c, c, math.radians(k * 45), 50 * K, ring, col)
    img = Image.alpha_composite(img, crowd)

    # centre: a ballot / check seal
    seal = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sl = ImageDraw.Draw(seal)
    r0 = 128 * K
    sl.ellipse([c - r0, c - r0 + 8 * K, c + r0, c + r0 + 8 * K], fill=(70, 12, 0, 90))
    seal = seal.filter(ImageFilter.GaussianBlur(10 * K))
    img = Image.alpha_composite(img, seal)
    d = ImageDraw.Draw(img)
    d.ellipse([c - r0, c - r0, c + r0, c + r0], fill=(23, 24, 26, 255))
    w = int(30 * K)
    pts = [(c - 58 * K, c + 4 * K), (c - 16 * K, c + 46 * K), (c + 62 * K, c - 44 * K)]
    d.line(pts, fill=(200, 219, 122, 255), width=w, joint='curve')
    for p in (pts[0], pts[2]):
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=(200, 219, 122, 255))

    out = img.convert('RGB').resize((1024, 1024), Image.LANCZOS)
    out.save(os.path.join(OUT, 'tool', 'icon_1024.png'))
    print('icon_1024.png written')

main()

"""
Generate launcher PNG icons for the Zero Cost Holding App.
Design: deep navy background + rising chart line + seed sprouting (stem + leaves)
Color palette:
  Background: #0D1B2A -> #060E1A gradient
  Chart line: #00C896 (bright green)
  Leaves:     #00C896 / #39E0B4
  Seed:       #D4A017 (gold)
  Arrow:      #D4A017 (gold)
"""

import math
from PIL import Image, ImageDraw

SIZES = {
    "mipmap-mdpi":    48,
    "mipmap-hdpi":    72,
    "mipmap-xhdpi":   96,
    "mipmap-xxhdpi":  144,
    "mipmap-xxxhdpi": 192,
}

BASE = "/Users/xiaoxiao/personal-JavaProject/stock-seed-app/android/app/src/main/res"


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    s = size / 108.0  # scale factor (design space is 108x108)

    # ── Background gradient (top-left dark blue -> bottom-right near-black) ──
    bg_top    = (13, 27, 42)
    bg_bottom = (6,  14, 26)
    for y in range(size):
        t = y / size
        r, g, b = lerp_color(bg_top, bg_bottom, t)
        draw.line([(0, y), (size - 1, y)], fill=(r, g, b, 255))

    # Rounded-rect clip: radius = size * 0.22 (Android adaptive icon safe zone)
    radius = int(size * 0.22)
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    img.putalpha(mask)

    # Re-draw gradient inside rounded rect
    bg_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg_img)
    for y in range(size):
        t = y / size
        r, g, b = lerp_color(bg_top, bg_bottom, t)
        bg_draw.line([(0, y), (size - 1, y)], fill=(r, g, b, 255))
    bg_img.putalpha(mask)
    img = bg_img

    draw = ImageDraw.Draw(img, "RGBA")

    # ── Helpers ──
    def sc(v):
        return v * s  # scale a design-space value

    def pt(x, y):
        return (x * s, y * s)

    # ── Card background (subtle inner plate) ──
    pad = sc(20)
    cr = sc(7)
    draw.rounded_rectangle(
        [pad, pad, size - pad, size - pad],
        radius=int(cr),
        fill=(255, 255, 255, 18),
        outline=(255, 255, 255, 40),
        width=max(1, int(sc(0.8))),
    )

    # ── Ground baseline ──
    gold = (212, 160, 23)
    lw = max(1, int(sc(2.2)))
    draw.line([pt(26, 73), pt(82, 73)], fill=gold + (255,), width=lw)

    # ── Stem ──
    green  = (0, 200, 150)
    lw_stem = max(2, int(sc(3)))
    draw.line([pt(54, 73), pt(54, 49)], fill=green + (255,), width=lw_stem)

    # ── Left leaf (bezier approximated as polygon) ──
    def bezier_pts(p0, p1, p2, p3, steps=20):
        pts = []
        for i in range(steps + 1):
            t = i / steps
            mt = 1 - t
            x = mt**3*p0[0] + 3*mt**2*t*p1[0] + 3*mt*t**2*p2[0] + t**3*p3[0]
            y = mt**3*p0[1] + 3*mt**2*t*p1[1] + 3*mt*t**2*p2[1] + t**3*p3[1]
            pts.append((x * s, y * s))
        return pts

    # left leaf: tip at (54,62) curves to (40,50), back via (50,48) to (54,56)
    left_leaf = (
        bezier_pts((54,62),(54,62),(42,58),(40,50))
        + bezier_pts((40,50),(40,50),(50,48),(54,56))
        + [pt(54, 62)]
    )
    draw.polygon(left_leaf, fill=green + (230,))

    # right leaf: (54,56) curves to (68,44), back via (58,42) to (54,50)
    right_leaf = (
        bezier_pts((54,56),(54,56),(66,52),(68,44))
        + bezier_pts((68,44),(68,44),(58,42),(54,50))
        + [pt(54, 56)]
    )
    green2 = (57, 224, 180)
    draw.polygon(right_leaf, fill=green2 + (230,))

    # ── Seed (golden ellipse at baseline) ──
    ex, ey = 54 * s, 73 * s
    ew, eh = 14 * s, 9 * s
    draw.ellipse(
        [(ex - ew/2, ey - eh/2), (ex + ew/2, ey + eh/2)],
        fill=(212, 160, 23, 255),
        outline=(253, 230, 138, 255),
        width=max(1, int(sc(1))),
    )

    # ── Rising chart line (glow layer first, then solid) ──
    chart_pts_ds = [(34,64), (44,56), (54,58), (68,44), (78,36)]
    chart_pts = [pt(x, y) for x, y in chart_pts_ds]

    # glow
    glow_lw = max(3, int(sc(5.5)))
    for i in range(len(chart_pts) - 1):
        draw.line([chart_pts[i], chart_pts[i+1]], fill=(57, 224, 180, 100), width=glow_lw)

    # solid line
    line_lw = max(2, int(sc(3)))
    for i in range(len(chart_pts) - 1):
        draw.line([chart_pts[i], chart_pts[i+1]], fill=green + (255,), width=line_lw)

    # chart nodes
    node_r = sc(3)
    for i, (x, y) in enumerate(chart_pts_ds):
        cx, cy = x * s, y * s
        if i == len(chart_pts_ds) - 1:
            # top node: larger gold ring
            outer = sc(3.5)
            inner = sc(1.8)
            draw.ellipse([(cx-outer, cy-outer), (cx+outer, cy+outer)], fill=(253, 230, 138, 255))
            draw.ellipse([(cx-inner, cy-inner), (cx+inner, cy+inner)], fill=(212, 160, 23, 255))
        elif i == len(chart_pts_ds) - 2:
            draw.ellipse([(cx-node_r, cy-node_r), (cx+node_r, cy+node_r)], fill=(212, 160, 23, 255))
        else:
            draw.ellipse([(cx-node_r, cy-node_r), (cx+node_r, cy+node_r)], fill=green + (255,))

    # ── Up-arrow at top node ──
    ax, ay = 78 * s, 36 * s
    aw = sc(4)
    ah = sc(5)
    alw = max(1, int(sc(2.5)))
    draw.line([(ax, ay), (ax - aw, ay + ah)], fill=gold + (255,), width=alw)
    draw.line([(ax, ay), (ax + aw, ay + ah)], fill=gold + (255,), width=alw)
    draw.line([(ax, ay), (ax, ay + ah * 1.6)], fill=gold + (255,), width=alw)

    return img


def main():
    import os
    for folder, size in SIZES.items():
        icon = draw_icon(size)
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            path = os.path.join(BASE, folder, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            icon.save(path, "PNG")
            print(f"  saved {path} ({size}x{size})")


if __name__ == "__main__":
    main()

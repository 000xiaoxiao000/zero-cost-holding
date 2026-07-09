"""
Generate launcher PNG icons for the Stock Seed App.
Design: "SeedChart"
  Three bullish candlestick bars rising left to right,
  with a seedling sprouting from the tallest candle.
  Deep indigo-to-navy background, teal + gold palette.
"""

import os
from PIL import Image, ImageDraw

SIZES = {
    "mipmap-mdpi":    48,
    "mipmap-hdpi":    72,
    "mipmap-xhdpi":   96,
    "mipmap-xxhdpi":  144,
    "mipmap-xxxhdpi": 192,
}

BASE = "/Users/xiaoxiao/personal-JavaProject/stock-seed-app/android/app/src/main/res"
DS = 108.0


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def build_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def bezier(p0, p1, p2, p3, s, steps=24):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        x = mt**3*p0[0] + 3*mt**2*t*p1[0] + 3*mt*t**2*p2[0] + t**3*p3[0]
        y = mt**3*p0[1] + 3*mt**2*t*p1[1] + 3*mt*t**2*p2[1] + t**3*p3[1]
        pts.append((x * s, y * s))
    return pts


def draw_icon(size):
    s = size / DS

    def sc(v):
        return v * s

    def pt(x, y):
        return (x * s, y * s)

    # Background: vertical scanline gradient, dark indigo top -> near-black bottom
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    bg_draw = ImageDraw.Draw(bg)
    c_top = (26, 16, 64)
    c_bot = (6, 13, 30)
    for y in range(size):
        t = y / max(1, size - 1)
        col = lerp_color(c_top, c_bot, t) + (255,)
        bg_draw.line([(0, y), (size - 1, y)], fill=col)

    radius = int(size * 0.22)
    bg.putalpha(build_mask(size, radius))
    img = bg
    draw = ImageDraw.Draw(img, "RGBA")

    TEAL  = (0, 212, 160)
    TEAL2 = (0, 158, 120)
    TEALL = (57, 232, 192)
    GOLD  = (245, 197, 24)
    GOLD2 = (212, 160, 16)
    W     = (255, 255, 255)

    lw1 = max(1, int(sc(2)))
    cr  = max(1, int(sc(2)))

    def candle(x_cx, body_top, body_bot, wick_top, wick_bot, fill_col):
        hw = 5
        wx = x_cx * s
        draw.line([pt(x_cx, wick_top), pt(x_cx, body_top)],  fill=W + (100,), width=lw1)
        draw.line([pt(x_cx, body_bot), pt(x_cx, wick_bot)],   fill=W + (70,),  width=lw1)
        x1, y1 = (x_cx - hw) * s, body_top * s
        x2, y2 = (x_cx + hw) * s, body_bot * s
        draw.rounded_rectangle([x1, y1, x2, y2], radius=cr, fill=fill_col + (255,))
        shine_x = x1 + (x2 - x1) * 0.25
        draw.line([(shine_x, y1 + sc(2)), (shine_x, y2 - sc(2))],
                  fill=W + (50,), width=max(1, int(sc(1.3))))
        draw.rounded_rectangle([x1, y1, x2, y2], radius=cr,
                                outline=W + (25,), width=max(1, int(sc(0.6))))

    # Three rising candles
    candle(32, 62, 76, 58, 76, TEAL2)
    candle(54, 52, 76, 46, 76, TEAL)
    candle(76, 44, 76, 36, 76, GOLD)

    # Seedling on tallest candle (candle 3 wick tip at y=36)
    stem_x = sc(76)
    draw.line([(stem_x, sc(36)), (stem_x, sc(23))],
              fill=TEAL + (255,), width=max(2, int(sc(2.5))))

    left_leaf = (
        bezier((76, 30), (76, 30), (66, 27), (63, 21), s)
        + bezier((63, 21), (63, 21), (72, 19), (76, 26), s)
        + [(stem_x, sc(30))]
    )
    draw.polygon(left_leaf, fill=TEAL + (235,))

    right_leaf = (
        bezier((76, 26), (76, 26), (86, 23), (89, 17), s)
        + bezier((89, 17), (89, 17), (80, 15), (76, 22), s)
        + [(stem_x, sc(26))]
    )
    draw.polygon(right_leaf, fill=TEALL + (235,))

    # Gold seed dot at stem base
    ex, ey = stem_x, sc(37.5)
    ew, eh = sc(3.2), sc(2.2)
    draw.ellipse([(ex - ew, ey - eh), (ex + ew, ey + eh)], fill=GOLD + (255,))

    # Baseline rule
    draw.line([pt(20, 78), pt(88, 78)], fill=W + (55,), width=max(1, int(sc(1))))

    return img


def main():
    for folder, size in SIZES.items():
        icon = draw_icon(size)
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            path = os.path.join(BASE, folder, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            icon.save(path, "PNG")
            print(f"  saved {path} ({size}x{size})")


if __name__ == "__main__":
    main()

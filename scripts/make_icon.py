#!/usr/bin/env python3
"""Renders Vault's app icon (light, dark and tinted appearances) as 1024px PNGs.

    python3 scripts/make_icon.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Vault", "Resources", "Assets.xcassets", "AppIcon.appiconset")
S = 4096  # supersampled canvas
FINAL = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def gradient(size, top, bottom, angle=0.0):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(0, size):
            t = (y * math.cos(angle) + x * math.sin(angle)) / size
            t = max(0.0, min(1.0, t))
            px[x, y] = lerp(top, bottom, t)
    return img


def fast_gradient(size, top, bottom):
    col = Image.new("RGBA", (1, size))
    for y in range(size):
        col.putpixel((0, y), lerp(top, bottom, y / (size - 1)))
    return col.resize((size, size))


def bezier(p0, p1, p2, p3, n=200):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def shield_points(cx, top, w, h):
    """A classic shield: gently arched top, straight-ish sides, pointed base."""
    left, right = cx - w / 2, cx + w / 2
    shoulder = top + h * 0.10
    pts = []
    pts += bezier((left, shoulder), (cx - w * 0.22, top + h * 0.02), (cx - w * 0.1, top), (cx, top - h * 0.015))
    pts += bezier((cx, top - h * 0.015), (cx + w * 0.1, top), (cx + w * 0.22, top + h * 0.02), (right, shoulder))[1:]
    pts += bezier((right, shoulder), (right, top + h * 0.55), (cx + w * 0.30, top + h * 0.82), (cx, top + h))[1:]
    pts += bezier((cx, top + h), (cx - w * 0.30, top + h * 0.82), (left, top + h * 0.55), (left, shoulder))[1:]
    return pts


def render(variant):
    if variant == "light":
        bg = fast_gradient(S, (88, 140, 255, 255), (52, 58, 214, 255))
        shield_fill = fast_gradient(S, (255, 255, 255, 255), (226, 232, 255, 255))
        lock_color = (64, 92, 235, 255)
        shadow_alpha = 90
    elif variant == "dark":
        bg = fast_gradient(S, (28, 30, 38, 255), (8, 9, 12, 255))
        shield_fill = fast_gradient(S, (104, 150, 255, 255), (64, 64, 230, 255))
        lock_color = (255, 255, 255, 255)
        shadow_alpha = 160
    else:  # tinted: grayscale, the system applies the tint
        bg = Image.new("RGBA", (S, S), (0, 0, 0, 255))
        shield_fill = fast_gradient(S, (255, 255, 255, 255), (190, 190, 190, 255))
        lock_color = (40, 40, 40, 255)
        shadow_alpha = 0

    img = bg.copy()
    cx = S / 2
    w, h = S * 0.56, S * 0.64
    top = S * 0.17
    pts = shield_points(cx, top, w, h)

    if shadow_alpha:
        shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).polygon([(x, y + S * 0.02) for x, y in pts], fill=(0, 0, 30, shadow_alpha))
        shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.025))
        img = Image.alpha_composite(img, shadow)

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    img.paste(shield_fill, (0, 0), mask)

    # Lock: shackle + body with keyhole.
    d = ImageDraw.Draw(img)
    body_w, body_h = S * 0.24, S * 0.19
    body_top = S * 0.47
    bx0, bx1 = cx - body_w / 2, cx + body_w / 2
    sh_w = S * 0.15
    stroke = S * 0.036
    d.arc([cx - sh_w / 2, body_top - S * 0.14, cx + sh_w / 2, body_top + S * 0.02], 180, 360, fill=lock_color, width=int(stroke))
    d.line([(cx - sh_w / 2 + stroke / 2, body_top - S * 0.06), (cx - sh_w / 2 + stroke / 2, body_top + 4)], fill=lock_color, width=int(stroke))
    d.line([(cx + sh_w / 2 - stroke / 2, body_top - S * 0.06), (cx + sh_w / 2 - stroke / 2, body_top + 4)], fill=lock_color, width=int(stroke))
    d.rounded_rectangle([bx0, body_top, bx1, body_top + body_h], radius=S * 0.035, fill=lock_color)
    hole = (cx, body_top + body_h * 0.42)
    hole_color = (255, 255, 255, 255) if variant == "light" else ((70, 80, 230, 255) if variant == "dark" else (220, 220, 220, 255))
    d.ellipse([hole[0] - S * 0.022, hole[1] - S * 0.022, hole[0] + S * 0.022, hole[1] + S * 0.022], fill=hole_color)
    d.polygon([(hole[0] - S * 0.012, hole[1]), (hole[0] + S * 0.012, hole[1]), (hole[0] + S * 0.007, hole[1] + S * 0.055), (hole[0] - S * 0.007, hole[1] + S * 0.055)], fill=hole_color)

    # Soft top highlight on the shield (light/dark), for a layered, glassy feel.
    if variant != "tinted":
        hl = Image.new("RGBA", (S, S), (255, 255, 255, 0))
        hl_mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(hl_mask).polygon(pts, fill=70 if variant == "light" else 50)
        cut = Image.new("L", (S, S), 0)
        ImageDraw.Draw(cut).rectangle([0, 0, S, top + h * 0.38], fill=255)
        cut = cut.filter(ImageFilter.GaussianBlur(S * 0.06))
        hl_mask = Image.composite(hl_mask, Image.new("L", (S, S), 0), cut)
        img.paste(Image.new("RGBA", (S, S), (255, 255, 255, 255)), (0, 0), hl_mask)

    return img.convert("RGB").resize((FINAL, FINAL), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    for variant in ("light", "dark", "tinted"):
        render(variant).save(os.path.join(OUT, f"AppIcon-{variant}.png"), optimize=True)
    print("Wrote icons to", OUT)


if __name__ == "__main__":
    main()

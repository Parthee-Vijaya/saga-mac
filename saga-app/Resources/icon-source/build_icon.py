#!/usr/bin/env python3
"""
Bygger Saga app-ikon i alle 10 størrelser via Pillow + samler ICNS.

Design:
  - Squircle med Apple's signature corner radius (~22% af canvas)
  - Sky-blue gradient baggrund (matcher SagaColors.accentGradient)
  - Hvid omvendt trekant centreret (samme form som menubar-ikonet)
  - Subtle dybde-overlay (top-light → bottom-shadow)
  - Subtle skygge på trekanten

Brug:
  python3 build_icon.py
  iconutil --convert icns -o ../AppIcon.icns saga-icon.iconset
"""
from PIL import Image, ImageDraw, ImageFilter
import os
import math

# Saga brand colors (matcher SagaColors fra SagaTheme.swift)
ACCENT_LIGHT = (102, 179, 255, 255)  # 0.40, 0.70, 1.0 → #66B3FF
ACCENT_DEEP = (51, 140, 242, 255)    # 0.20, 0.55, 0.95 → #338CF2
WHITE = (255, 255, 255, 255)


def render_icon(size: int) -> Image.Image:
    """Render Saga-ikonet i given pixel-størrelse."""
    # Canvas (RGBA, transparent baggrund så squircle-corners er gennemsigtige)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Squircle-mask. Apple's squircle er IKKE en simpel rounded-rect — det er
    # en superellipse. Men en rounded-rect med rx=22% er praktisk talt umulig
    # at skelne fra ægte squircle ved typiske app-icon-størrelser.
    radius = int(size * 0.22)  # 22% corner radius → matcher iOS/macOS

    # Tegn squircle-baggrund med vertikal sky-blue gradient (top-left light → bottom-right deep)
    # Vi laver gradient ved at tegne linjer pixel-for-pixel
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    for y in range(size):
        for x in range(size):
            # Diagonal gradient (top-left til bottom-right)
            t = (x + y) / (2 * size)  # 0.0 → 1.0
            r = int(ACCENT_LIGHT[0] + (ACCENT_DEEP[0] - ACCENT_LIGHT[0]) * t)
            g = int(ACCENT_LIGHT[1] + (ACCENT_DEEP[1] - ACCENT_LIGHT[1]) * t)
            b = int(ACCENT_LIGHT[2] + (ACCENT_DEEP[2] - ACCENT_LIGHT[2]) * t)
            bg.putpixel((x, y), (r, g, b, 255))

    # Mask: squircle (rounded rectangle med rx=22%)
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(
        [(0, 0), (size - 1, size - 1)],
        radius=radius,
        fill=255,
    )

    # Maskér gradient med squircle
    img.paste(bg, (0, 0), mask)

    # Subtle dybde-overlay (vertikal: top hvid 8%, bunden sort 8%)
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    for y in range(size):
        t = y / size  # 0 = top, 1 = bottom
        # Top-light (hvid 8% → 0%) eller bottom-shadow (0% → sort 8%)
        if t < 0.5:
            alpha = int((0.5 - t) * 2 * 0.08 * 255)
            color = (255, 255, 255, alpha)
        else:
            alpha = int((t - 0.5) * 2 * 0.08 * 255)
            color = (0, 0, 0, alpha)
        overlay_draw.line([(0, y), (size, y)], fill=color)

    # Maskér overlay med squircle
    overlay_masked = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    overlay_masked.paste(overlay, (0, 0), mask)
    img = Image.alpha_composite(img, overlay_masked)

    # Omvendt trekant (peger nedad, ligesidet, ~50% bredde)
    triangle_width = int(size * 0.50)
    triangle_height = int(triangle_width * math.sqrt(3) / 2)  # ligesidet trekant
    cx = size // 2
    # Vertikalt centreret
    top_y = (size - triangle_height) // 2
    bottom_y = top_y + triangle_height
    left_x = cx - triangle_width // 2
    right_x = cx + triangle_width // 2

    # Tegn trekanten på et separat lag så vi kan blur'e dens skygge
    # Skygge-lag (offset 4px nedad, blur 8px, 25% sort)
    shadow_offset = max(2, size // 200)
    shadow_blur_radius = max(2, size // 100)
    shadow_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)
    shadow_draw.polygon(
        [
            (left_x, top_y + shadow_offset),
            (right_x, top_y + shadow_offset),
            (cx, bottom_y + shadow_offset),
        ],
        fill=(0, 0, 0, 64),  # 25% sort
    )
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=shadow_blur_radius))

    # Maskér skyggen så den ikke går uden for squircle
    shadow_masked = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_masked.paste(shadow_layer, (0, 0), mask)
    img = Image.alpha_composite(img, shadow_masked)

    # Selve trekanten (hvid)
    triangle_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    triangle_draw = ImageDraw.Draw(triangle_layer)
    triangle_draw.polygon(
        [(left_x, top_y), (right_x, top_y), (cx, bottom_y)],
        fill=WHITE,
    )
    img = Image.alpha_composite(img, triangle_layer)

    return img


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    iconset_dir = os.path.join(here, "saga-icon.iconset")
    os.makedirs(iconset_dir, exist_ok=True)

    # Apple's required icon sizes
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    for size, filename in sizes:
        print(f"Rendering {size}x{size} → {filename}")
        img = render_icon(size)
        img.save(os.path.join(iconset_dir, filename), "PNG", optimize=True)

    print(f"\n✓ Iconset bygget i {iconset_dir}")
    print(f"  Bygg ICNS med: iconutil --convert icns -o ../AppIcon.icns saga-icon.iconset")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build Galio's AppIcon.appiconset from the original source artwork (assets/icon-source.png).

The source is an original generated illustration (stone shield with a rune line; no Riot
artwork). Steps: find the tile on the white canvas, crop it, re-mask it with a clean rounded
rectangle on a transparent 1024 canvas (macOS grid: 824 px tile, 100 px margin), then export
every size required by the macOS app icon set.
"""
import json
import pathlib
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "icon-source.png"
OUT = ROOT / "Galio" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def tile_bounds(img: Image.Image):
    rgb = img.convert("RGB")
    bg = Image.new("RGB", rgb.size, (255, 255, 255))
    diff = ImageChops.difference(rgb, bg).convert("L").point(lambda v: 255 if v > 40 else 0)
    return diff.getbbox()


def build_master(src: Image.Image) -> Image.Image:
    box = tile_bounds(src) or (0, 0, src.width, src.height)
    # Trim a few pixels so no white anti-aliasing from the source corners survives.
    inset = int((box[2] - box[0]) * 0.012)
    tile = src.crop((box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset)).convert("RGBA")
    size, margin = 1024, 100
    inner = size - 2 * margin
    tile = tile.resize((inner, inner), Image.LANCZOS)
    scale = 4
    mask = Image.new("L", (inner * scale, inner * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner * scale - 1, inner * scale - 1), radius=int(inner * 0.225 * scale), fill=255)
    mask = mask.resize((inner, inner), Image.LANCZOS)
    tile.putalpha(mask)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sh = Image.new("RGBA", (inner, inner), (0, 0, 0, 110))
    sh.putalpha(mask.point(lambda v: int(v * 0.43)))
    shadow.paste(sh, (margin, margin + 12), sh)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(tile, (margin, margin))
    return canvas


def main():
    src = Image.open(sys.argv[1] if len(sys.argv) > 1 else SRC)
    master = build_master(src)
    OUT.mkdir(parents=True, exist_ok=True)
    images = []
    for pt, scale in SIZES:
        px = pt * scale
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        master.resize((px, px), Image.LANCZOS).save(OUT / name, optimize=True)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    (OUT / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (OUT.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    master.save(ROOT / "assets" / "icon-1024.png", optimize=True)
    print("wrote", OUT)


if __name__ == "__main__":
    main()

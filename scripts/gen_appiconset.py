#!/usr/bin/env python3
"""Generate deterministic iOS and macOS app-icon catalogs.

The iOS images are deliberately opaque: App Store Connect rejects app icons
with an alpha channel. macOS keeps the transparent squircle treatment.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow required: python3 -m pip install Pillow", file=sys.stderr)
    sys.exit(1)

THOX_GREEN = (5, 164, 81, 255)
NEUTRAL_DARK = (12, 14, 18, 255)

# This app is iPhone-only; iPad slots would be unused asset variants.
IOS_PLAN = (
    ("iphone", "20", 2, "Icon-20@2x.png"),
    ("iphone", "20", 3, "Icon-20@3x.png"),
    ("iphone", "29", 2, "Icon-29@2x.png"),
    ("iphone", "29", 3, "Icon-29@3x.png"),
    ("iphone", "40", 2, "Icon-40@2x.png"),
    ("iphone", "40", 3, "Icon-40@3x.png"),
    ("iphone", "60", 2, "Icon-60@2x.png"),
    ("iphone", "60", 3, "Icon-60@3x.png"),
    ("ios-marketing", "1024", 1, "Icon-1024.png"),
)

MAC_PLAN = (
    ("16", 1, "icon_16x16.png"),
    ("16", 2, "icon_16x16@2x.png"),
    ("32", 1, "icon_32x32.png"),
    ("32", 2, "icon_32x32@2x.png"),
    ("128", 1, "icon_128x128.png"),
    ("128", 2, "icon_128x128@2x.png"),
    ("256", 1, "icon_256x256.png"),
    ("256", 2, "icon_256x256@2x.png"),
    ("512", 1, "icon_512x512.png"),
    ("512", 2, "icon_512x512@2x.png"),
)


def draw_chip_mark(side: int, *, opaque: bool) -> Image.Image:
    background = THOX_GREEN if opaque else (0, 0, 0, 0)
    image = Image.new("RGBA", (side, side), background)
    draw = ImageDraw.Draw(image)
    if not opaque:
        draw.rounded_rectangle(
            (0, 0, side - 1, side - 1), radius=int(side * 0.22), fill=THOX_GREEN
        )

    slab_radius = int(side * 0.06)
    pad = int(side * 0.22)
    gap = int(side * 0.08)
    full_width = side - 2 * pad
    cap_width = int(full_width * 0.55)
    slab_height = int(side * 0.10)
    cap_x = (side - cap_width) // 2
    cap_y = int(side * 0.30)
    draw.rounded_rectangle(
        (cap_x, cap_y, cap_x + cap_width, cap_y + slab_height),
        radius=slab_radius,
        fill=NEUTRAL_DARK,
    )
    middle_y = cap_y + slab_height + gap
    draw.rounded_rectangle(
        (pad, middle_y, pad + full_width, middle_y + slab_height),
        radius=slab_radius,
        fill=NEUTRAL_DARK,
    )
    bottom_y = middle_y + slab_height + gap
    draw.rounded_rectangle(
        (pad, bottom_y, pad + full_width, bottom_y + slab_height),
        radius=slab_radius,
        fill=NEUTRAL_DARK,
    )
    return image.convert("RGB") if opaque else image


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def reset_directory(path: Path) -> None:
    shutil.rmtree(path, ignore_errors=True)
    path.mkdir(parents=True)


def write_ios_iconset(directory: Path) -> None:
    reset_directory(directory)
    master = draw_chip_mark(1024, opaque=True)
    images = []
    for idiom, logical_size, scale, filename in IOS_PLAN:
        pixels = round(float(logical_size) * scale)
        master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(
            directory / filename, format="PNG", optimize=True
        )
        images.append(
            {
                "filename": filename,
                "idiom": idiom,
                "size": f"{logical_size}x{logical_size}",
                "scale": f"{scale}x",
            }
        )
    write_json(directory / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})
    print(f"wrote {directory} ({len(images)} opaque variants)")


def write_mac_iconset(directory: Path, master: Image.Image) -> None:
    reset_directory(directory)
    images = []
    for logical_size, scale, filename in MAC_PLAN:
        pixels = int(logical_size) * scale
        master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(
            directory / filename, format="PNG", optimize=True
        )
        images.append(
            {
                "filename": filename,
                "idiom": "mac",
                "size": f"{logical_size}x{logical_size}",
                "scale": f"{scale}x",
            }
        )
    write_json(directory / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})
    print(f"wrote {directory} ({len(images)} variants)")


def write_icns(mac_iconset: Path, destination: Path) -> None:
    with tempfile.TemporaryDirectory() as temporary:
        iconset = Path(temporary) / "AppIcon.iconset"
        shutil.copytree(mac_iconset, iconset, ignore=shutil.ignore_patterns("Contents.json"))
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(destination)],
            check=True,
        )
    print(f"wrote {destination}")


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    resources = root / "Resources"
    assets = root / "Assets.xcassets"
    resources.mkdir(exist_ok=True)
    assets.mkdir(exist_ok=True)

    # Always redraw the master so generator changes propagate to every output.
    mac_master = draw_chip_mark(1024, opaque=False)
    mac_master.save(resources / "AppIcon-master.png", format="PNG", optimize=True)
    write_ios_iconset(resources / "AppIcon.appiconset")
    write_ios_iconset(assets / "AppIcon.appiconset")
    write_mac_iconset(assets / "AppIcon-mac.appiconset", mac_master)
    write_icns(assets / "AppIcon-mac.appiconset", resources / "AppIcon.icns")
    write_json(assets / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    print("done")


if __name__ == "__main__":
    main()

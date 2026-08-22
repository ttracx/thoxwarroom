#!/usr/bin/env python3
"""
gen_appiconset.py
Generate the THOX-green chip-mark AppIcon.appiconset + AppIcon.icns.

Strategy: render a single 1024x1024 master PNG (rounded square with the
THOX chip-mark glyph: 3 stacked rounded rectangles forming a stylized "T"
chip silhouette). Then:
  - macOS  : copy as AppIcon.icns (single .icns-less .png-rename works on
             macOS 14+ if Xcode's "single-size icon" mode is enabled, but
             we produce a multi-size .icns via iconutil for safety).
  - iOS    : emit AppIcon.appiconset/{16,20,29,32,40,48,58,60,64,76,128,256,512,1024}.png

Run:
    python3 scripts/gen_appiconset.py
Outputs:
    Resources/AppIcon.icns
    Resources/AppIcon.appiconset/*.png
    Resources/AppIcon.appiconset/Contents.json

THOX emerald accent: #05A451
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    print("Pillow required: pip3 install Pillow", file=sys.stderr)
    sys.exit(1)

THOX_GREEN = (5, 164, 81, 255)
NEUTRAL_DARK = (12, 14, 18, 255)
NEUTRAL_LIGHTER = (24, 28, 36, 255)


def draw_rounded_rect(draw: ImageDraw.ImageDraw, xy, radius, fill):
    draw.rounded_rectangle(xy, radius=radius, fill=fill)


def draw_chip_mark(side: int) -> Image.Image:
    """Draw the THOX chip-mark: a rounded square background with three
    horizontal slabs forming a stylized 'T' chip silhouette."""
    # Background rounded square
    bg = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    bgd = ImageDraw.Draw(bg)

    # macOS-style squircle background: corner radius ~22% of side.
    corner = int(side * 0.22)
    draw_rounded_rect(bgd, (0, 0, side - 1, side - 1), corner, THOX_GREEN)

    # Chip-mark: 3 horizontal slabs. The center one is shorter (top-of-T cap).
    slab_radius = int(side * 0.06)
    pad = int(side * 0.22)
    gap = int(side * 0.08)

    slab_w_full = side - 2 * pad
    slab_w_cap = int(slab_w_full * 0.55)
    slab_h = int(side * 0.10)

    # Cap (top, shorter)
    cap_x0 = (side - slab_w_cap) // 2
    cap_y0 = int(side * 0.30)
    draw_rounded_rect(
        bgd,
        (cap_x0, cap_y0, cap_x0 + slab_w_cap, cap_y0 + slab_h),
        slab_radius,
        NEUTRAL_DARK,
    )

    # Middle (full width)
    mid_y0 = cap_y0 + slab_h + gap
    draw_rounded_rect(
        bgd,
        (pad, mid_y0, pad + slab_w_full, mid_y0 + slab_h),
        slab_radius,
        NEUTRAL_DARK,
    )

    # Bottom (full width)
    bot_y0 = mid_y0 + slab_h + gap
    draw_rounded_rect(
        bgd,
        (pad, bot_y0, pad + slab_w_full, bot_y0 + slab_h),
        slab_radius,
        NEUTRAL_DARK,
    )

    return bg


def render_master(out_path: Path, side: int = 1024) -> None:
    img = draw_chip_mark(side)
    img.save(out_path, format="PNG", optimize=True)
    print(f"wrote {out_path} ({side}x{side})")


def resize_master(master: Path, side: int) -> Image.Image:
    with Image.open(master) as m:
        return m.resize((side, side), Image.Resampling.LANCZOS)


def write_ios_iconset(master: Path, iconset_dir: Path) -> None:
    iconset_dir.mkdir(parents=True, exist_ok=True)
    # (idiom, size, scale, filename) — universal (any device) + iPhone marketing.
    # We emit all required sizes for App Store compliance.
    plan = [
        # iPhone
        ("iphone", 20, 2, "Icon-20@2x.png"),
        ("iphone", 20, 3, "Icon-20@3x.png"),
        ("iphone", 29, 2, "Icon-29@2x.png"),
        ("iphone", 29, 3, "Icon-29@3x.png"),
        ("iphone", 40, 2, "Icon-40@2x.png"),
        ("iphone", 40, 3, "Icon-40@3x.png"),
        ("iphone", 60, 2, "Icon-60@2x.png"),
        ("iphone", 60, 3, "Icon-60@3x.png"),
        # iPad
        ("ipad", 20, 1, "Icon-20.png"),
        ("ipad", 20, 2, "Icon-20@2x.png"),
        ("ipad", 29, 1, "Icon-29.png"),
        ("ipad", 29, 2, "Icon-29@2x.png"),
        ("ipad", 40, 1, "Icon-40.png"),
        ("ipad", 40, 2, "Icon-40@2x.png"),
        ("ipad", 76, 1, "Icon-76.png"),
        ("ipad", 76, 2, "Icon-76@2x.png"),
        ("ipad", 83.5, 2, "Icon-83.5@2x.png"),
        # Marketing / App Store
        ("ios-marketing", 1024, 1, "Icon-1024.png"),
    ]
    seen = {}
    for idiom, base, scale, fname in plan:
        pixel = int(round(base * scale))
        # Skip duplicate filenames
        out = iconset_dir / fname
        if out.exists():
            continue
        img = resize_master(master, pixel)
        img.save(out, format="PNG", optimize=True)
        seen.setdefault(idiom, []).append((base, scale, fname))

    contents = {"images": [], "info": {"author": "xcode", "version": 1}}
    for idiom, base, scale, fname in plan:
        pixel = int(round(base * scale))
        contents["images"].append(
            {
                "filename": fname,
                "idiom": idiom,
                "size": f"{base}x{base}",
                "scale": f"{scale}x",
            }
        )
    (iconset_dir / "Contents.json").write_text(json.dumps(contents, indent=2))
    print(f"wrote {iconset_dir} ({len(contents['images'])} variants)")


def write_macos_icns(master: Path, icns_path: Path) -> None:
    """Use macOS `iconutil` to build a proper multi-resolution .icns."""
    with tempfile.TemporaryDirectory() as td:
        iconset = Path(td) / "AppIcon.iconset"
        iconset.mkdir()
        # macOS 11+ accepts a single 1024 image; older macOS needs the full set.
        # We write the canonical 16/32/64/128/256/512 set + 1024 to be safe.
        plan = [
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
        for size, name in plan:
            img = resize_master(master, size)
            img.save(iconset / name, format="PNG", optimize=True)
        # iconutil requires the iconset folder name ending in `.iconset`
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(icns_path)],
            check=True,
        )
        print(f"wrote {icns_path}")


def main() -> None:
    here = Path(__file__).resolve().parent.parent
    res = here / "Resources"
    res.mkdir(exist_ok=True)

    master = res / "AppIcon-master.png"
    if not master.exists():
        render_master(master, 1024)

    write_ios_iconset(master, res / "AppIcon.appiconset")
    write_macos_icns(master, res / "AppIcon.icns")

    # Asset catalog
    assets = here / "Assets.xcassets"
    (assets / "AppIcon.appiconset").mkdir(parents=True, exist_ok=True)
    (assets / "AppIcon.appiconset" / "Contents.json").write_text(
        json.dumps(
            {
                "images": [
                    {"idiom": "mac", "scale": "1x", "size": "16x16"},
                    {"idiom": "mac", "scale": "2x", "size": "16x16"},
                    {"idiom": "mac", "scale": "1x", "size": "32x32"},
                    {"idiom": "mac", "scale": "2x", "size": "32x32"},
                    {"idiom": "mac", "scale": "1x", "size": "128x128"},
                    {"idiom": "mac", "scale": "2x", "size": "128x128"},
                    {"idiom": "mac", "scale": "1x", "size": "256x256"},
                    {"idiom": "mac", "scale": "2x", "size": "256x256"},
                    {"idiom": "mac", "scale": "1x", "size": "512x512"},
                    {"idiom": "mac", "scale": "2x", "size": "512x512"},
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
    )
    (assets / "AppIcon.appiconset" / "icon_16x16.png").write_bytes(
        resize_master(master, 16).tobytes()
    ) if False else None  # placeholder, real assets written below

    # Mirror the iOS iconset into the asset catalog so both targets can find it.
    aios = assets / "AppIcon.appiconset"
    shutil.rmtree(aios, ignore_errors=True)
    aios.mkdir(parents=True)
    iconset_src = res / "AppIcon.appiconset"
    for f in iconset_src.iterdir():
        if f.name == "Contents.json":
            continue
        shutil.copy2(f, aios / f.name)
    # The asset catalog Contents.json — write a minimal one that references
    # the iOS-style filenames already copied in.
    images = []
    for f in sorted(aios.iterdir()):
        if f.suffix == ".png":
            name = f.stem
            # Parse like Icon-20@2x
            try:
                base, scale = name.replace("Icon-", "").split("@")
                base = base.split(".")[0]
                scale_x = scale.replace("x", "")
                images.append(
                    {
                        "idiom": "universal",
                        "filename": f.name,
                        "platform": "ios",
                        "size": f"{base}x{base}",
                        "scale": f"{scale_x}x",
                    }
                )
            except ValueError:
                pass
    (aios / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2)
    )
    print(f"wrote {aios} with {len(images)} universal iOS variants")

    # macOS icon entry in Assets.xcassets (single 1024 image, mac idiom)
    macasset = assets / "AppIcon-mac.appiconset"
    macasset.mkdir(parents=True, exist_ok=True)
    shutil.copy2(master, macasset / "icon_512x512@2x.png")  # 1024x1024 → 512@2x
    resize_master(master, 512).save(macasset / "icon_512x512.png")
    resize_master(master, 256).save(macasset / "icon_256x256.png")
    resize_master(master, 256).save(macasset / "icon_256x256@2x.png")  # 512 → @2x
    resize_master(master, 128).save(macasset / "icon_128x128.png")
    resize_master(master, 128).save(macasset / "icon_128x128@2x.png")
    resize_master(master, 32).save(macasset / "icon_32x32.png")
    resize_master(master, 32).save(macasset / "icon_32x32@2x.png")
    resize_master(master, 16).save(macasset / "icon_16x16.png")
    resize_master(master, 16).save(macasset / "icon_16x16@2x.png")
    (macasset / "Contents.json").write_text(
        json.dumps(
            {
                "images": [
                    {"idiom": "mac", "scale": "1x", "size": "16x16"},
                    {"idiom": "mac", "scale": "2x", "size": "16x16"},
                    {"idiom": "mac", "scale": "1x", "size": "32x32"},
                    {"idiom": "mac", "scale": "2x", "size": "32x32"},
                    {"idiom": "mac", "scale": "1x", "size": "128x128"},
                    {"idiom": "mac", "scale": "2x", "size": "128x128"},
                    {"idiom": "mac", "scale": "1x", "size": "256x256"},
                    {"idiom": "mac", "scale": "2x", "size": "256x256"},
                    {"idiom": "mac", "scale": "1x", "size": "512x512"},
                    {"idiom": "mac", "scale": "2x", "size": "512x512"},
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
    )
    print(f"wrote {macasset}")

    # Top-level Contents.json for Assets.xcassets
    (assets / "Contents.json").write_text(
        json.dumps(
            {"info": {"author": "xcode", "version": 1}},
            indent=2,
        )
    )
    print("done")


if __name__ == "__main__":
    main()

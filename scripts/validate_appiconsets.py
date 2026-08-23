#!/usr/bin/env python3
"""Validate asset metadata, PNG dimensions, and the iOS no-alpha rule."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def png_info(path: Path) -> tuple[int, int, int]:
    with path.open("rb") as image:
        header = image.read(29)
    if len(header) != 29 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ValueError(f"{path}: not a valid PNG")
    width, height, _, color_type = struct.unpack(">IIBB", header[16:26])
    return width, height, color_type


def validate_catalog(path: Path, *, ios: bool) -> list[str]:
    errors: list[str] = []
    contents_path = path / "Contents.json"
    try:
        contents = json.loads(contents_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"{contents_path}: {error}"]

    assigned: set[str] = set()
    for entry in contents.get("images", []):
        filename = entry.get("filename")
        if not filename:
            errors.append(f"{contents_path}: icon slot has no filename")
            continue
        assigned.add(filename)
        try:
            logical_size = float(entry["size"].split("x", 1)[0])
            scale = int(entry["scale"].removesuffix("x"))
            expected = round(logical_size * scale)
            width, height, color_type = png_info(path / filename)
        except (KeyError, ValueError, OSError) as error:
            errors.append(str(error))
            continue
        if (width, height) != (expected, expected):
            errors.append(f"{path / filename}: {width}x{height}, expected {expected}x{expected}")
        if ios and color_type in (4, 6):
            errors.append(f"{path / filename}: iOS app icon contains an alpha channel")

    pngs = {item.name for item in path.glob("*.png")}
    for filename in sorted(pngs - assigned):
        errors.append(f"{path / filename}: unassigned PNG")
    for filename in sorted(assigned - pngs):
        errors.append(f"{path / filename}: assigned PNG is missing")
    return errors


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    errors = []
    errors.extend(validate_catalog(root / "Assets.xcassets/AppIcon.appiconset", ios=True))
    errors.extend(validate_catalog(root / "Assets.xcassets/AppIcon-mac.appiconset", ios=False))
    if errors:
        print("App icon validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("App icon metadata, dimensions, assignment, and iOS alpha checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Prove that project and asset generation is deterministic across two runs."""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
GENERATED_ROOTS = (
    ROOT / "ThoxWarRoom.xcodeproj",
    ROOT / "Assets.xcassets/AppIcon.appiconset",
    ROOT / "Assets.xcassets/AppIcon-mac.appiconset",
    ROOT / "Resources/AppIcon.appiconset",
)
GENERATED_FILES = (
    ROOT / "Resources/AppIcon-master.png",
    ROOT / "Resources/AppIcon.icns",
)


def snapshot() -> dict[str, str]:
    files = list(GENERATED_FILES)
    for generated_root in GENERATED_ROOTS:
        files.extend(path for path in generated_root.rglob("*") if path.is_file())
    result: dict[str, str] = {}
    for path in sorted(files):
        relative = str(path.relative_to(ROOT))
        result[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_generated_drift.py /path/to/xcodegen", file=sys.stderr)
        return 2
    xcodegen = Path(sys.argv[1]).resolve()
    if not xcodegen.is_file():
        print("ERROR: XcodeGen executable is missing", file=sys.stderr)
        return 2

    before = snapshot()
    subprocess.run([str(xcodegen), "generate", "--quiet"], cwd=ROOT, check=True)
    subprocess.run([sys.executable, "scripts/gen_appiconset.py"], cwd=ROOT, check=True)
    after = snapshot()

    if before != after:
        changed = sorted(set(before) | set(after))
        changed = [path for path in changed if before.get(path) != after.get(path)]
        print("Generated output drift detected:", file=sys.stderr)
        for path in changed:
            print(f"- {path}", file=sys.stderr)
        return 1
    print(f"Generated project and assets are deterministic ({len(after)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

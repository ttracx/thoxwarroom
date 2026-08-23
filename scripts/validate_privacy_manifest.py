#!/usr/bin/env python3
"""Validate the app privacy manifest and its release-bundle placement."""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path


EXPECTED_MANIFEST = {
    "NSPrivacyTracking": False,
    "NSPrivacyTrackingDomains": [],
    "NSPrivacyCollectedDataTypes": [],
    "NSPrivacyAccessedAPITypes": [
        {
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
            "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
        }
    ],
}


def validate(path: Path) -> None:
    if not path.is_file():
        raise ValueError(f"privacy manifest is missing: {path}")

    try:
        with path.open("rb") as manifest_file:
            manifest = plistlib.load(manifest_file)
    except (OSError, plistlib.InvalidFileException) as error:
        raise ValueError(f"privacy manifest is not a valid property list: {path}") from error

    if manifest != EXPECTED_MANIFEST:
        raise ValueError(
            f"privacy manifest declarations differ from the reviewed local-only contract: {path}"
        )


def main() -> int:
    paths = [Path(argument) for argument in sys.argv[1:]]
    if not paths:
        paths = [Path("App/PrivacyInfo.xcprivacy")]

    try:
        for path in paths:
            validate(path)
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    for path in paths:
        print(f"Validated privacy manifest: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

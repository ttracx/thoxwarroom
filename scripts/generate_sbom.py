#!/usr/bin/env python3
"""Generate a deterministic SPDX 2.3 SBOM for the native ThoxWarRoom sources."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import sys


PACKAGE_NAME = re.compile(r'\bname:\s*"([A-Za-z0-9_-]+)"')
LOCAL_DEPENDENCY = re.compile(r'\.package\(path:\s*"([^"]+)"\)')
REMOTE_DEPENDENCY = re.compile(r'\.package\(\s*(?:url|id):')
VERSION = re.compile(r'^\s*MARKETING_VERSION:\s*"?([^"\s]+)"?\s*$', re.MULTILINE)
REVISION = re.compile(r'^[0-9a-f]{40}$')


class SBOMError(ValueError):
    """A non-sensitive source inventory validation failure."""


def _read_text(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise SBOMError(f"Unable to read required source file: {path.name}") from error


def _spdx_id(name: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9.-]", "-", name)
    return f"SPDXRef-Package-{normalized}"


def _iso8601(value: str) -> str:
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise SBOMError("Created timestamp must be valid ISO 8601") from error
    if parsed.tzinfo is None:
        raise SBOMError("Created timestamp must include a timezone")
    return parsed.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def _package_inventory(root: pathlib.Path) -> dict[str, list[str]]:
    packages_root = root / "Packages"
    manifests = sorted(packages_root.glob("*/Package.swift"))
    if not manifests:
        raise SBOMError("No local Swift package manifests found")

    inventory: dict[str, list[str]] = {}
    directory_to_name: dict[pathlib.Path, str] = {}
    manifest_text: dict[str, str] = {}
    for manifest in manifests:
        text = _read_text(manifest)
        if REMOTE_DEPENDENCY.search(text):
            raise SBOMError(
                f"Remote dependency in {manifest.parent.name} requires explicit SBOM modeling"
            )
        match = PACKAGE_NAME.search(text)
        if match is None:
            raise SBOMError(f"Package name missing from {manifest.parent.name}/Package.swift")
        name = match.group(1)
        if name in inventory:
            raise SBOMError(f"Duplicate local package name: {name}")
        inventory[name] = []
        directory_to_name[manifest.parent.resolve()] = name
        manifest_text[name] = text

    for manifest in manifests:
        package_name = directory_to_name[manifest.parent.resolve()]
        for relative_path in LOCAL_DEPENDENCY.findall(manifest_text[package_name]):
            target = (manifest.parent / relative_path).resolve()
            dependency_name = directory_to_name.get(target)
            if dependency_name is None:
                raise SBOMError(
                    f"Local dependency for {package_name} is outside the inventoried package set"
                )
            inventory[package_name].append(dependency_name)
        inventory[package_name].sort()
    return inventory


def build_sbom(root: pathlib.Path, revision: str, created: str) -> dict[str, object]:
    if not REVISION.fullmatch(revision):
        raise SBOMError("Revision must be a lowercase 40-character Git SHA")
    project_text = _read_text(root / "project.yml")
    version_match = VERSION.search(project_text)
    if version_match is None:
        raise SBOMError("MARKETING_VERSION missing from project.yml")
    version = version_match.group(1)
    inventory = _package_inventory(root)

    app_id = _spdx_id("ThoxWarRoom")
    package_entries = [
        {
            "SPDXID": app_id,
            "name": "ThoxWarRoom",
            "versionInfo": version,
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": False,
            "licenseConcluded": "MIT",
            "licenseDeclared": "MIT",
            "supplier": "Organization: THOX AI LLC",
            "externalRefs": [
                {
                    "referenceCategory": "PACKAGE-MANAGER",
                    "referenceType": "purl",
                    "referenceLocator": f"pkg:generic/thoxwarroom@{version}?vcs_url=https://github.com/ttracx/thoxwarroom@{revision}",
                }
            ],
        }
    ]
    for name in sorted(inventory):
        package_entries.append(
            {
                "SPDXID": _spdx_id(name),
                "name": name,
                "versionInfo": version,
                "downloadLocation": "NOASSERTION",
                "filesAnalyzed": False,
                "licenseConcluded": "MIT",
                "licenseDeclared": "MIT",
                "supplier": "Organization: THOX AI LLC",
            }
        )

    relationships = [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": app_id,
        }
    ]
    relationships.extend(
        {
            "spdxElementId": app_id,
            "relationshipType": "DEPENDS_ON",
            "relatedSpdxElement": _spdx_id(name),
        }
        for name in sorted(inventory)
    )
    for name in sorted(inventory):
        relationships.extend(
            {
                "spdxElementId": _spdx_id(name),
                "relationshipType": "DEPENDS_ON",
                "relatedSpdxElement": _spdx_id(dependency),
            }
            for dependency in inventory[name]
        )

    return {
        "SPDXID": "SPDXRef-DOCUMENT",
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "name": f"ThoxWarRoom-{version}",
        "documentNamespace": f"https://thox.ai/spdx/thoxwarroom/{revision}",
        "creationInfo": {
            "created": _iso8601(created),
            "creators": [
                "Organization: THOX AI LLC",
                "Tool: thoxwarroom-generate-sbom-1",
            ],
        },
        "documentDescribes": [app_id],
        "packages": package_entries,
        "relationships": relationships,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--revision", required=True)
    parser.add_argument("--created", required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        sbom = build_sbom(args.source_root.resolve(), args.revision, args.created)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(sbom, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    except SBOMError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Generated SPDX SBOM: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

import json
import pathlib
import tempfile
import unittest

import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from generate_sbom import SBOMError, build_sbom  # noqa: E402


class GenerateSBOMTests(unittest.TestCase):
    def make_source(self, remote_dependency: bool = False) -> pathlib.Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name)
        (root / "project.yml").write_text(
            'settings:\n  base:\n    MARKETING_VERSION: "4.2.0"\n', encoding="utf-8"
        )
        core = root / "Packages" / "Core"
        feature = root / "Packages" / "Feature"
        core.mkdir(parents=True)
        feature.mkdir(parents=True)
        (core / "Package.swift").write_text(
            'let package = Package(name: "Core")\n', encoding="utf-8"
        )
        dependency = (
            '.package(url: "https://example.invalid/dependency", from: "1.0.0")'
            if remote_dependency
            else '.package(path: "../Core")'
        )
        (feature / "Package.swift").write_text(
            f'let package = Package(name: "Feature", dependencies: [{dependency}])\n',
            encoding="utf-8",
        )
        return root

    def test_builds_deterministic_spdx_inventory_and_relationships(self) -> None:
        root = self.make_source()
        revision = "a" * 40
        first = build_sbom(root, revision, "2026-08-23T10:00:00-05:00")
        second = build_sbom(root, revision, "2026-08-23T15:00:00Z")

        self.assertEqual(first, second)
        self.assertEqual(first["spdxVersion"], "SPDX-2.3")
        self.assertEqual(first["creationInfo"]["created"], "2026-08-23T15:00:00Z")
        self.assertEqual(
            [package["name"] for package in first["packages"]],
            ["ThoxWarRoom", "Core", "Feature"],
        )
        relationships = json.dumps(first["relationships"], sort_keys=True)
        self.assertIn("SPDXRef-Package-Feature", relationships)
        self.assertIn("SPDXRef-Package-Core", relationships)

    def test_rejects_unmodeled_remote_dependency(self) -> None:
        with self.assertRaisesRegex(SBOMError, "Remote dependency"):
            build_sbom(
                self.make_source(remote_dependency=True),
                "b" * 40,
                "2026-08-23T15:00:00Z",
            )

    def test_rejects_invalid_revision_and_naive_timestamp(self) -> None:
        root = self.make_source()
        with self.assertRaisesRegex(SBOMError, "Revision"):
            build_sbom(root, "not-a-sha", "2026-08-23T15:00:00Z")
        with self.assertRaisesRegex(SBOMError, "timezone"):
            build_sbom(root, "c" * 40, "2026-08-23T15:00:00")


if __name__ == "__main__":
    unittest.main()

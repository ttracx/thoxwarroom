import pathlib
import tempfile
import unittest

import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from scan_source_secrets import scan_paths  # noqa: E402


class SourceSecretScannerTests(unittest.TestCase):
    def make_root(self) -> pathlib.Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        return pathlib.Path(temporary.name)

    def test_accepts_placeholders_and_env_example(self) -> None:
        root = self.make_root()
        example = root / ".env.example"
        example.write_text("ASC_API_KEY_P8=/secure/AuthKey_PLACEHOLDER.p8\n", encoding="utf-8")
        readme = root / "README.md"
        readme.write_text(
            "Authorization: Bearer <api-key>\nhttps://user:password@example.invalid\n",
            encoding="utf-8",
        )
        self.assertEqual(scan_paths(root, [example, readme]), [])

    def test_flags_private_key_and_sensitive_filename_without_value(self) -> None:
        root = self.make_root()
        key = root / "AuthKey_EXAMPLE123.p8"
        key.write_text(
            "-----BEGIN PRIVATE KEY-----\nDO-NOT-PRINT-THIS\n-----END PRIVATE KEY-----\n",
            encoding="utf-8",
        )
        findings = scan_paths(root, [key])
        self.assertEqual(
            findings,
            [
                ("sensitive-filename", "AuthKey_EXAMPLE123.p8"),
                ("private-key-marker", "AuthKey_EXAMPLE123.p8"),
            ],
        )
        self.assertNotIn("DO-NOT-PRINT-THIS", repr(findings))

    def test_flags_high_confidence_tokens_and_url_credentials(self) -> None:
        root = self.make_root()
        source = root / "Config.swift"
        source.write_text(
            "\n".join(
                [
                    "ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD",
                    "AKIA1234567890ABCDEF",
                    "https://operator:supersecretvalue@example.invalid",
                ]
            ),
            encoding="utf-8",
        )
        self.assertEqual(
            [rule for rule, _ in scan_paths(root, [source])],
            ["github-token", "aws-access-key", "private-url-credentials"],
        )

    def test_explicit_fixture_exclusion_skips_content_only(self) -> None:
        root = self.make_root()
        fixture = root / "fixture.txt"
        fixture.write_text("-----BEGIN PRIVATE KEY-----\n", encoding="utf-8")
        self.assertEqual(scan_paths(root, [fixture], {"fixture.txt"}), [])


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Scan Git-tracked source for high-confidence credential material."""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys


MAX_TRACKED_FILE_BYTES = 5 * 1_024 * 1_024
ALLOWED_SENSITIVE_NAMES = {".env.example"}
CONTENT_SCAN_EXCLUSIONS = {"scripts/tests/test_scan_source_secrets.py"}
SENSITIVE_FILENAMES = (
    re.compile(r"^AuthKey_[A-Za-z0-9]+\.p8$", re.IGNORECASE),
    re.compile(r"^(?:id_rsa|id_ed25519)$", re.IGNORECASE),
    re.compile(r"^\.env(?:\..+)?$", re.IGNORECASE),
)
CONTENT_RULES: tuple[tuple[str, re.Pattern[bytes]], ...] = (
    (
        "private-key-marker",
        re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    ),
    ("github-token", re.compile(rb"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b")),
    ("github-fine-grained-token", re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{40,}\b")),
    ("aws-access-key", re.compile(rb"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("openai-api-key", re.compile(rb"\bsk-[A-Za-z0-9_-]{24,}\b")),
    (
        "private-url-credentials",
        re.compile(
            rb"https?://(?!user:password@)[^\s/:@]{2,}:[^\s/@]{8,}@",
            re.IGNORECASE,
        ),
    ),
)


class SecretScanError(RuntimeError):
    """A non-sensitive scanner failure."""


def tracked_paths(root: pathlib.Path) -> list[pathlib.Path]:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            check=True,
            capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise SecretScanError("Unable to enumerate Git-tracked files") from error
    paths = []
    for raw_path in result.stdout.split(b"\0"):
        if not raw_path:
            continue
        try:
            relative = pathlib.PurePosixPath(raw_path.decode("utf-8"))
        except UnicodeDecodeError as error:
            raise SecretScanError("Tracked path is not valid UTF-8") from error
        if relative.is_absolute() or ".." in relative.parts:
            raise SecretScanError("Git returned an unsafe tracked path")
        paths.append(root.joinpath(*relative.parts))
    return paths


def scan_paths(
    root: pathlib.Path,
    paths: list[pathlib.Path],
    content_exclusions: set[str] | None = None,
) -> list[tuple[str, str]]:
    findings: list[tuple[str, str]] = []
    resolved_root = root.resolve()
    exclusions = content_exclusions or set()
    for path in sorted(paths):
        try:
            relative = path.resolve(strict=True).relative_to(resolved_root)
        except (OSError, ValueError):
            findings.append(("unsafe-or-missing-tracked-path", path.name))
            continue
        relative_text = relative.as_posix()
        if path.name not in ALLOWED_SENSITIVE_NAMES and any(
            pattern.fullmatch(path.name) for pattern in SENSITIVE_FILENAMES
        ):
            findings.append(("sensitive-filename", relative_text))
        if relative_text in exclusions:
            continue
        try:
            size = path.stat().st_size
            if size > MAX_TRACKED_FILE_BYTES:
                findings.append(("tracked-file-too-large-to-scan", relative_text))
                continue
            content = path.read_bytes()
        except OSError:
            findings.append(("tracked-file-unreadable", relative_text))
            continue
        for rule_id, pattern in CONTENT_RULES:
            if pattern.search(content):
                findings.append((rule_id, relative_text))
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=pathlib.Path, default=pathlib.Path.cwd())
    args = parser.parse_args()
    root = args.source_root.resolve()
    try:
        findings = scan_paths(root, tracked_paths(root), CONTENT_SCAN_EXCLUSIONS)
    except SecretScanError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    if findings:
        print("ERROR: tracked source secret scan failed", file=sys.stderr)
        for rule_id, relative_path in findings:
            print(f"  {relative_path}: {rule_id}", file=sys.stderr)
        print("Matched values are intentionally not displayed.", file=sys.stderr)
        return 1
    print("Tracked source secret scan passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

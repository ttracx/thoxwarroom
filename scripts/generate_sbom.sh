#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain --untracked-files=no)" ] && [ -z "${ALLOW_DIRTY_SBOM:-}" ]; then
    echo "ERROR: tracked worktree changes make release provenance ambiguous" >&2
    echo "       Commit changes first or set ALLOW_DIRTY_SBOM=1 for a non-release preview" >&2
    exit 1
fi

REVISION=$(git rev-parse HEAD)
CREATED=$(git show -s --format=%cI "$REVISION")
OUTPUT=${SBOM_OUTPUT:-build/release/ThoxWarRoom.spdx.json}

python3 scripts/generate_sbom.py \
    --source-root . \
    --revision "$REVISION" \
    --created "$CREATED" \
    --output "$OUTPUT"

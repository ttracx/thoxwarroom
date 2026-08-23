#!/usr/bin/env bash
# One-command clean-clone bootstrap and unsigned validation.
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/ci_unsigned.sh

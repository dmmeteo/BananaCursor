#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec uv run --with 'dmgbuild==1.6.7' python -B scripts/package-release.py "$@"

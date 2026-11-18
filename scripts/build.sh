#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec uv run python -B scripts/build.py "$@"

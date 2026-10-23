#!/usr/bin/env bash
# Backward-compatible wrapper.
# Setup sebenarnya ada di .devcontainer/setup.sh (idempoten, mendukung Ubuntu
# devcontainer dan Alpine recovery container).
set -Eeuo pipefail
exec bash "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/setup.sh" "$@"

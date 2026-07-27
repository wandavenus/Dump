#!/usr/bin/env bash
set -o pipefail

flutter analyze --no-fatal-infos --fatal-warnings "$@"
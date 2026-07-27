#!/usr/bin/env bash
set -o pipefail

# Keep analyzer output focused on actionable diagnostics. Info-level lints are
# intentionally not shown, but errors and warnings still determine the exit
# status of this workflow.
output_file="$(mktemp)"
trap 'rm -f "$output_file"' EXIT

analyzer_status=0
flutter analyze --no-fatal-infos --fatal-warnings "$@" >"$output_file" 2>&1 || analyzer_status=$?

awk '
function flush_block() {
  if (kind == "error" || kind == "warning") {
    printf "%s", block
    if (kind == "error") {
      errors++
    } else {
      warnings++
    }
  }
  block = ""
  kind = ""
}

/^[[:space:]]+error •/ {
  flush_block()
  kind = "error"
  block = $0 "\n"
  next
}

/^[[:space:]]+warning •/ {
  flush_block()
  kind = "warning"
  block = $0 "\n"
  next
}

/^[[:space:]]+info •/ {
  flush_block()
  kind = "info"
  next
}

kind != "" {
  block = block $0 "\n"
}

END {
  flush_block()
  if (errors == 0 && warnings == 0) {
    print "No errors or warnings found."
  } else {
    printf "%d error(s), %d warning(s).\n", errors, warnings
  }
}
' "$output_file"

exit "$analyzer_status"
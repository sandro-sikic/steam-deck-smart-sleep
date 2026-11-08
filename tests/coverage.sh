#!/bin/bash
# Run the bats suite under kcov and fail unless both scripts have 100% line
# coverage.  Needs `bats` and `kcov` on PATH.  Output goes to a temp dir.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

SDSS_COVERAGE=1 kcov --include-path="$repo/install.sh,$repo/steam-deck-smart-sleep.sh" \
    "$out" bats "$repo/tests" >"$out/run.log" 2>&1 || { grep -E '^(not ok|#)' "$out/run.log"; echo "tests failed" >&2; exit 1; }

python3 - "$out" <<'PY'
import glob, json, sys
files = {}
for path in glob.glob(sys.argv[1] + "/*/coverage.json"):
    for f in json.load(open(path))["files"]:
        files[f["file"]] = f
bad = 0
for name, f in sorted(files.items()):
    print(f"{f['percent_covered']:>7}%  {f['covered_lines']}/{f['total_lines']}  {name}")
    bad |= float(f["percent_covered"]) < 100
sys.exit(1 if bad or not files else 0)
PY

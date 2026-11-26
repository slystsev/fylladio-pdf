#!/bin/zsh
# Runs the UI self-test on a separate app copy, with its own settings and bookmark store.
# Usage: test-ui.sh <outDir>   (needs FylladioCheck's large.pdf: swift run -c release FylladioCheck <outDir>/fc 50)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?outDir}
scripts/build-app.sh .build/test/Fylladio.app >/dev/null
[[ -f "$OUT/fc/large.pdf" ]] || swift run -c release FylladioCheck "$OUT/fc" 50 >/dev/null
rm -rf "$OUT/st"; mkdir -p "$OUT/st"; cp "$OUT/fc/large.pdf" "$OUT/st/doc.pdf"
FYLLADIO_SELFTEST="$OUT/st" FYLLADIO_SELFTEST_FILE="$OUT/st/doc.pdf" .build/test/Fylladio.app/Contents/MacOS/Fylladio >"$OUT/st/out.log" 2>&1 &
for i in {1..60}; do [[ -f "$OUT/st/report.txt" ]] && break; perl -e 'select(undef,undef,undef,2)'; done
grep -E "FAIL|ALL" "$OUT/st/report.txt" || { echo "no report (hung?)"; tail -3 "$OUT/st/progress.txt"; exit 1; }
echo "$(grep -c PASS "$OUT/st/report.txt") checks passed"

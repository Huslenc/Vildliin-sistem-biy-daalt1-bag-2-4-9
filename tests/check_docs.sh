#!/bin/sh
# Review R6: every screenshot referenced in README exists, and every file in docs/screenshots is referenced.
cd "$(dirname "$0")/.." || exit 1
fail=0
for f in $(grep -o 'docs/screenshots/[A-Za-z0-9_.-]*\.png' README.md | sort -u); do
  [ -f "$f" ] || { echo "FAIL README references missing file: $f"; fail=1; }
done
for f in docs/screenshots/*.png; do
  grep -q "$f" README.md || { echo "FAIL unreferenced screenshot: $f"; fail=1; }
done
[ $fail -eq 0 ] && echo "PASS docs: all screenshot links resolve, no orphan files"
exit $fail

#!/bin/sh
# Worker scaling (review S4/R7): run_ms excludes pool start-up. Usage: sh tests/bench.sh [tasks]
cd "$(dirname "$0")/.." || exit 1
N=${1:-40}
echo "tasks=$N queue=32 task=100..300ms (seed 1)"; echo "workers run_ms speedup"
base=""
for w in 1 2 4 8 16; do
  ms=$(./tpdemo $w 32 $N 100 300 0 1 | grep -o '"run_ms":[0-9.]*' | cut -d: -f2)
  [ -z "$base" ] && base=$ms
  echo "$w $ms $(awk -v a="$base" -v b="$ms" 'BEGIN{printf "%.2fx", a/b}')"
done

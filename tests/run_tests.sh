#!/bin/sh
# Core tests. Valid case args: workers queue tasks min max interval seed
cd "$(dirname "$0")/.." || exit 1
fail=0; n=0
check() {
  n=$((n+1))
  out=$(./tpdemo "$@") || { echo "FAIL #$n ($*): program error"; fail=1; return; }
  d=$(echo "$out" | grep -c '"e":"done"')
  dup=$(echo "$out" | grep '"e":"rejected"' | sed 's/.*"k":\([0-9]*\).*/\1/' | sort | uniq -d | wc -l)
  if echo "$out" | grep -q '"ok":true' && echo "$out" | grep -q '"truncated":false' \
     && [ "$d" -eq "$3" ] && [ "$dup" -eq 0 ]; then echo "PASS #$n workers=$1 queue=$2 tasks=$3"
  else echo "FAIL #$n ($*)"; fail=1; fi
}
check 1 4 10 10 30 0 1      # single worker
check 4 8 20 10 40 5 2      # normal
check 2 1 15 10 30 0 3      # tiny queue -> back-pressure
check 8 4 50 5 20 0 4       # more workers than queue slots
check 3 10 1 10 10 0 5      # one task only
check 16 32 200 1 3 0 6     # upper bounds of every parameter
check 1 1 5 5 5 0 7         # lower bounds (1 worker, 1 slot)

# invalid input must give exit 1 and the "invalid parameters" message (never run)
bad() {
  msg=$(./tpdemo "$@" 2>&1 >/dev/null); rc=$?
  if [ $rc -eq 1 ] && [ "$msg" = "invalid parameters" ]; then echo "PASS invalid rejected: $*"
  else echo "FAIL invalid accepted/wrong message (rc=$rc): $*"; fail=1; fi
}
bad 0 4 10 10 30 0;   bad 17 4 10 10 30 0;  bad 4 0 10 10 30 0;   bad 4 33 10 10 30 0
bad 4 4 0 10 30 0;    bad 4 4 201 10 30 0;  bad 4 4 10 0 30 0;    bad 4 4 10 40 30 0
bad 4 4 10 10 5001 0; bad 4 4 10 10 30 2001; bad 12abc 4 10 10 30 0; bad 4 4 10 10 30 -1
bad "" 4 10 10 30 0;  bad 4 4 10 10 30 0 7x
./tpdemo 4 4 10 10 >/dev/null 2>&1 && { echo "FAIL too few args accepted"; fail=1; } || echo "PASS too few args rejected"

# repeatability: 30 seeds, tiny queue, everything must complete without dropped events
bad_runs=0
for s in $(seq 11 40); do
  ./tpdemo 4 3 40 1 5 0 $s | grep -q '"ok":true' || bad_runs=$((bad_runs+1))
done
[ $bad_runs -eq 0 ] && echo "PASS stability 30/30 seeds ok:true" || { echo "FAIL stability: $bad_runs/30 failed"; fail=1; }
exit $fail

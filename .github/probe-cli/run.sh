#!/usr/bin/env bash
# Measurement only, not meant for upstream. Lifts the call and depth limits so only the 896 KiB
# stack guard binds, then finds with `gridcraft-cli eval` the deepest n per form that returns a
# number, on $BASE and $OURS, release and dev.
set -uo pipefail
forms=(
  "countdown|=LET(F,LAMBDA(me,n,IF(n<=0,0,1+me(me,n-1))),F(F,{N}))"
  "tail|=LET(F,LAMBDA(me,n,IF(n=0,0,me(me,n-1))),F(F,{N}))"
  "let|=LET(F,LAMBDA(me,n,IF(n<=0,0,LET(e,me(me,n-1),e+1))),F(F,{N}))"
  "map|=LET(F,LAMBDA(me,n,IF(n<=0,0,1+SUM(MAP({1},LAMBDA(v,me(me,n-1)))))),F(F,{N}))"
)
for ref in $BASE $OURS; do
  git checkout -q "$ref"
  sed -i.bak 's/^const MAX_LAMBDA_CALLS: usize = 140;/const MAX_LAMBDA_CALLS: usize = 100_000;/; s/^const MAX_DEPTH: usize = 400;/const MAX_DEPTH: usize = 1_000_000;/' crates/calc/src/eval.rs
  grep -q 'MAX_LAMBDA_CALLS: usize = 100_000' crates/calc/src/eval.rs || { echo "sed failed"; exit 1; }
  grep -q 'MAX_DEPTH: usize = 1_000_000' crates/calc/src/eval.rs || { echo "sed failed"; exit 1; }
  for profile in release dev; do
    flag=""; dir=debug; [ "$profile" = release ] && { flag="--release"; dir=release; }
    cargo build -q -p gridcraft-cli $flag || exit 1
    bin=target/$dir/gridcraft-cli; [ -f "$bin.exe" ] && bin="$bin.exe"
    for entry in "${forms[@]}"; do
      name=${entry%%|*}; tpl=${entry#*|}
      run() { local out; out=$("$bin" eval "${tpl//\{N\}/$1}" 2>&1); echo "$out [exit $?]"; }
      lo=1; hi=4000
      while [ $((lo + 1)) -lt $hi ]; do
        mid=$(((lo + hi) / 2))
        if run $mid | grep -Eq '^-?[0-9.]+ \[exit 0\]$'; then lo=$mid; else hi=$mid; fi
      done
      echo "PROBE $RUNNER_OS ${ref:0:8} $profile $name: deepest n $lo; n=$hi gives $(run $hi | tr '\n' ' ' | cut -c1-80)"
    done
  done
  git checkout -q -- crates/calc/src/eval.rs; rm -f crates/calc/src/eval.rs.bak
done

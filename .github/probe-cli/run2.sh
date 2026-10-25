#!/usr/bin/env bash
# Measurement only, not meant for upstream. For each "label:ref:lift" in $CONFIGS, builds
# gridcraft-cli (release and dev) at ref, with the call and depth limits lifted when lift=1 so only
# the 896 KiB stack guard binds, and finds per form the deepest n whose answer is right
# (n, or 0 for forms named *0).
set -uo pipefail
forms_file="$PROBE_DIR/forms.txt"
for cfg in $CONFIGS; do
  IFS=: read -r label ref lift <<<"$cfg"
  git checkout -q "$ref" || exit 1
  if [ "$lift" = 1 ]; then
    sed -i.bak -E 's/^const MAX_LAMBDA_CALLS: usize = [0-9_]+;/const MAX_LAMBDA_CALLS: usize = 100_000;/; s/^const MAX_DEPTH: usize = [0-9_]+;/const MAX_DEPTH: usize = 1_000_000;/' crates/calc/src/eval.rs
    grep -q 'MAX_LAMBDA_CALLS: usize = 100_000' crates/calc/src/eval.rs && grep -q 'MAX_DEPTH: usize = 1_000_000' crates/calc/src/eval.rs || { echo "sed failed"; exit 1; }
  fi
  echo "### $label ($ref) $(grep -E '^const (MAX_DEPTH|MAX_LAMBDA_CALLS)' crates/calc/src/eval.rs | tr '\n' ' ')"
  for profile in release dev; do
    flag=""; dir=debug; [ "$profile" = release ] && { flag="--release"; dir=release; }
    cargo build -q -p gridcraft-cli $flag || exit 1
    bin=target/$dir/gridcraft-cli; [ -f "$bin.exe" ] && bin="$bin.exe"
    while IFS='|' read -r name tpl; do
      [ -z "$name" ] && continue
      run() { local out; out=$("$bin" eval "${tpl//\{N\}/$1}" 2>&1); echo "$out [exit $?]"; }
      want() { case $name in *0) echo 0 ;; *) echo "$1" ;; esac; }
      lo=1; hi=4000
      while [ $((lo + 1)) -lt $hi ]; do
        mid=$(((lo + hi) / 2))
        if [ "$(run $mid)" = "$(want $mid) [exit 0]" ]; then lo=$mid; else hi=$mid; fi
      done
      echo "PROBE $RUNNER_OS $label $profile $name: deepest n $lo; n=$hi gives $(run $hi | tr '\n' ' ' | cut -c1-60)"
    done <"$forms_file"
  done
  git checkout -q -- crates/calc/src/eval.rs; rm -f crates/calc/src/eval.rs.bak
done

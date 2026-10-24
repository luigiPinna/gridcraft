#!/usr/bin/env bash
# Measure the stack one LAMBDA call needs: lift the call and depth limits so only the 896 KiB
# stack guard binds, then find the deepest n per form (probe.rs). Not meant for upstream.
set -euo pipefail
probe="$PROBE_DIR/probe.rs"
for ref in "$BASE" "$OURS"; do
  git checkout -q "$ref"
  sed -i.bak 's/^const MAX_LAMBDA_CALLS: usize = 140;/const MAX_LAMBDA_CALLS: usize = 100_000;/; s/^const MAX_DEPTH: usize = 400;/const MAX_DEPTH: usize = 1_000_000;/' crates/calc/src/eval.rs
  grep -q 'MAX_LAMBDA_CALLS: usize = 100_000' crates/calc/src/eval.rs
  cat "$probe" >> crates/calc/src/tests.rs
  for profile in release dev; do
    flag=""; [ "$profile" = release ] && flag="--release"
    echo "### $RUNNER_OS $ref $profile"
    cargo test -q -p gridcraft-calc --lib $flag -- probe_stack_per_call --nocapture 2>&1 | grep PROBE
  done
  git checkout -q -- crates/calc/src/eval.rs crates/calc/src/tests.rs; rm -f crates/calc/src/eval.rs.bak
done
git checkout -q "$OURS"
for profile in release dev; do
  flag=""; [ "$profile" = release ] && flag="--release"
  echo "### $RUNNER_OS $OURS $profile: #1809 tests and the calc suite, limits as committed"
  cargo test -q -p gridcraft-calc --lib $flag 2>&1 | grep -E '^test result|FAILED|panicked'
done

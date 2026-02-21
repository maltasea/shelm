#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f "LANG_SPEC.md" ]]; then
  echo "LANG_SPEC.md not found. Run from repository root." >&2
  exit 1
fi

run_dune() {
  if command -v opam >/dev/null 2>&1; then
    opam exec -- dune "$@"
  else
    dune "$@"
  fi
}

run_buoy() {
  if command -v opam >/dev/null 2>&1; then
    opam exec -- ./_build/default/bin/buoy.exe "$@"
  else
    ./_build/default/bin/buoy.exe "$@"
  fi
}

echo "[1/7] Build + tests"
run_dune build
run_dune runtest

echo "[2/7] .by extension enforcement"
if run_buoy benchmarks/prime_count.pl --target perl >/tmp/buoy-ext.out 2>&1; then
  echo "Expected extension check to fail for non-.by file" >&2
  exit 1
fi
if ! rg -q "must use \\.by extension" /tmp/buoy-ext.out; then
  echo "Missing expected .by extension error message" >&2
  cat /tmp/buoy-ext.out >&2
  exit 1
fi

echo "[3/7] keyword/end-only block syntax enforcement"
cat > /tmp/buoy-if-do.by <<'EOF'
let x = 1
if x == 1 do
  println("ok")
end
EOF
if run_buoy /tmp/buoy-if-do.by --target perl >/tmp/buoy-if-do.out 2>&1; then
  echo "Expected if ... do to be rejected" >&2
  exit 1
fi
if ! rg -q "if \\.\\.\\. do.*not supported" /tmp/buoy-if-do.out; then
  echo "Missing expected if ... do rejection message" >&2
  cat /tmp/buoy-if-do.out >&2
  exit 1
fi

cat > /tmp/buoy-brace-block.by <<'EOF'
let x = 1
if x == 1 {
  println("ok")
}
EOF
if run_buoy /tmp/buoy-brace-block.by --target perl >/tmp/buoy-brace-block.out 2>&1; then
  echo "Expected brace block syntax to be rejected" >&2
  exit 1
fi
if ! rg -q "Brace blocks are not supported" /tmp/buoy-brace-block.out; then
  echo "Missing expected brace-block rejection message" >&2
  cat /tmp/buoy-brace-block.out >&2
  exit 1
fi

echo "[4/7] Compile all .by files to all targets"
BY_FILES=()
while IFS= read -r path; do
  BY_FILES+=("$path")
done < <(find examples benchmarks -type f -name '*.by' | sort)
if [[ "${#BY_FILES[@]}" -eq 0 ]]; then
  echo "No .by files found in examples/benchmarks" >&2
  exit 1
fi
for src in "${BY_FILES[@]}"; do
  for target in perl ocaml go bytecode; do
    run_buoy "$src" --target "$target" >"/tmp/buoy-conformance-$(basename "$src").$target.out"
  done
done

echo "[5/7] Execute generated Perl for all sample .by files"
for src in "${BY_FILES[@]}"; do
  run_buoy "$src" --target perl > /tmp/buoy-sample.pl
  perl /tmp/buoy-sample.pl >/tmp/buoy-sample.out
done

echo "[6/7] Benchmark CLI mode"
run_buoy benchmarks/prime_count.by --benchmark benchmarks/prime_count.pl --iterations 1 >/tmp/buoy-bench.out
if ! rg -q "Perl benchmark comparison" /tmp/buoy-bench.out; then
  echo "Benchmark output missing expected header" >&2
  cat /tmp/buoy-bench.out >&2
  exit 1
fi

echo "[7/7] Spec file presence"
for path in LANG_SPEC.md SYNTAX_SPEC.md scripts/check-conformance.sh test/syntax_tests.ml; do
  [[ -f "$path" ]] || { echo "Missing required file: $path" >&2; exit 1; }
done

echo "Conformance checks passed."

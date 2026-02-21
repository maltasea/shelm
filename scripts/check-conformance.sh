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

run_shelm() {
  if command -v opam >/dev/null 2>&1; then
    opam exec -- ./_build/default/bin/shelm.exe "$@"
  else
    ./_build/default/bin/shelm.exe "$@"
  fi
}

echo "[1/7] Build + tests"
run_dune build
run_dune runtest

echo "[2/7] .shlm extension enforcement"
if run_shelm benchmarks/prime_count.pl --target perl >/tmp/shelm-ext.out 2>&1; then
  echo "Expected extension check to fail for non-.shlm file" >&2
  exit 1
fi
if ! rg -q "must use \\.shlm extension" /tmp/shelm-ext.out; then
  echo "Missing expected .shlm extension error message" >&2
  cat /tmp/shelm-ext.out >&2
  exit 1
fi

echo "[3/7] keyword/end-only block syntax enforcement"
cat > /tmp/shelm-if-do.shlm <<'EOF'
let x = 1
if x == 1 do
  println("ok")
end
EOF
if run_shelm /tmp/shelm-if-do.shlm --target perl >/tmp/shelm-if-do.out 2>&1; then
  echo "Expected if ... do to be rejected" >&2
  exit 1
fi
if ! rg -q "if \\.\\.\\. do.*not supported" /tmp/shelm-if-do.out; then
  echo "Missing expected if ... do rejection message" >&2
  cat /tmp/shelm-if-do.out >&2
  exit 1
fi

cat > /tmp/shelm-brace-block.shlm <<'EOF'
let x = 1
if x == 1 {
  println("ok")
}
EOF
if run_shelm /tmp/shelm-brace-block.shlm --target perl >/tmp/shelm-brace-block.out 2>&1; then
  echo "Expected brace block syntax to be rejected" >&2
  exit 1
fi
if ! rg -q "Brace blocks are not supported" /tmp/shelm-brace-block.out; then
  echo "Missing expected brace-block rejection message" >&2
  cat /tmp/shelm-brace-block.out >&2
  exit 1
fi

cat > /tmp/shelm-legacy-for.shlm <<'EOF'
for x in [1, 2] do
  println(x)
end
EOF
if run_shelm /tmp/shelm-legacy-for.shlm --target perl >/tmp/shelm-legacy-for.out 2>&1; then
  echo "Expected legacy for-loop syntax to be rejected" >&2
  exit 1
fi
if ! rg -q '`for` is not supported' /tmp/shelm-legacy-for.out; then
  echo "Missing expected legacy-for rejection message" >&2
  cat /tmp/shelm-legacy-for.out >&2
  exit 1
fi

cat > /tmp/shelm-legacy-fn.shlm <<'EOF'
fn add x, y do
  return x + y
end
EOF
if run_shelm /tmp/shelm-legacy-fn.shlm --target perl >/tmp/shelm-legacy-fn.out 2>&1; then
  echo "Expected legacy fn syntax to be rejected" >&2
  exit 1
fi
if ! rg -q '`fn`/`rec fn` are not supported' /tmp/shelm-legacy-fn.out; then
  echo "Missing expected legacy-fn rejection message" >&2
  cat /tmp/shelm-legacy-fn.out >&2
  exit 1
fi

cat > /tmp/shelm-compact-colon-type.shlm <<'EOF'
let v = kw:Int
EOF
if run_shelm /tmp/shelm-compact-colon-type.shlm --target perl >/tmp/shelm-compact-colon-type.out 2>&1; then
  echo "Expected compact typed form (name:Type) to be rejected" >&2
  exit 1
fi
if ! rg -q "is not supported" /tmp/shelm-compact-colon-type.out; then
  echo "Missing expected compact-type rejection message" >&2
  cat /tmp/shelm-compact-colon-type.out >&2
  exit 1
fi

cat > /tmp/shelm-typed-signature.shlm <<'EOF'
def age : Int = 9
defun add(x : Int, y : Int) => Int do
  return x + y
end
let f = fun(v : Int) => Int do
  return v * 2
end
println(string_of(add(age, 1)))
println(string_of(f(3)))
EOF
run_shelm /tmp/shelm-typed-signature.shlm --target perl >/tmp/shelm-typed-signature.out

echo "[4/7] Compile all .shlm files to all targets"
SHLM_FILES=()
while IFS= read -r path; do
  SHLM_FILES+=("$path")
done < <(find examples benchmarks -type f -name '*.shlm' | sort)
if [[ "${#SHLM_FILES[@]}" -eq 0 ]]; then
  echo "No .shlm files found in examples/benchmarks" >&2
  exit 1
fi
for src in "${SHLM_FILES[@]}"; do
  for target in perl ocaml go bytecode; do
    run_shelm "$src" --target "$target" >"/tmp/shelm-conformance-$(basename "$src").$target.out"
  done
done

echo "[5/7] Execute generated Perl for all sample .shlm files"
for src in "${SHLM_FILES[@]}"; do
  run_shelm "$src" --target perl > /tmp/shelm-sample.pl
  perl /tmp/shelm-sample.pl >/tmp/shelm-sample.out
done

echo "[6/7] Benchmark CLI mode"
run_shelm benchmarks/prime_count.shlm --benchmark benchmarks/prime_count.pl --iterations 1 >/tmp/shelm-bench.out
if ! rg -q "Perl benchmark comparison" /tmp/shelm-bench.out; then
  echo "Benchmark output missing expected header" >&2
  cat /tmp/shelm-bench.out >&2
  exit 1
fi

echo "[7/7] Spec file presence"
for path in LANG_SPEC.md scripts/check-conformance.sh test/syntax_tests.ml; do
  [[ -f "$path" ]] || { echo "Missing required file: $path" >&2; exit 1; }
done

echo "Conformance checks passed."

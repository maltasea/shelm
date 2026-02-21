# Conformance Report

## Scope

This report validates repository conformance against `LANG_SPEC.md` (implemented v1 spec).

## Command Run

```bash
./scripts/check-conformance.sh
```

## Result

- Status: PASS
- Date: 2026-02-21

## Checks Performed

1. `dune build` and `dune runtest` pass.
2. CLI enforces `.by` source extension.
3. `do/end` emits deprecation warning.
4. All `examples/*.by` and `benchmarks/*.by` compile for:
   - `perl`
   - `ocaml`
   - `go`
   - `bytecode`
5. Generated Perl from all sample `.by` files executes successfully.
6. CLI benchmark mode works:
   - `buoy benchmarks/prime_count.by --benchmark benchmarks/prime_count.pl --iterations 1`
7. Spec/test/conformance files are present:
   - `LANG_SPEC.md`
   - `scripts/check-conformance.sh`
   - `test/syntax_tests.ml`

## Notes

- `LANG_V1.md` and `BYTECODE_V1.md` are retained as directional drafts.
- `LANG_SPEC.md` is the normative source-level contract for current behavior.

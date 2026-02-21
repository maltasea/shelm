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
2. CLI enforces `.shlm` source extension.
3. Keyword/end block syntax enforcement rejects non-canonical forms.
4. All `examples/*.shlm` and `benchmarks/*.shlm` compile for:
   - `perl`
   - `ocaml`
   - `go`
   - `bytecode`
5. Generated Perl from all sample `.shlm` files executes successfully.
6. CLI benchmark mode works:
   - `shelm benchmarks/prime_count.shlm --benchmark benchmarks/prime_count.pl --iterations 1`
7. Spec/test/conformance files are present:
   - `LANG_SPEC.md`
   - `scripts/check-conformance.sh`
   - `test/syntax_tests.ml`

## Notes

- `LANG_V1.md` and `BYTECODE_V1.md` are retained as directional drafts.
- `LANG_SPEC.md` is the normative source-level contract for current behavior.

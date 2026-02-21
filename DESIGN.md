# Buoy v1 Direction

## Goal

Ship a practical compiler pipeline:

`source -> tuple AST (triplet meta) -> macros -> expanded AST -> bytecode`

And use that bytecode for:

- VM execution
- backend/runtime integration work

## Priority Rule

- Default priority is run-time speed.
- Compilation speed is not a priority unless it blocks iteration.
- If tradeoffs appear, choose the faster path unless it breaks:
  - correctness
  - deterministic semantics
  - actionable error reporting

## Non-Goals

- No OCaml compiler-internals coupling (`Typedtree`, `Flambda`, etc.).
- No functional-programming feature creep.
- No auto-currying.
- No continuations/callcc-style control flow.
- No default TCO requirement (optional mode can be explored later).
- No syntax golf.
- No macro/hygiene/SRFI research track.
- No fake cross-platform agenda for app-level `main` logic.

## Language Bias

- Explicit imperative semantics.
- Fixed-arity function calls.
- Explicit recursion marker via `rec` keyword (planned).
- Readable syntax over clever shorthand.

## Runtime Bias

- Bytecode VM is simple and predictable.
- Keep portability where it matters (compute/runtime layers).
- Keep platform-specific boundaries explicit in app entrypoints.

## Concrete Specs

- `LANG_SPEC.md` is the source-level contract.
- `BYTECODE_V1.md` is the bytecode direction document.
- Includes simple FFI syntax (`$path` host get, `&path(...)` host call).

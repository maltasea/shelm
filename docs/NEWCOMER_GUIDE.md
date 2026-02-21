# Shelm Newcomer Guide

Welcome to Shelm.

If you are new, this guide gets you from zero to running code in a few minutes.

## 1) What Shelm Is

Shelm is a small language that compiles to multiple targets:

- `perl`
- `ocaml`
- `go`
- `bytecode`

Source files use the `.by` extension.

## 2) First Program

Create `hello.by`:

```shelm
let name = "World"
println("Hello, " ++ name ++ "!")
```

Compile to Perl:

```bash
opam exec -- ./_build/default/bin/shelm.exe hello.by --target perl > hello.pl
perl hello.pl
```

If `opam` is already active in your shell, you can call `./_build/default/bin/shelm.exe` directly.

## 3) Build the Compiler

From repo root:

```bash
opam exec -- dune build
```

Run tests:

```bash
opam exec -- dune runtest
```

## 4) Core Syntax

- Variables: `let x = 1`
- Assignment: `x = x + 1`
- Blocks prefer `keyword ... end`:
  - `if cond then ... else ... end`
  - `while cond do ... end`
  - `for item in items do ... end`
- Functions:
  - `fn add x, y do return x + y end`
  - `rec fn fact n do ... end`
- Closures/lambdas are intentionally not in the surface syntax (speed-first profile).
- Arrays: `[1, 2, 3]`
- Hashes: `{"a": 1, "b": 2}`
- Regex:
  - literal: `/\d+/`
  - match: `text =~ /\d+/`
  - replace: `text =~ s/foo/bar/g`

## 5) FFI Host Syntax

- Host read: `$foo/bar`
- Host call: `&foo/bar(1, 2)`

In generated Perl, host hooks are loaded with:

- `SHELM_PERL_HOST=runtime/perl_host_default.pl`

## 6) Helpful Commands

Compile sample files:

```bash
opam exec -- ./_build/default/bin/shelm.exe examples/hello.by --target perl
opam exec -- ./_build/default/bin/shelm.exe examples/arrays.by --target go
opam exec -- ./_build/default/bin/shelm.exe examples/hashes.by --target bytecode
```

Run benchmark mode:

```bash
opam exec -- ./_build/default/bin/shelm.exe benchmarks/prime_count.by \
  --benchmark benchmarks/prime_count.pl \
  --iterations 10
```

Run full conformance checks:

```bash
./scripts/check-conformance.sh
```

## 7) Next Reads

- `LANG_SPEC.md` (normative language spec)
- `CONFORMANCE_REPORT.md` (latest conformance status)
- `examples/*.by` (small working programs)

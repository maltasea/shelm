# Shelm

Shelm is a small, speed-first language that compiles to multiple backends. Source files use the `.shlm` extension.

## Quick Start

Build the compiler:

```bash
opam exec -- dune build
```

Write `hello.shlm`:

```shelm
let name = "World"
println("Hello, " ++ name ++ "!")
```

Compile and run:

```bash
opam exec -- ./_build/default/bin/shelm.exe hello.shlm --target perl > hello.pl
perl hello.pl
```

## Targets

Shelm compiles to four backends:

| Target | Flag | Output |
|--------|------|--------|
| Perl | `--target perl` | `.pl` file |
| OCaml | `--target ocaml` | `.ml` file |
| Go | `--target go` | `.go` file |
| Bytecode | `--target bytecode` | `.bytecode` assembly |

## Perl Host / FFI

Generated Perl includes a host bridge for calling into Perl from Shelm:

```shelm
# Read a host value
let now = $time/now_ms

# Call a host function
let result = &math/add(1, 2)
```

Set `SHELM_PERL_HOST` to load a custom host file:

```bash
SHELM_PERL_HOST=runtime/perl_host_default.pl perl hello.pl
```

## Benchmarking

Compare generated Perl against a reference Perl script:

```bash
opam exec -- ./_build/default/bin/shelm.exe benchmarks/prime_count.shlm \
  --benchmark benchmarks/prime_count.pl \
  --iterations 10
```

Or use the standalone comparison script:

```bash
scripts/compare-perl-vs-shelm.sh \
  --perl examples/bench_sum.pl \
  --shelm examples/bench_sum.shlm \
  --iterations 50
```

## Conformance

Run the full conformance suite:

```bash
./scripts/check-conformance.sh
```

This builds, runs tests, compiles all examples/benchmarks for every target, checks syntax enforcement, and verifies benchmark mode.

## Documentation

- [LANG_SPEC.md](LANG_SPEC.md) -- normative language spec
- [docs/NEWCOMER_GUIDE.md](docs/NEWCOMER_GUIDE.md) -- getting started guide
- [CONFORMANCE_REPORT.md](CONFORMANCE_REPORT.md) -- latest conformance status
- [DESIGN.md](DESIGN.md) -- project direction and design principles

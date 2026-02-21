# Buoy Lang v1

> Historical/directional draft. For implemented language behavior, see `LANG_SPEC.md`.

## Primary Goal

Design the language for fast bytecode interpreters first.

## Optimization Policy

- Run-time speed first by default.
- Compilation speed is a non-goal.
- Language features are accepted only if they map to efficient lowering.
- "Nice" syntax is secondary to fast parsing, simple lowering, and cheap runtime behavior.

## Core Constraints

- Surface syntax is ML-like but must be trivially translatable to S-exprs.
- Canonical AST is triple-based tuples:
  - `[tag, [char_pos, line_nr, module_name], args[]]`
- Macros run on canonical triple AST.
- Bytecode is the execution contract.

## Non-Goals

- No auto-currying.
- No continuations.
- No implicit TCO.
- No hygiene/SRFI-style macro system.
- No syntax golf.

## Minimum Features (v1)

- Variables
- Lists
- Vectors
- String-key map (key/value)
- `if/else`
- `unless`
- `foreach`
- `match/case`
- `enum`
- `type`
- `rec fn`
- FFI host get/call

## Surface Syntax (v1)

```buoy
type option<T> =
| None
| Some(T)

enum color =
| Red
| Green
| Blue

rec fn fact(n) {
  if n <= 1 {
    1
  } else {
    n * fact(n - 1)
  }
}

let xs = vec[1, 2, 3]
foreach x in xs {
  print(x)
}

unless length(xs) == 0 {
  print("non-empty")
}

match color_val {
| Red -> 1
| Green -> 2
| Blue -> 3
}

let host_name = $env/user/name
let out = &io/print_line("hello")
let out2 = &io/print_line "hello"
```

## Canonical Triple AST Examples

```text
let x = 10
=> ["let", [p,l,m], [["sym",[p,l,m],["x"]], ["int",[p,l,m],["10"]]]]

unless cond { body }
=> macro rewrite
=> ["if",[p,l,m],[["not",[p,l,m],[cond]], ["do",[p,l,m],[body]], ["do",[p,l,m],[]]]]

rec fn fact(n) { ... }
=> ["defn-rec",[p,l,m],[["sym",[p,l,m],["fact"]], ["params",[p,l,m],[["sym",[p,l,m],["n"]]]], ["do",[p,l,m],[...]]]]

$foo/bar/goo
=> ["host-get",[p,l,m],[["host-path",[p,l,m],["foo","bar","goo"]]]]

&foo/haa("gigi")
=> ["host-call",[p,l,m],[["host-path",[p,l,m],["foo","haa"]], ["string",[p,l,m],["gigi"]]]]

&foo/haa "gigi"
=> parser rewrite
=> &foo/haa("gigi")
```

## Fast-Semantics Rules

- Fixed arity calls only.
- Arity mismatch is an error.
- `map` keys are strings only in v1.
- `vector` is mutable dense indexed storage.
- `list` is semantic alias of vector in v1 runtime layout.
- `match` supports scalar and enum-tag cases in v1.

## FFI v1

- Host variable read:
  - `$foo/bar/goo`
- Host function call:
  - `&foo/haa("gigi")`
  - `&foo/haa "gigi"` (sugar)
- Path is `/`-separated identifiers.
- Non-paren call form is rewritten to explicit paren call.
- v1 supports host reads and host calls only (no host writes yet).

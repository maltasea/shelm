# Buoy Language Spec (Implemented v1)

## Status

This document is the normative language spec for the current implementation in this repository.

- Source file extension: `.by`
- Compiler entrypoint: `bin/buoy.ml`
- Frontend pipeline: `reader -> lexer -> parser -> tuple AST -> normalize -> macro_expand`
- Dedicated syntax grammar: `SYNTAX_SPEC.md`
- Language policy: speed-first, bytecode-first. Features with hidden runtime costs are excluded by default.

## Lexical Rules

- Line comment: `# ...` to end of line.
- Strings: double-quoted (`"..."`) with escapes `\n`, `\t`, `\\`, `\"`.
- Numbers:
  - Integer: `123`
  - Float: `123.45`
- Identifiers:
  - First char: `a-z`, `A-Z`, `_`
  - Rest: identifier chars plus digits plus `-` and `?`
- Keywords:
  - `let`, `fn`, `rec`, `if`, `else`, `while`, `for`, `in`, `return`
  - `type`, `enum`, `break`, `continue`
  - `true`, `false`, `nil`, `not`, `and`, `or`

## Source Rewriting (Reader Layer)

The reader enforces keyword/end block syntax and normalizes source before lexing/parsing.

### Canonical Block Form

- Canonical blocks are keyword/end style:
  - `if cond then ... end`
  - `while cond do ... end`
  - `for x in xs do ... end`
  - `foreach x in xs do ... end`
  - `enum name do ... end`
  - `fn name ... do ... end`
  - `match expr with ... end`
- Brace/colon block forms are rejected.
- `if ... do`/`elif ... do`/`else do` are rejected.

### Additional Reader Sugar

- `unless cond do ... end` rewrites to `if not (cond) ... end`
- `foreach x in xs do ... end` rewrites to `for x in xs do ... end`
- Call sugar rewrites:
  - `print x` -> `print(x)`
  - `f a, b` -> `f(a, b)`
  - Applies to non-keyword call heads.

### FFI Sugar

- Host read:
  - `$foo/bar` -> `host_get("foo/bar")`
- Host call:
  - `&foo/bar(a, b)` -> `host_call("foo/bar", a, b)`
  - `&foo/bar a, b` -> `host_call("foo/bar", a, b)`

### Regex Shorthand

- `#"...pattern..."` rewrites to `/...pattern.../`

## Program Structure

- A program is a newline-separated list of statements.
- Blocks contain nested statement lists.
- Empty lines are allowed.

## Statements

- `type Name = expr` (compile-time declaration)
- `enum Name do ... end`
- `let name = expr`
- `name = expr`
- `target[index] = expr`
- `if cond then ... elif cond then ... else ... end`
- `match expr with | pattern -> ... end`
- `while cond do ... end`
- `for name in expr do ... end`
- `foreach name in expr do ... end`
- `break`
- `continue`
- Function definitions:
  - `fn name do ... end`
  - `fn name x do ... end`
  - `fn name x, y do ... end`
  - `fn name(x, y) do ... end`
  - `fn name ... do ... end`
  - `rec fn ...` variants are also supported.
- `return expr` (expression is required)
- Expression statement (`expr`)

## Expressions

- Literals:
  - `int`, `float`, `string`, `true`, `false`, `nil`
  - arrays: `[a, b, c]`
  - hashes: `{k: v, ...}`
  - regex: `/pattern/flags`
- Variables: `name`
- Indexing: `expr[index]`
- Function calls: `f(...)`

### Operators and Precedence

From lowest to highest:

1. `or`
2. `and`
3. `==`, `!=`, `<`, `>`, `<=`, `>=`
4. `=~`, `!~` (regex match / not match)
5. `+`, `-`
6. `++` (string concat)
7. `*`, `/`, `%`
8. Unary `-`, unary `not`
9. Postfix call/index

## Builtins (Cross-Backend in Current Implementation)

These names are recognized consistently by Perl/OCaml/Go generators:

- `print`, `println`
- `length`, `join`, `split`, `substr`, `replace`, `trim`, `uppercase`, `lowercase`, `reverse`
- `push`, `pop`, `shift`, `sort`, `unique`
- `keys`, `values`, `exists`, `delete`
- `regex_match`, `regex_replace`, `regex_find_all`
- `sqrt`, `sin`, `cos`, `abs`, `log`, `floor`, `ceil`, `random`
- `int_of`, `float_of`, `string_of`
- `open`, `close`, `readline`, `read_file`, `writeln`
- `async`, `await` (implemented as synchronous future stubs in generators)

## Not In Implemented v1

The following are not part of the implemented parser/AST surface today:

- Algebraic enum payload constructors (e.g. `Some(x)` from enum declaration)
- Static type checking/inference
- Implicit closures / lambda expressions
- TCO guarantees

## Match / Case

- `match` is a statement form.
- Cases are evaluated top-to-bottom.
- `match` evaluates the scrutinee once, then compares with `==` semantics.
- Wildcard case:
  - `| _ -> ...`

Example:

```buoy
match x with
  | 1 -> println("one")
  | 2 -> println("two")
  | _ -> println("other")
end
```

`case` block forms are not accepted in source; use `| pattern -> ...`.

## Type / Enum

- `type` declarations are accepted and carried through AST/bytecode lowering.
- Backends currently treat `type` as compile-time-only metadata (no runtime checks).
- `enum` declares runtime constants for variants.
  - Runtime value format is a compact integer tag (`0..n-1` by declaration order).
  - Example:
    ```buoy
    enum color do
      red
      green
    end
    ```
    - `red` and `green` become bound values.

## Loop Control

- `break` exits the nearest loop.
- `continue` skips to the next iteration of the nearest loop.

## Performance Contract

- Bytecode target is the optimization anchor.
- No implicit closure allocation in surface syntax.
- No mandatory TCO requirement.
- Features that impose broad runtime overhead are excluded unless explicitly opted-in in a future profile.

## Bytecode Target Notes

- `--target bytecode` emits textual `.bytecode 1` assembly generated from tuple AST.
- Current bytecode output contract is defined by implementation in `lib/bytecode.ml`.

## Conformance Command

Use:

```bash
scripts/check-conformance.sh
```

This runs build/tests, validates CLI rules, compiles all `.by` examples/benchmarks for every target, checks keyword/end-only syntax enforcement, and verifies benchmark mode.

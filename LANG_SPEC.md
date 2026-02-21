# Shelm Language Spec (Implemented v1)

## Status

This document is the normative language spec for the current implementation in this repository.

- Source file extension: `.shlm`
- Compiler entrypoint: `bin/shelm.ml`
- Frontend pipeline: `reader -> lexer -> parser -> tuple AST -> normalize -> macro_expand`
- Language policy: speed-first, bytecode-first. Features with hidden runtime costs are excluded by default.

## Lexical Rules

- Line comment: `# ...` to end of line.
- Strings: double-quoted (`"..."`) with escapes `\n`, `\t`, `\\`, `\"`.
- Numbers:
  - Integer: `123`
  - Float: `123.45`
- Identifiers:
  ```ebnf
  ident_start = "A".."Z" | "a".."z" | "_" ;
  ident_char  = ident_start | "0".."9" | "-" | "?" ;
  ident       = ident_start , { ident_char } ;
  ```
- Keywords:
  - `let`, `def`, `defun`, `fun`, `if`, `else`, `while`, `foreach`, `in`, `return`
  - `type`, `enum`, `break`, `continue`
  - `true`, `false`, `nil`, `not`, `and`, `or`
- Keyword literals:
  - postfix lowercase: `kw:`
  - prefix lowercase: `:kw`
- Type names in annotations/signatures are `Ucfirst` identifiers (`Int`, `String`, `Person`).

## Source Rewriting (Reader Layer)

The reader enforces keyword/end block syntax and normalizes source before lexing/parsing.

### Canonical Block Form

- Canonical blocks are keyword/end style:
  - `if cond then ... end`
  - `while cond do ... end`
  - `foreach x in xs do ... end`
  - `enum name do ... end`
  - `defun name ... do ... end`
  - `match expr with ... end`
- Brace/colon block forms are rejected.
- `if ... do`/`elif ... do`/`else do` are rejected.

### Line-Based Evaluation

Shelm is line-based. Each line is collected as a single expression or statement up to the end of line.

- `print "hello" "you"` -- everything after `print` on the line is its arguments.
- Commas between arguments are optional on a normal line: `print a b` and `print a, b` are equivalent.

### Parenthesized Expressions

Parentheses have two distinct roles, determined by content:

- **Arglist**: `(a, b, c)` -- contains commas, produces an argument list.
- **Infix expression**: `(a > b)` -- no commas, contains an infix operator, produces a single value.

Infix operators (`+`, `-`, `*`, `/`, `%`, `<`, `>`, `<=`, `>=`, `==`, `!=`, `and`, `or`, `++`, `=~`, `!~`) are only valid inside parenthesized infix expressions. Bare infix on a line is not allowed:
- `(a + b)` -- valid infix expression.
- `a + b` -- not valid as a standalone expression (infix must be parenthesized).

Infix expressions must stand alone or appear as arguments. They cannot appear directly after a block keyword:
- `if (a > b) then` -- not allowed (infix expression attached to keyword).
- `if cond then` -- valid (simple identifier condition).

### Call Forms

All of these are equivalent:

- `print a b` -- space-separated arguments
- `print a, b` -- comma-separated arguments
- `print (a, b)` -- arglist in parentheses (space before `(`)
- `print(a, b)` -- arglist in parentheses (no space before `(`)

The space before `(` determines how a parenthesized group is interpreted when it follows a call head:

- `f(...)` (no space) -- the `(...)` is always an arglist. Bare infix inside is invalid:
  - `print(a, b)` -- valid, arglist with two arguments.
  - `print(a > b)` -- **not valid**, because `(...)` is an arglist and `a > b` is bare infix without parenthesization.
- `f (...)` (space before `(`) -- the `(...)` is a standalone parenthesized expression passed as an argument:
  - `print (a > b)` -- **valid**, `(a > b)` is an infix expression producing a single value passed to `print`.
  - `print (a, b)` -- valid, `(a, b)` is an arglist.

### Additional Reader Sugar

- `unless cond do ... end` rewrites to `if not (cond) ... end`
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

## Surface Syntax EBNF

The surface syntax is keyword/end only. Blocks are explicit and closed with `end`.

### Program

```ebnf
program = { surface_statement , sep } , [ surface_statement ] , eof ;
sep     = newline , { newline } ;
```

### Block Headers (Canonical)

- `if <expr> then ... end`
- `elif <expr> then`
- `while <expr> do ... end`
- `foreach <name> in <expr> do ... end`
- `enum <name> do ... end`
- `defun ... do ... end`
- `match <expr> with ... end`

`match` cases use pipe syntax:

- `| <pattern> -> <expr>`
- `| <pattern> ->` followed by multiline case body

### Rejected Block Forms

The reader rejects these forms:

- Brace blocks: `if ... { ... }`, `while ... { ... }`, etc.
- Colon blocks: `if ...: ... end`, `match ...: ... end`, etc.
- `if ... do`, `elif ... do`, `else do`
- `else if ...` (use `elif ... then`)
- `case ... { ... }` source cases (use `| pattern -> ...`)

### Surface Statements

```ebnf
surface_statement =
    "type" , ident , "=" , expr
  | enum_surface
  | "let" , ident , "=" , expr
  | "let" , ident , ":" , type_name , "=" , expr
  | "def" , ident , "=" , expr
  | "def" , ident , ":" , type_name , "=" , expr
  | ident , "=" , expr
  | postfix_expr , "[" , expr , "]" , "=" , expr
  | postfix_expr , "=~" , "s/" , regex_body , "/" , regex_body , "/" , regex_flags
  | if_surface
  | while_surface
  | foreach_surface
  | match_surface
  | defun_surface
  | "break"
  | "continue"
  | "return" , expr
  | expr ;

if_surface =
    "if" , expr , "then" , block_body , { "elif" , expr , "then" , block_body } , [ "else" , block_body ] , "end" ;

while_surface = "while" , expr , "do" , block_body , "end" ;
foreach_surface = "foreach" , ident , "in" , expr , "do" , block_body , "end" ;

enum_surface  = "enum" , ident , "do" , enum_variants_surface , "end" ;
enum_variants_surface = ident , { sep , ident } ;

match_surface = "match" , expr , "with" , match_pipe_case , { sep , match_pipe_case } , "end" ;
match_pipe_case = "|" , match_pattern , "->" , [ expr | block_body ] ;

defun_surface =
    "defun" , ident , [ return_sig ] , "do" , block_body , "end"
  | "defun" , ident , typed_bare_params , [ return_sig ] , "do" , block_body , "end"
  | "defun" , ident , "(" , [ typed_params ] , ")" , [ return_sig ] , "do" , block_body , "end" ;

bare_params = ident , { "," , ident } ;
params      = ident , { "," , ident } ;
typed_param = ident | ident , ":" , type_name ;
typed_bare_params = typed_param , { "," , typed_param } ;
typed_params = typed_param , { "," , typed_param } ;
return_sig = "=>" , type_name ;
type_name = ident ;  (* validated as Ucfirst by reader *)

block_body  = { surface_statement , sep } ;
```

### Reader Sugar Forms

Accepted and rewritten before parse:

1. `unless cond do ... end` -> `if not (cond) then ... end`
2. Call sugar:
   - `f x` -> `f(x)`
   - `f a, b` -> `f(a, b)`
3. FFI sugar:
   - `$foo/bar` -> `host_get("foo/bar")`
   - `&foo/bar(a, b)` -> `host_call("foo/bar", a, b)`
   - `&foo/bar a, b` -> `host_call("foo/bar", a, b)`
4. Regex shorthand:
   - `#"a+b"` -> `/a+b/`
5. Type annotations/signatures are accepted in surface syntax and erased in reader normalization:
   - `foo : Int`
   - `=> Int`
   - compact no-space `foo:Int` is rejected

## Normalized Core Grammar (Parser Input)

After reader rewrite, parser input uses braces and explicit `case` blocks internally.

```ebnf
program = sep_lines , terminated_stmts , eof ;

sep_lines = { newline } ;
sep       = newline , { newline } ;

terminated_stmts = [ stmt , terminated_tail ] ;
terminated_tail  = [ sep , stmt , terminated_tail ] | sep | empty ;

block = "{" , sep_lines , terminated_stmts , "}" ;
```

### Core Statements

```ebnf
stmt =
    "type" , ident , "=" , expr
  | "enum" , ident , enum_block
  | "let" , ident , "=" , expr
  | "def" , ident , "=" , expr
  | ident , "=" , expr
  | postfix_expr , "[" , expr , "]" , "=" , expr
  | postfix_expr , regex_replace
  | "match" , expr , match_block
  | "if" , expr , block
  | "if" , expr , block , "else" , block
  | "if" , expr , block , "else" , else_if
  | "while" , expr , block
  | "foreach" , ident , "in" , expr , block
  | "break"
  | "continue"
  | defun_def
  | "return" , expr
  | expr ;

regex_replace = "=~" , "s/" , regex_body , "/" , regex_body , "/" , regex_flags ;

else_if =
    "if" , expr , block
  | "if" , expr , block , "else" , block
  | "if" , expr , block , "else" , else_if ;

defun_def =
    "defun" , ident , block
  | "defun" , ident , bare_params , block
  | "defun" , ident , "(" , [ params ] , ")" , block ;

enum_block  = "{" , sep_lines , [ enum_variants ] , "}" ;
enum_variants = ident , { ("," | sep) , ident } , [ "," | sep ] ;

match_block = "{" , sep_lines , [ match_case , { sep , match_case } , [ sep ] ] , "}" ;
match_case  = "case" , match_pattern , block ;
match_pattern = "_" | expr ;
```

### Core Expressions

```ebnf
expr         = or_expr ;
or_expr      = and_expr , { "or" , and_expr } ;
and_expr     = cmp_expr , { "and" , cmp_expr } ;
cmp_expr     = match_expr , { ("==" | "!=" | "<" | ">" | "<=" | ">=") , match_expr } ;
match_expr   = add_expr
             | match_expr , "=~" , regex_lit
             | match_expr , "!~" , regex_lit ;
add_expr     = concat_expr , { ("+" | "-") , concat_expr } ;
concat_expr  = mul_expr , { "++" , mul_expr } ;
mul_expr     = unary_expr , { ("*" | "/" | "%") , unary_expr } ;
unary_expr   = postfix_expr | "-" , unary_expr | "not" , unary_expr ;

postfix_expr = primary_expr , { call_suffix | index_suffix } ;
call_suffix  = "(" , [ arg_list ] , ")" ;
index_suffix = "[" , expr , "]" ;
arg_list     = expr , { "," , expr } ;

primary_expr =
    int_lit
  | float_lit
  | string_lit
  | keyword_lit
  | "true"
  | "false"
  | "nil"
  | ident
  | fun_expr
  | "(" , expr , ")"
  | "[" , [ array_elems ] , "]"
  | "{" , [ hash_pairs ] , "}"
  | regex_lit ;

fun_expr =
    "fun" , block
  | "fun" , bare_params , block
  | "fun" , "(" , [ params ] , ")" , block ;

keyword_lit = ident , ":" | ":" , ident ;

array_elems = expr , { "," , expr } ;
hash_pairs  = hash_pair , { "," , hash_pair } ;
hash_pair   = expr , ":" , expr | keyword_lit , expr ;
```

## Deterministic Rewrites (Surface -> Core)

1. `if <e> then` -> `if <e> {`
2. `elif <e> then` -> `} else if <e> {`
3. `else` -> `} else {`
4. `while <e> do` -> `while <e> {`
5. `foreach <x> in <e> do` -> `foreach <x> in <e> {`
6. `enum <name> do` -> `enum <name> {`
7. `defun ... do` -> `defun ... {`
8. `fun ... do` -> `fun ... {`
9. `match <e> with` -> `match <e> {`
10. `| <pat> -> <expr>` -> `case <pat> { <expr> }`
11. `| <pat> ->` -> `case <pat> {` (multiline case body)
12. `end` closes the innermost open block; for an open multiline match case it closes the case first, then `match`.

## Statements

- `type Name = expr` (compile-time declaration)
- `enum Name do ... end`
- `let name = expr`
- `let name : Type = expr` (annotation is parsed then erased before codegen)
- `def name : Type = expr` (annotation is parsed then erased before codegen)
- `name = expr`
- `target[index] = expr`
- `if cond then ... elif cond then ... else ... end`
- `match expr with | pattern -> ... end`
- `while cond do ... end`
- `foreach name in expr do ... end`
- `break`
- `continue`
- Function definitions:
  - `defun name do ... end`
  - `defun name x do ... end`
  - `defun name x, y do ... end`
  - `defun name(x, y) do ... end`
  - `defun name ... do ... end`
  - typed params/returns are allowed:
    - `defun add(x : Int, y : Int) => Int do ... end`
- Value/function bindings:
  - `def name = expr`
  - `let name = expr`
  - `let f = fun x, y do ... end`
  - `let f = fun(x : Int) => Int do ... end` (signature parsed then erased before codegen)
- `return expr` (expression is required)
- Expression statement (`expr`)

## Expressions

- Literals:
  - `9` (int)
  - `8.3` (float)
  - `"hello"` (string)
  - `true/false` (bool)
  - `nil`
  - `name:` or `:name` (keyword literal; both evaluate to string `"name"`)
  - `Name:` or `:Name` -- not allowed (keyword literals must be lowercase)
- Arrays: `[a, b, c]`
- Maps/Dicts: `{ name: "bernd", age: 88 }` (keyword-key style)
- Regex: `/pattern/flags`
- Variables: `name`
- Indexing: `expr[index]`
- Function calls: `f(...)` (see Call Forms above for equivalences)
- Parenthesized infix: `(a > b)` (see Parenthesized Expressions above)
- `Ucfirst` identifiers are type names, not valid in surface expressions.
- `Ucfirst(8)` (sum type with payload) is not allowed in surface syntax.
- `foo:Int` (compact type annotation) is not allowed; use `foo : Int`.

### Operators and Precedence

Infix operators are only valid inside parenthesized expressions (see Parenthesized Expressions).

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
- Capturing closures
- TCO guarantees
- `rec` keyword forms
- `fn` keyword forms
- `for` loop keyword forms

## Match / Case

- `match` is a statement form.
- Cases are evaluated top-to-bottom.
- `match` evaluates the scrutinee once, then compares with `==` semantics.
- Wildcard case:
  - `| _ -> ...`

Example:

```shelm
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
- Surface annotations/signatures are accepted in v1:
  - variable/binding annotation: `foo : Int`
  - return signature: `=> Int`
- Current implementation erases these annotations/signatures in the reader layer before parse/codegen.
- Compact no-space forms like `foo:Int`/`kw:Int` are rejected.
- `enum` declares runtime constants for variants.
  - Runtime value format is a compact integer tag (`0..n-1` by declaration order).
  - Example:
    ```shelm
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

## Syntax Exclusions

- No `fn` forms.
- No `rec` forms.
- No `for` forms.
- No closure/capture syntax.
- No semicolon-separated statement grammar.
- No bare infix outside parentheses (e.g. `a + b` alone on a line).
- No infix expressions directly after block keywords (e.g. `if(a > b) then`).
- No uppercase keyword literals (`Name:`, `:Name`).
- No compact type annotations (`foo:Int`); use `foo : Int`.
- No `Ucfirst` sum type constructors with payload in surface syntax (`Ucfirst(8)`).

## Conformance Command

Use:

```bash
scripts/check-conformance.sh
```

This runs build/tests, validates CLI rules, compiles all `.shlm` examples/benchmarks for every target, checks keyword/end-only syntax enforcement, and verifies benchmark mode.

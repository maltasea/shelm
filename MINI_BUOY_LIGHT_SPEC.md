# Mini Buoy Light (Syntax-Only Profile)

This document defines **Mini Buoy Light** as a small, shell-like surface syntax profile in the Buoy family.

Status:
- Spec only.
- No runtime/VM/bytecode changes implied.
- No semantic changes implied.

Purpose:
- Provide a smaller language shape for derivative languages that should feel like a reduced Buoy.
- Keep deterministic lowering to Buoy core forms by syntax shape only (no semantic analysis).

## 1) Design Constraints

1. Syntax should be lightweight and script-like.
2. No static typing surface.
3. No complex pattern matching.
4. Only basic value kinds in source.
5. Explicit block markers (`then`/`do`/`with` + `end`), no significant whitespace.

## 2) Allowed Surface Constructs

### 2.1 Program

- Program is newline-separated statements.
- Empty lines and `# ...` comments allowed.

### 2.2 Statements

1. Local binding: `let name = expr`
2. Reassignment: `name = expr`
3. Index assignment: `target[index] = expr`
4. Conditionals:
   - `if expr then ... end`
   - `if expr then ... elif expr then ... else ... end`
5. Loops:
   - `while expr do ... end`
   - `for name in expr do ... end`
   - `foreach name in expr do ... end` (sugar)
6. Function defs (optional but allowed):
   - `fn name ... do ... end`
   - `rec fn name ... do ... end`
7. `return expr`
8. `break`, `continue`
9. Expression statement

### 2.3 Expressions

1. Literals: int, float, string, bool, nil
2. Arrays: `[a, b, c]`
3. String-key hashes: `{"k": v}`
4. Variable references: `name`
5. Calls: `f(...)` and call sugar `f a, b`
6. Indexing: `expr[index]`
7. Operators:
   - logical: `and`, `or`, `not`
   - compare: `==`, `!=`, `<`, `>`, `<=`, `>=`
   - arithmetic: `+`, `-`, `*`, `/`, `%`
   - concat: `++`
8. Regex usage (simple):
   - literal `/.../flags`
   - match `x =~ /.../`
   - non-match `x !~ /.../`
   - replace `x =~ s/a/b/g`

## 3) Forbidden In Light Profile

1. `type` declarations
2. `enum` declarations
3. `match ... with` / pipe-case matching
4. Source `case` blocks
5. Advanced type-level syntax
6. Feature forms that require semantic disambiguation to parse

## 4) Canonical Block Style

Only keyword/end style blocks are part of Light:

1. `if ... then ... end`
2. `while ... do ... end`
3. `for/foreach ... in ... do ... end`
4. `fn/rec fn ... do ... end`

Not part of Light:

1. Brace blocks `{ ... }`
2. Colon blocks `...: ... end`

## 5) Deterministic Lowering Contract (Light -> Buoy Core)

Lowering is syntactic:

1. `foreach x in xs do ... end` -> `for x in xs do ... end`
2. `f a, b` -> `f(a, b)` where call-sugar head is non-keyword identifier
3. `unless c do ... end` (if included by a dialect) -> `if not (c) then ... end`
4. FFI sugar (if enabled by dialect):
   - `$a/b` -> `host_get("a/b")`
   - `&a/b(...)` -> `host_call("a/b", ...)`

Lowering target is Buoy core statement/expression forms; this profile does not define a separate runtime.

## 6) Minimal EBNF (Surface)

```ebnf
program = { stmt , sep } , [ stmt ] , eof ;
sep     = newline , { newline } ;

stmt =
    "let" , ident , "=" , expr
  | ident , "=" , expr
  | postfix_expr , "[" , expr , "]" , "=" , expr
  | if_stmt
  | while_stmt
  | for_stmt
  | fn_stmt
  | "return" , expr
  | "break"
  | "continue"
  | expr ;

if_stmt =
  "if" , expr , "then" , block ,
  { "elif" , expr , "then" , block } ,
  [ "else" , block ] ,
  "end" ;

while_stmt = "while" , expr , "do" , block , "end" ;
for_stmt   = ("for" | "foreach") , ident , "in" , expr , "do" , block , "end" ;

fn_stmt =
    "fn" , ident , [ params ] , "do" , block , "end"
  | "rec" , "fn" , ident , [ params ] , "do" , block , "end" ;

params = ident , { "," , ident } ;
block  = { stmt , sep } ;
```

## 7) Example

```buoy
let total = 0
for x in [1, 2, 3, 4] do
  total = total + x
end

if total > 5 then
  println("big")
else
  println("small")
end
```

## 8) Conformance Scope (for future implementation)

A Light implementation is conformant if:

1. It accepts only the allowed Light surface constructs.
2. It rejects forbidden Light constructs.
3. It lowers accepted programs to Buoy core-equivalent forms without semantic analysis.

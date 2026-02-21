# Shelm Syntax Specification (Implemented)

This document defines the implemented `.shlm` syntax.

It has two layers:

1. Surface syntax (user source, keyword/end only for blocks).
2. Normalized core syntax (internal brace form consumed by parser).

Lowering from surface to core is form-based and does not require semantic analysis.

## 1) Lexical Syntax

### 1.1 Whitespace and separators

- Space/tab are insignificant.
- Newline separates statements.
- Empty lines are allowed.
- Semicolons are not part of the grammar.

### 1.2 Comments

- Line comment: `# ...` to end of line.

### 1.3 Literals

- Integer: `9` (example)
- Float: `8.3` (example)
- String: `"hello"` with escapes `\n`, `\t`, `\\`, `\"`
- Booleans: `true/false` (bool)
- Nil: `nil`
- Keyword literal: `name:` (evaluates to string `"name"`)
- Map/Dict literal example: `{ name: "bernd", age: 88 }`
- Regex literal: `/pattern/flags` where flags are `[gimsx]*`

### 1.4 Identifiers

```ebnf
ident_start = "A".."Z" | "a".."z" | "_" ;
ident_char  = ident_start | "0".."9" | "-" | "?" ;
ident       = ident_start , { ident_char } ;
```

### 1.5 Keywords

Parser keywords:

`let def defun fun if else while foreach in return match case type enum break continue true false nil not and or`

Reader block keywords:

`then elif with do end foreach unless`

## 2) Surface Syntax (User Source)

### 2.1 Program

```ebnf
program = { surface_statement , sep } , [ surface_statement ] , eof ;
sep     = newline , { newline } ;
```

Blocks are explicit and closed with `end`.

### 2.2 Block headers (canonical)

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

### 2.3 Rejected block forms

The reader rejects these forms:

- Brace blocks: `if ... { ... }`, `while ... { ... }`, etc.
- Colon blocks: `if ...: ... end`, `match ...: ... end`, etc.
- `if ... do`, `elif ... do`, `else do`
- `else if ...` (use `elif ... then`)
- `case ... { ... }` source cases (use `| pattern -> ...`)

### 2.4 Surface statements

```ebnf
surface_statement =
    "type" , ident , "=" , expr
  | enum_surface
  | "let" , ident , "=" , expr
  | "def" , ident , "=" , expr
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
    "defun" , ident , "do" , block_body , "end"
  | "defun" , ident , bare_params , "do" , block_body , "end"
  | "defun" , ident , "(" , [ params ] , ")" , "do" , block_body , "end" ;

bare_params = ident , { "," , ident } ;
params      = ident , { "," , ident } ;

block_body  = { surface_statement , sep } ;
```

### 2.5 Reader sugar forms

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

## 3) Normalized Core Grammar (Parser Input)

After reader rewrite, parser input uses braces and explicit `case` blocks internally.

```ebnf
program = sep_lines , terminated_stmts , eof ;

sep_lines = { newline } ;
sep       = newline , { newline } ;

terminated_stmts = [ stmt , terminated_tail ] ;
terminated_tail  = [ sep , stmt , terminated_tail ] | sep | empty ;

block = "{" , sep_lines , terminated_stmts , "}" ;
```

### 3.1 Core statements

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

### 3.2 Core expressions

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

keyword_lit = ident , ":" ;

array_elems = expr , { "," , expr } ;
hash_pairs  = hash_pair , { "," , hash_pair } ;
hash_pair   = expr , ":" , expr | keyword_lit , expr ;
```

## 4) Deterministic Rewrites (Surface -> Core)

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

## 5) Syntax-Level Exclusions

- No `fn` forms.
- No `rec` forms.
- No `for` forms.
- No type annotation/signature forms (for bindings, params, or returns).
- No closure/capture syntax.
- No semicolon-separated statement grammar.

# Mini Shelm Light (Short Spec)

Mini Shelm Light is a small surface profile.

## Required Surface Keywords

- `let`
- `def`
- `defun`
- `fun`
- `foreach`

## Statements

- `let name = expr`
- `def name = expr`
- `defun name [params] do ... end`
- `name = expr`
- `target[index] = expr`
- `if expr then ... [elif expr then ...] [else ...] end`
- `while expr do ... end`
- `foreach name in expr do ... end`
- `return expr`
- `break`
- `continue`
- expression statement

## Expressions

- literals:
  - `9` (int)
  - `8.3` (float)
  - `"hello"` (string)
  - `true` / `false` (bool)
  - `nil`
- arrays: `[a, b, c]`
- maps/dicts: `{ name: "bernd", age: 88 }`
- variable refs: `name`
- calls: `f(...)` and `f a, b`
- indexing: `expr[index]`
- operators: `and or not == != < > <= >= + - * / % ++`
- regex: `/.../flags`, `x =~ /.../`, `x !~ /.../`, `x =~ s/a/b/g`
- function value: `fun [params] do ... end`
- keyword literal: `name:` (evaluates to string `"name"`)

## Not In Light

- `rec`
- `fn`
- `for`
- type annotations/signatures

## Minimal EBNF

```ebnf
program = { stmt , sep } , [ stmt ] , eof ;
sep     = newline , { newline } ;

stmt =
    "let" , ident , "=" , expr
  | "def" , ident , "=" , expr
  | "defun" , ident , [ params ] , "do" , block , "end"
  | ident , "=" , expr
  | postfix_expr , "[" , expr , "]" , "=" , expr
  | if_stmt
  | while_stmt
  | foreach_stmt
  | "return" , expr
  | "break"
  | "continue"
  | expr ;

if_stmt =
  "if" , expr , "then" , block ,
  { "elif" , expr , "then" , block } ,
  [ "else" , block ] ,
  "end" ;

while_stmt   = "while" , expr , "do" , block , "end" ;
foreach_stmt = "foreach" , ident , "in" , expr , "do" , block , "end" ;
fun_expr     = "fun" , [ params ] , "do" , block , "end" ;
keyword_lit  = ident , ":" ;

params = ident , { "," , ident } ;
block  = { stmt , sep } ;
```

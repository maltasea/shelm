# Learn Shelm in 5 Minutes

Shelm is a small, line-based language that compiles to Perl, OCaml, Go, and bytecode. It has keyword/end blocks, optional commas, and a relaxed call syntax.

```shelm
# This is a comment
println("Hello, Shelm!")
```

## Variables

Use `let` or `def` to bind a value. Reassign with `=`.

```shelm
let name = "Alice"
def age = 30
let pi = 3.14

name = "Bob"       # reassign
age = age + 1
```

## Types

Shelm has integers, floats, strings, booleans, nil, arrays, and hashes.

```shelm
let n = 42
let f = 3.14
let s = "hello\n"
let yes = true
let no = false
let nothing = nil

let colors = ["red", "green", "blue"]
let person = {name: "Alice", age: 30}
```

### Keywords

Keywords are bareword strings. Postfix `name:` and prefix `:name` both evaluate to `"name"`.

```shelm
let key = name:          # "name"
let alt = :role          # "role"
let h = {name: "Alice", :age 30, active: true}
```

## Operators

Arithmetic and comparison go inside parentheses when used standalone. Inside function calls and `if`/`while` conditions they work naturally.

```shelm
let sum = (x + y)
let diff = (x - y)
let prod = (x * y)
let quot = (x / y)
let rem = (x % y)

println(string_of(x + y))    # fine inside a call
```

String concatenation uses `++`:

```shelm
let greeting = "Hello, " ++ name ++ "!"
```

Comparison:

```shelm
if x == y then println("equal") end
if x != y then println("different") end
if x < y then println("less") end
# also >, <=, >=
```

Logical operators:

```shelm
if x > 0 and x < 100 then
  println("in range")
end

if done or timeout then
  println("stop")
end

if not ready then
  println("wait")
end
```

## Control Flow

### If / Elif / Else

```shelm
if score > 90 then
  println("A")
elif score > 80 then
  println("B")
elif score > 70 then
  println("C")
else
  println("F")
end
```

The line-based call model works inside blocks too — parentheses around arguments are optional:

```shelm
if a then
  println("x")
end

if a then
  println "x"
end
```

### While

```shelm
let i = 0
while i < 5 do
  println(string_of(i))
  i = i + 1
end
```

### Foreach

```shelm
let fruits = ["apple", "banana", "cherry"]
foreach fruit in fruits do
  println(fruit)
end
```

### Unless

`unless` is the inverse of `if` — it runs the body when the condition is false:

```shelm
unless ready do
  println("waiting...")
end
```

### Break and Continue

```shelm
let i = 0
while i < 100 do
  i = i + 1
  if i % 2 == 0 then
    continue
  end
  if i > 10 then
    break
  end
  println(string_of(i))
end
```

## Functions

Define functions with `defun`. Call them by name.

```shelm
defun greet name do
  println("Hello, " ++ name ++ "!")
end

greet("Shelm")
```

Parameters can be bare (space/comma separated) or parenthesized:

```shelm
defun add x, y do
  return x + y
end

defun multiply(a, b) do
  return a * b
end

println(string_of(add(2, 3)))
println(string_of(multiply(4, 5)))
```

### Function Values (Lambdas)

```shelm
let double = fun(x) do
  return x * 2
end

println(string_of(double(21)))
```

### Recursion

```shelm
defun factorial n do
  if n <= 1 then
    return 1
  end
  return n * factorial(n - 1)
end

println(string_of(factorial(6)))   # 720
```

## Arrays

```shelm
let nums = [5, 3, 1, 4, 2]

println(string_of(length(nums)))   # 5

push(nums, 6)                      # add to end
let last = pop(nums)               # remove from end
let first = shift(nums)            # remove from front

let sorted = sort(nums)
let reversed = reverse(nums)
let uniq = unique([1, 2, 2, 3])

# index access
println(string_of(nums[0]))
nums[0] = 99
```

### Higher-Order Functions

```shelm
let nums = [1, 2, 3, 4, 5]

let doubled = map(nums, fun(x) do return x * 2 end)
let evens = filter(nums, fun(x) do return x % 2 == 0 end)
each(nums, fun(x) do println(string_of(x)) end)
```

## Hashes

```shelm
let colors = {"apple": "red", "banana": "yellow"}

println(colors["apple"])           # red
colors["cherry"] = "red"           # add entry

let k = keys(colors)
let v = values(colors)

if exists(colors["banana"]) then
  println("found it")
end

delete(colors["banana"])
```

## Strings

```shelm
let s = "Hello, World!"

println(string_of(length(s)))      # 13
println(uppercase(s))              # HELLO, WORLD!
println(lowercase(s))              # hello, world!
println(reverse(s))                # !dlroW ,olleH
println(substr(s, 0, 5))           # Hello
println(trim("  hi  "))            # hi
println(replace(s, "World", "Shelm"))

let parts = split(",", "a,b,c")   # ["a", "b", "c"]
println(join(" - ", parts))        # a - b - c
```

## Regex

```shelm
let text = "The year is 2024"

if text =~ ~r/\d+/ then
  println("contains a number")
end

if text !~ ~r/[A-Z]{3}/ then
  println("no three uppercase letters")
end

# in-place substitution
text =~ s/2024/2025/g
println(text)                      # The year is 2025
```

## Pattern Matching

```shelm
let status = 404

match status with
  | 200 -> println("OK")
  | 404 -> println("Not Found")
  | 500 -> println("Server Error")
  | _ -> println("Unknown")
end
```

Cases can have multi-line bodies:

```shelm
match command with
  | "quit" ->
    println("Goodbye")
    return 0
  | "help" ->
    println("Available commands: quit, help")
  | _ ->
    println("Unknown command: " ++ command)
end
```

## Enums

```shelm
enum Direction do
  north
  south
  east
  west
end

let heading = north

match heading with
  | north -> println("Going up")
  | south -> println("Going down")
  | _ -> println("Going sideways")
end
```

## Type Annotations

Shelm supports optional type annotations. They're parsed but erased before compilation -- no static checking in v1.

```shelm
def age : Int = 25
def name : String = "Alice"

defun add(x : Int, y : Int) => Int do
  return x + y
end

let double = fun(v : Int) => Int do
  return v * 2
end
```

## Math

```shelm
println(string_of(sqrt(16)))       # 4
println(string_of(abs(-7)))        # 7
println(string_of(floor(3.7)))     # 3
println(string_of(ceil(3.2)))      # 4
println(string_of(sin(0)))         # 0
println(string_of(cos(0)))         # 1
println(string_of(log(1)))         # 0

let r = random()                   # 0.0 to 1.0
let d = random(6)                  # 0.0 to 6.0
```

## Type Conversion

```shelm
let n = int_of("42")              # 42
let f = float_of("3.14")          # 3.14
let s = string_of(42)             # "42"
```

## File I/O

```shelm
# Read a file
let fh = open("data.txt")
let line = readline(fh)
while line != nil do
  println(line)
  line = readline(fh)
end
close(fh)

# Read entire file at once
let contents = read_file("data.txt")

# Write to a file
let out = open("output.txt", ">")
writeln(out, "Hello, file!")
close(out)
```

## The Line-Based Call Model

Shelm collects arguments until the end of a line. Commas are optional. These are all equivalent:

```shelm
foo "aa" b                # the naked arglist
foo ("aa", b)             # foo with arglist
foo("aa", b)              # no whitespace needed for arglists
```

A standalone parenthesized expression without commas is treated as an infix expression, not an arglist:

```shelm
print (x + y)             # one arg: the value of x + y
print(x, y)               # two args: x and y
```

## Compiling

Shelm files use the `.shlm` extension. Compile to any of four targets:

```bash
shelm hello.shlm --target perl      # generates Perl
shelm hello.shlm --target ocaml     # generates OCaml
shelm hello.shlm --target go        # generates Go
shelm hello.shlm --target bytecode  # generates bytecode
```

## Quick Reference

| Feature | Syntax |
|---|---|
| Variable | `let x = 1` or `def x = 1` |
| Reassign | `x = 2` |
| If | `if ... then ... elif ... else ... end` |
| Unless | `unless ... do ... end` |
| While | `while ... do ... end` |
| Foreach | `foreach x in xs do ... end` |
| Function | `defun name x, y do ... end` |
| Lambda | `fun(x) do ... end` |
| Match | `match x with \| 1 -> ... \| _ -> ... end` |
| Enum | `enum Color do red green blue end` |
| Array | `[1, 2, 3]` |
| Hash | `{name: "val"}` |
| Concat | `"a" ++ "b"` |
| Regex literal | `~r/pat/flags` |
| Regex match | `s =~ ~r/pat/` |
| Regex replace | `s =~ s/pat/repl/g` |
| Comment | `# comment` |

let contains_substring hay needle =
  let hlen = String.length hay in
  let nlen = String.length needle in
  if nlen = 0 then
    true
  else
    let rec loop i =
      if i + nlen > hlen then
        false
      else if String.sub hay i nlen = needle then
        true
      else
        loop (i + 1)
    in
    loop 0

let compile target source =
  match Shelm_lib.Shelm.compile_source_target target source with
  | Ok code -> code
  | Error err -> failwith (Shelm_lib.Errors.format_error err)

let compile_result target source =
  Shelm_lib.Shelm.compile_source_target target source

let compile_perl source = compile "perl" source
let compile_perl_result source = compile_result "perl" source
let compile_ocaml source = compile "ocaml" source
let compile_go source = compile "go" source
let compile_bytecode source = compile "bytecode" source

let assert_contains label hay needle =
  if not (contains_substring hay needle) then
    failwith (Printf.sprintf "%s: expected generated code to contain %S" label needle)

let assert_parse_error_contains label source needle =
  match compile_perl_result source with
  | Ok _ -> failwith (Printf.sprintf "%s: expected parse error" label)
  | Error err ->
    let msg = Shelm_lib.Errors.format_error err in
    if not (contains_substring msg needle) then
      failwith (Printf.sprintf "%s: expected error containing %S, got: %s" label needle msg)

let test_defun_defs_compile () =
  let source =
    {|
defun add x, y do
  return x + y
end
defun fact n do
  if n <= 1 then
    return 1
  end
  return n * fact(n - 1)
end
println(string_of(add(2, 3)))
println(string_of(fact(6)))
|}
  in
  let code = compile_perl source in
  assert_contains "defun-add" code "sub add { my $x = shift; my $y = shift;";
  assert_contains "defun-fact" code "sub fact { my $n = shift;";
  assert_contains "defun-call" code "add(2, 3)";
  assert_contains "defun-recursive-call" code "fact(6)"

let test_index_not_rewritten_as_call () =
  let source =
    {|
let colors = {"banana": "yellow"}
if exists(colors["banana"]) then
  println("ok")
end
delete(colors["banana"])
|}
  in
  let code = compile_perl source in
  assert_contains "exists-index" code "if (exists($colors{\"banana\"})) {";
  assert_contains "delete-index" code "delete($colors{\"banana\"});"

let test_keyword_literals_compile () =
  let source =
    {|
let key = name:
let alt = :name
let person = {name: "Shelm", :age 9, active: true}
println(key)
println(alt)
println(person["name"])
|}
  in
  let code = compile_perl source in
  assert_contains "keyword-literal" code "my $key = \"name\";";
  assert_contains "keyword-literal-prefix" code "my $alt = \"name\";";
  assert_contains "keyword-hash-name" code "\"name\" => \"Shelm\"";
  assert_contains "keyword-hash-age" code "\"age\" => 9";
  assert_contains "keyword-hash-active" code "\"active\" => 1";
  assert_contains "keyword-index-name" code "$person{\"name\"}"

let test_def_binding_compile () =
  let source =
    {|
def x = 41
def y = x + 1
println(string_of(y))
|}
  in
  let code = compile_perl source in
  assert_contains "def-x" code "my $x = 41;";
  assert_contains "def-y" code "my $y = ($x + 1);"

let test_match_case_compile () =
  let source =
    {|
let x = 2
match x with
  | 1 -> println("one")
  | 2 -> println("two")
  | _ -> println("other")
end
|}
  in
  let code = compile_perl source in
  assert_contains "match-subject" code "my $__match_1 = $x;";
  assert_contains "match-case-1" code "if (shelm_match_eq($__match_1, 1)) {";
  assert_contains "match-case-2" code "if (shelm_match_eq($__match_1, 2)) {";
  assert_contains "match-wildcard" code "if (1) {"

let test_type_enum_compile () =
  let source =
    {|
type age = int
enum color do
  red
  green
  blue
end
let c = green
match c with
  | red -> println("r")
  | _ -> println("x")
end
|}
  in
  let code = compile_perl source in
  assert_contains "enum-red" code "my $red = 0;";
  assert_contains "enum-green" code "my $green = 1;";
  assert_contains "enum-blue" code "my $blue = 2;";
  assert_contains "enum-match" code "if (shelm_match_eq($__match_1, $red)) {"

let test_break_continue_compile () =
  let source =
    {|
let i = 0
while i < 10 do
  i = i + 1
  if i == 3 then
    continue
  end
  if i == 7 then
    break
  end
end
|}
  in
  let code = compile_perl source in
  assert_contains "continue" code "next;";
  assert_contains "break" code "last;"

let test_fun_expr_compile () =
  let source =
    {|
let f = fun(x) do
  return x * 2
end
|}
  in
  let code = compile_perl source in
  assert_contains "fun-expr-let" code "my $f = sub { my $x = shift;";
  assert_contains "fun-expr-body" code "return ($x * 2);"

let test_typed_signatures_compile () =
  let source =
    {|
def age : Int = 41
defun add(x : Int, y : Int) => Int do
  return x + y
end
let double = fun(v : Int) => Int do
  return v * 2
end
println(string_of(add(age, 1)))
println(string_of(double(3)))
|}
  in
  let code = compile_perl source in
  assert_contains "typed-def" code "my $age = 41;";
  assert_contains "typed-defun" code "sub add { my $x = shift; my $y = shift;";
  assert_contains "typed-fun-value" code "my $double = sub { my $v = shift;";
  assert_contains "typed-defun-call" code "add($age, 1)";
  assert_contains "typed-fun-call" code "double(3)"

let test_compact_colon_upper_rejected () =
  let source =
    {|
let v = kw:Int
|}
  in
  assert_parse_error_contains "compact-colon" source "is not supported"

let test_upper_postfix_keyword_rejected () =
  let source =
    {|
let m = {Name: 1}
|}
  in
  assert_parse_error_contains "upper-postfix-keyword" source "Postfix keyword literals must be lowercase"

let test_legacy_fn_rejected () =
  let source =
    {|
fn add x, y do
  return x + y
end
|}
  in
  match compile_perl_result source with
  | Ok _ -> failwith "legacy fn syntax should be rejected"
  | Error err ->
    let msg = Shelm_lib.Errors.format_error err in
    if not (contains_substring msg "not supported") then
      failwith (Printf.sprintf "expected compatibility rejection for fn syntax, got: %s" msg)

let test_legacy_for_rejected () =
  let source =
    {|
for x in [1, 2] do
  println(x)
end
|}
  in
  assert_parse_error_contains "legacy-for" source "`for` is not supported"

let test_brace_blocks_rejected () =
  let source =
    {|
let x = 3
if x > 2 {
  println("ok")
}
|}
  in
  assert_parse_error_contains "brace-blocks" source "Brace blocks are not supported"

let test_colon_blocks_rejected () =
  let source =
    {|
let x = 3
if x > 2:
  println("ok")
end
|}
  in
  assert_parse_error_contains "colon-blocks" source "Colon blocks are not supported"

let test_if_do_rejected () =
  let source =
    {|
let x = 1
if x == 1 do
  println("ok")
end
|}
  in
  assert_parse_error_contains "if-do" source "`if ... do` is not supported"

let test_keyword_end_blocks_compile () =
  let source =
    {|
let total = 0
let xs = [1, 2, 3, 4]
foreach x in xs do
  total = total + x
end
if total > 3 then
  println("big")
elif total == 0 then
  println("zero")
else
  println("small")
end
while total > 0 do
  total = total - 1
  if total == 2 then
    continue
  end
  if total == 1 then
    break
  end
end
match total with
  | 1 -> println("one")
  | _ ->
    println("other")
end
|}
  in
  let code = compile_perl source in
  assert_contains "kw-for" code "for my $x (@xs) {";
  assert_contains "kw-if" code "if (($total > 3)) {";
  assert_contains "kw-elif" code "if (($total == 0)) {";
  assert_contains "kw-while" code "while (($total > 0)) {";
  assert_contains "kw-match" code "my $__match_1 = $total;";
  assert_contains "kw-case" code "if (shelm_match_eq($__match_1, 1)) {"

(* 3B: OCaml codegen tests — validates 1A fix *)

let test_ocaml_builtins_correct_arity () =
  let source =
    {|
let arr = [3, 1, 2]
let n = length(arr)
push(arr, 4)
let x = pop(arr)
let s = sort(arr)
let r = reverse(arr)
let u = unique(arr)
let h = {"a": 1}
let ks = keys(h)
let vs = values(h)
let joined = join(", ", arr)
let parts = split(",", "a,b,c")
let up = uppercase("hello")
let lo = lowercase("HELLO")
let t = trim("  hi  ")
let rep = replace("aXb", "X", "Y")
let sq = sqrt(4)
let sn = sin(0)
let cs = cos(0)
let ab = abs(-1)
let lg = log(1)
let fl = floor(3.7)
let cl = ceil(3.2)
let io = int_of("42")
let fo = float_of("3.14")
let so = string_of(42)
let sub = substr("hello", 1, 3)
|}
  in
  let code = compile_ocaml source in
  assert_contains "ocaml-length" code "val_length";
  assert_contains "ocaml-push" code "val_push";
  assert_contains "ocaml-pop" code "val_pop";
  assert_contains "ocaml-sort" code "val_sort";
  assert_contains "ocaml-reverse" code "val_reverse";
  assert_contains "ocaml-unique" code "val_unique";
  assert_contains "ocaml-keys" code "val_keys";
  assert_contains "ocaml-values" code "val_values";
  assert_contains "ocaml-join" code "val_join";
  assert_contains "ocaml-split" code "val_split";
  assert_contains "ocaml-uppercase" code "val_uppercase";
  assert_contains "ocaml-lowercase" code "val_lowercase";
  assert_contains "ocaml-trim" code "val_trim";
  assert_contains "ocaml-replace" code "val_replace";
  assert_contains "ocaml-sqrt" code "val_sqrt";
  assert_contains "ocaml-sin" code "val_sin";
  assert_contains "ocaml-cos" code "val_cos";
  assert_contains "ocaml-abs" code "val_abs";
  assert_contains "ocaml-log" code "val_log";
  assert_contains "ocaml-floor" code "val_floor";
  assert_contains "ocaml-ceil" code "val_ceil";
  assert_contains "ocaml-int_of" code "val_int_of";
  assert_contains "ocaml-float_of" code "val_float_of";
  assert_contains "ocaml-string_of" code "val_string_of";
  assert_contains "ocaml-substr" code "val_substr"

let test_ocaml_builtins_wrong_arity_no_crash () =
  (* Before the fix, these crashed with Failure "hd" or Invalid_argument "List.nth" *)
  let builtins = [
    "length"; "pop"; "shift"; "sort"; "reverse"; "keys"; "values";
    "unique"; "sqrt"; "sin"; "cos"; "abs"; "log"; "floor"; "ceil";
    "int_of"; "float_of"; "string_of"; "close"; "readline"; "read_file";
    "uppercase"; "lowercase"; "trim"
  ] in
  List.iter (fun name ->
    let source = Printf.sprintf "%s()\n" name in
    let code = compile_ocaml source in
    assert_contains ("ocaml-zero-arity-" ^ name) code "wrong arity"
  ) builtins

let test_ocaml_two_arg_wrong_arity_no_crash () =
  let builtins = ["map"; "filter"; "each"; "join"; "split"; "writeln";
                   "regex_match"; "regex_find_all"] in
  List.iter (fun name ->
    let source = Printf.sprintf "let x = 1\n%s(x)\n" name in
    let code = compile_ocaml source in
    assert_contains ("ocaml-wrong-arity-2-" ^ name) code "wrong arity"
  ) builtins

let test_ocaml_three_arg_wrong_arity_no_crash () =
  let builtins = ["replace"; "regex_replace"] in
  List.iter (fun name ->
    let source = Printf.sprintf "let x = 1\n%s(x, x)\n" name in
    let code = compile_ocaml source in
    assert_contains ("ocaml-wrong-arity-3-" ^ name) code "wrong arity"
  ) builtins

(* 3B: Go codegen tests — validates error comments *)

let test_go_builtins_correct_arity () =
  let source = {|
let arr = [3, 1, 2]
let n = length(arr)
let sq = sqrt(4)
let up = uppercase("hello")
let joined = join(", ", arr)
let rep = replace("aXb", "X", "Y")
|} in
  let code = compile_go source in
  assert_contains "go-length" code "valLength";
  assert_contains "go-sqrt" code "valSqrt";
  assert_contains "go-uppercase" code "valUppercase";
  assert_contains "go-join" code "valJoin";
  assert_contains "go-replace" code "valReplace"

let test_go_wrong_arity_has_comment () =
  let source = "length()\n" in
  let code = compile_go source in
  assert_contains "go-wrong-arity-comment" code "wrong arity for length"

(* 3C: Untested language features *)

let test_regex_match_compile () =
  let source = {|
let s = "hello"
if s =~ ~r/ell/ then
  println("matched")
end
if s !~ ~r/xyz/ then
  println("not matched")
end
|} in
  let code = compile_perl source in
  assert_contains "regex-match" code "=~ /ell/";
  (* !~ desugars to Not(RegexMatch(...)) *)
  assert_contains "regex-not-match" code "=~ /xyz/"

let test_float_literal_compile () =
  let source = "let x = 3.14\nprintln(string_of(x))\n" in
  let perl = compile_perl source in
  assert_contains "perl-float" perl "3.14";
  let ocaml = compile_ocaml source in
  assert_contains "ocaml-float" ocaml "VFloat 3.14";
  let go = compile_go source in
  assert_contains "go-float" go "3.14"

let test_nil_literal_compile () =
  let source = "let x = nil\n" in
  let perl = compile_perl source in
  assert_contains "perl-nil" perl "undef";
  let ocaml = compile_ocaml source in
  assert_contains "ocaml-nil" ocaml "VNil";
  let go = compile_go source in
  assert_contains "go-nil" go "nil"

let test_index_assign_compile () =
  let source = {|
let arr = [1, 2, 3]
arr[0] = 5
|} in
  let perl = compile_perl source in
  assert_contains "perl-index-assign" perl "$arr[0] = 5;";
  let ocaml = compile_ocaml source in
  assert_contains "ocaml-index-assign" ocaml "val_index_assign";
  let go = compile_go source in
  assert_contains "go-index-assign" go "valIndexAssign"

let test_string_concat_compile () =
  let source = {|let s = "a" ++ "b"|} in
  let perl = compile_perl source in
  assert_contains "perl-concat" perl ". ";
  let ocaml = compile_ocaml source in
  assert_contains "ocaml-concat" ocaml "val_concat";
  let go = compile_go source in
  assert_contains "go-concat" go "valConcat"

let test_boolean_ops_compile () =
  (* and/or work inside if conditions where the reader passes through the expr *)
  let source = {|
let a = 1
let b = 0
if a == 1 and b == 0 then
  println("and-ok")
end
if a == 0 or b == 0 then
  println("or-ok")
end
|} in
  let perl = compile_perl source in
  assert_contains "perl-and" perl "&&";
  assert_contains "perl-or" perl "||";
  let ocaml = compile_ocaml source in
  assert_contains "ocaml-and" ocaml "val_and";
  assert_contains "ocaml-or" ocaml "val_or";
  let go = compile_go source in
  assert_contains "go-and" go "valAnd";
  assert_contains "go-or" go "valOr"

let test_math_builtins_multi_target () =
  let source = {|
let x = sqrt(4)
let y = abs(-1)
let z = floor(3.7)
|} in
  let perl = compile_perl source in
  assert_contains "perl-sqrt" perl "sqrt(";
  assert_contains "perl-abs" perl "abs(";
  assert_contains "perl-floor" perl "int(";
  let go = compile_go source in
  assert_contains "go-sqrt" go "valSqrt(";
  assert_contains "go-abs" go "valAbs(";
  assert_contains "go-floor" go "valFloor("

let test_type_conversion_compile () =
  let source = {|
let a = int_of("42")
let b = float_of("3.14")
let c = string_of(42)
|} in
  let perl = compile_perl source in
  assert_contains "perl-int_of" perl "int(";
  assert_contains "perl-string_of" perl ". ";
  let ocaml = compile_ocaml source in
  assert_contains "ocaml-int_of" ocaml "val_int_of";
  assert_contains "ocaml-float_of" ocaml "val_float_of";
  assert_contains "ocaml-string_of" ocaml "val_string_of";
  let go = compile_go source in
  assert_contains "go-int_of" go "valIntOf";
  assert_contains "go-float_of" go "valFloatOf";
  assert_contains "go-string_of" go "valStringOf"

let test_bytecode_basic () =
  let source = {|
let x = 42
println(string_of(x))
|} in
  let code = compile_bytecode source in
  assert_contains "bc-push-int" code "PUSH_INT 42";
  assert_contains "bc-store" code "STORE"

let run name f =
  try
    f ();
    Printf.printf "ok - %s\n%!" name
  with
  | Failure msg ->
    Printf.eprintf "FAILED - %s: %s\n%!" name msg;
    exit 1
  | exn ->
    Printf.eprintf "FAILED - %s: %s\n%!" name (Printexc.to_string exn);
    exit 1

let () =
  run "defun defs compile" test_defun_defs_compile;
  run "index syntax stays index" test_index_not_rewritten_as_call;
  run "keyword literals compile" test_keyword_literals_compile;
  run "def bindings compile" test_def_binding_compile;
  run "match/case compile" test_match_case_compile;
  run "type/enum compile" test_type_enum_compile;
  run "break/continue compile" test_break_continue_compile;
  run "fun expression compile" test_fun_expr_compile;
  run "typed signatures compile" test_typed_signatures_compile;
  run "compact colon rejected" test_compact_colon_upper_rejected;
  run "upper postfix keyword rejected" test_upper_postfix_keyword_rejected;
  run "legacy fn rejected" test_legacy_fn_rejected;
  run "legacy for rejected" test_legacy_for_rejected;
  run "brace blocks rejected" test_brace_blocks_rejected;
  run "colon blocks rejected" test_colon_blocks_rejected;
  run "if-do rejected" test_if_do_rejected;
  run "keyword/end blocks compile" test_keyword_end_blocks_compile;
  (* 3B: OCaml codegen tests *)
  run "ocaml builtins correct arity" test_ocaml_builtins_correct_arity;
  run "ocaml builtins wrong arity no crash" test_ocaml_builtins_wrong_arity_no_crash;
  run "ocaml two-arg builtins wrong arity" test_ocaml_two_arg_wrong_arity_no_crash;
  run "ocaml three-arg builtins wrong arity" test_ocaml_three_arg_wrong_arity_no_crash;
  (* Go codegen tests *)
  run "go builtins correct arity" test_go_builtins_correct_arity;
  run "go wrong arity has comment" test_go_wrong_arity_has_comment;
  (* 3C: Untested language features *)
  run "regex match compile" test_regex_match_compile;
  run "float literal compile" test_float_literal_compile;
  run "nil literal compile" test_nil_literal_compile;
  run "index assign compile" test_index_assign_compile;
  run "string concat compile" test_string_concat_compile;
  run "boolean ops compile" test_boolean_ops_compile;
  run "math builtins multi-target" test_math_builtins_multi_target;
  run "type conversion compile" test_type_conversion_compile;
  run "bytecode basic" test_bytecode_basic;
  Printf.printf "all syntax tests passed\n%!"

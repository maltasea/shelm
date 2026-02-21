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

let compile_perl source =
  match Shelm_lib.Shelm.compile_source_target "perl" source with
  | Ok code -> code
  | Error err -> failwith (Shelm_lib.Errors.format_error err)

let compile_perl_result source =
  Shelm_lib.Shelm.compile_source_target "perl" source

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

let test_optional_paren_fn_defs () =
  let source =
    {|
fn add x, y do
  return x + y
end
rec fn fact n do
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
  assert_contains "fn-add" code "sub add { my $x = shift; my $y = shift;";
  assert_contains "fn-fact" code "sub fact { my $n = shift;";
  assert_contains "fn-call" code "add(2, 3)";
  assert_contains "rec-call" code "fact(6)"

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

let test_lambda_rejected () =
  let source =
    {|
let f = fn(x) { x * 2 }
|}
  in
  match compile_perl_result source with
  | Ok _ -> failwith "lambda should be rejected in speed-first profile"
  | Error err ->
    let msg = Shelm_lib.Errors.format_error err in
    if not (contains_substring msg "Parse error") then
      failwith (Printf.sprintf "expected parse error for lambda, got: %s" msg)

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
  run "optional-paren fn defs compile" test_optional_paren_fn_defs;
  run "index syntax stays index" test_index_not_rewritten_as_call;
  run "match/case compile" test_match_case_compile;
  run "type/enum compile" test_type_enum_compile;
  run "break/continue compile" test_break_continue_compile;
  run "lambda rejected" test_lambda_rejected;
  run "brace blocks rejected" test_brace_blocks_rejected;
  run "colon blocks rejected" test_colon_blocks_rejected;
  run "if-do rejected" test_if_do_rejected;
  run "keyword/end blocks compile" test_keyword_end_blocks_compile;
  Printf.printf "all syntax tests passed\n%!"

open Tuple_ast

type function_def = {
  id : string;
  params : string list;
  body : string list;
  is_rec : bool;
  meta : meta;
}

type state = {
  mutable label_counter : int;
  mutable temp_counter : int;
  mutable anon_counter : int;
  mutable functions : function_def list;
  mutable loop_stack : (string * string) list;  (* break_label, continue_label *)
}

let invalid where message = Error (Errors.Invalid_ast { where; message })
let ( let* ) r f = match r with Ok v -> f v | Error _ as e -> e

let create_state () = {
  label_counter = 0;
  temp_counter = 0;
  anon_counter = 0;
  functions = [];
  loop_stack = [];
}

let quote s = Printf.sprintf "%S" s

let is_plain_ident_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' | '?' -> true
  | _ -> false

let needs_quote_ident s =
  s = "" || not (String.for_all is_plain_ident_char s)

let emit_ident s =
  if needs_quote_ident s then quote s else s

let emit_loc meta =
  Printf.sprintf "LOC %d %d %s" meta.line_nr meta.char_pos (quote meta.module_name)

let fresh_label st prefix =
  st.label_counter <- st.label_counter + 1;
  Printf.sprintf "%s_%d" prefix st.label_counter

let fresh_temp st prefix =
  st.temp_counter <- st.temp_counter + 1;
  Printf.sprintf "__%s_%d" prefix st.temp_counter

let fresh_anon_fn st () =
  st.anon_counter <- st.anon_counter + 1;
  Printf.sprintf "__lambda_%d" st.anon_counter

let with_loop_context st ~break_label ~continue_label f =
  st.loop_stack <- (break_label, continue_label) :: st.loop_stack;
  let result = f () in
  st.loop_stack <- (match st.loop_stack with _ :: rest -> rest | [] -> []);
  result

let payload_string where = function
  | Node (_, _, [Node (v, _, [])]) -> Ok v
  | _ -> invalid where "Expected payload node"

let sym_name where = function
  | Node ("sym", _, _) as n -> payload_string where n
  | Node (tag, _, []) -> Ok tag
  | Node (tag, _, _) ->
    invalid where (Printf.sprintf "Expected symbol node, got '%s'" tag)

let map_results f xs =
  let rec aux acc = function
    | [] -> Ok (List.rev acc)
    | x :: rest ->
      let* y = f x in
      aux (y :: acc) rest
  in
  aux [] xs

let rec compile_expr st (n : node) : (string list, Errors.compile_error) result =
  match n with
  | Node ("int", _, _) ->
    let* v = payload_string "expr:int" n in
    Ok [Printf.sprintf "PUSH_INT %s" v]
  | Node ("float", _, _) ->
    let* v = payload_string "expr:float" n in
    Ok [Printf.sprintf "PUSH_FLOAT %s" v]
  | Node ("string", _, _) ->
    let* v = payload_string "expr:string" n in
    Ok [Printf.sprintf "PUSH_STRING %s" (quote v)]
  | Node ("bool", _, _) ->
    let* v = payload_string "expr:bool" n in
    if v = "true" || v = "false" then
      Ok [Printf.sprintf "PUSH_BOOL %s" v]
    else
      invalid "expr:bool" (Printf.sprintf "Invalid bool payload '%s'" v)
  | Node ("nil", _, _) ->
    Ok ["PUSH_NIL"]
  | Node ("sym", _, _) ->
    let* name = payload_string "expr:sym" n in
    Ok [Printf.sprintf "LOAD %s" (emit_ident name)]
  | Node ("array", _, elems) ->
    let* parts = compile_expr_list st elems in
    Ok (parts @ [Printf.sprintf "MAKE_ARRAY %d" (List.length elems)])
  | Node ("struct", _, pairs) ->
    let compile_pair = function
      | Node ("pair", _, [k; v]) ->
        let* k_code = compile_expr st k in
        let* v_code = compile_expr st v in
        Ok (k_code @ v_code)
      | Node (tag, _, _) ->
        invalid "expr:struct" (Printf.sprintf "Expected pair node, got '%s'" tag)
    in
    let* pair_parts = map_results compile_pair pairs in
    Ok (List.concat pair_parts @ [Printf.sprintf "MAKE_HASH %d" (List.length pairs)])
  | Node ("index", _, [target; idx]) ->
    let* target_code = compile_expr st target in
    let* idx_code = compile_expr st idx in
    Ok (target_code @ idx_code @ ["INDEX_GET"])
  | Node ("regex", _, [pat; flags]) ->
    let* p = payload_string "expr:regex-pattern" pat in
    let* f = payload_string "expr:regex-flags" flags in
    Ok [Printf.sprintf "PUSH_REGEX %s %s" (quote p) (quote f)]
  | Node ("regex_match", _, [e; pat; flags]) ->
    let* e_code = compile_expr st e in
    let* p = payload_string "expr:regex-match-pattern" pat in
    let* f = payload_string "expr:regex-match-flags" flags in
    Ok (e_code @ [Printf.sprintf "REGEX_MATCH %s %s" (quote p) (quote f)])
  | Node ("regex_replace", _, [e; pat; repl; flags]) ->
    let* e_code = compile_expr st e in
    let* p = payload_string "expr:regex-replace-pattern" pat in
    let* r = payload_string "expr:regex-replace-repl" repl in
    let* f = payload_string "expr:regex-replace-flags" flags in
    Ok (e_code @ [Printf.sprintf "REGEX_REPLACE %s %s %s" (quote p) (quote r) (quote f)])
  | Node ("host_get", _, [path_node]) ->
    let* path = payload_string "expr:host-get-path" path_node in
    Ok [Printf.sprintf "HOST_GET %s" (quote path)]
  | Node ("host_call", _, path_node :: args) ->
    let* path = payload_string "expr:host-call-path" path_node in
    let* arg_code = compile_expr_list st args in
    Ok (arg_code @ [Printf.sprintf "HOST_CALL %s %d" (quote path) (List.length args)])
  | Node ("host_call", _, []) ->
    invalid "expr:host-call" "Expected host path argument"
  | Node ("fn", meta, [Node ("params", _, params); Node ("do", _, body_nodes)]) ->
    let* param_names = map_results (sym_name "expr:lambda-param") params in
    let fn_id = fresh_anon_fn st () in
    let* body_code = compile_block st body_nodes in
    let body_code = ensure_terminal_return body_code in
    st.functions <- st.functions @ [{
      id = fn_id;
      params = param_names;
      body = body_code;
      is_rec = false;
      meta;
    }];
    Ok [Printf.sprintf "MAKE_FUNC %s %d" (emit_ident fn_id) (List.length param_names)]
  | Node ("call", _, fn :: args) ->
    let* fn_code = compile_expr st fn in
    let* arg_code = compile_expr_list st args in
    Ok (fn_code @ arg_code @ [Printf.sprintf "CALL %d" (List.length args)])
  | Node ("+", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["ADD"])
  | Node ("-", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["SUB"])
  | Node ("*", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["MUL"])
  | Node ("/", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["DIV"])
  | Node ("%", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["MOD"])
  | Node ("==", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["EQ"])
  | Node ("!=", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["NEQ"])
  | Node ("<", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["LT"])
  | Node (">", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["GT"])
  | Node ("<=", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["LE"])
  | Node (">=", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["GE"])
  | Node ("and", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["AND"])
  | Node ("or", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["OR"])
  | Node ("concat", _, [a; b]) ->
    let* a_code = compile_expr st a in
    let* b_code = compile_expr st b in
    Ok (a_code @ b_code @ ["CONCAT"])
  | Node ("neg", _, [e]) ->
    let* code = compile_expr st e in
    Ok (code @ ["NEG"])
  | Node ("not", _, [e]) ->
    let* code = compile_expr st e in
    Ok (code @ ["NOT"])
  | Node (tag, _, args) ->
    let* arg_code = compile_expr_list st args in
    Ok (arg_code @ [Printf.sprintf "CALL_NAME %s %d" (emit_ident tag) (List.length args)])

and compile_expr_list st nodes =
  let rec aux acc = function
    | [] -> Ok (List.concat (List.rev acc))
    | x :: xs ->
      let* code = compile_expr st x in
      aux (code :: acc) xs
  in
  aux [] nodes

and compile_stmt st (n : node) : (string list, Errors.compile_error) result =
  match n with
  | Node ("type", meta, [_name; _repr]) ->
    Ok [emit_loc meta]
  | Node ("enum", meta, [Node ("sym", _, [Node (_enum_name, _, [])]); Node ("variants", _, variant_nodes)]) ->
    let rec compile_variants acc = function
      | [] -> Ok (List.concat (List.rev acc))
      | Node ("sym", _, [Node (variant, _, [])]) :: rest ->
        let idx = List.length acc in
        let code = [
          Printf.sprintf "PUSH_INT %d" idx;
          Printf.sprintf "STORE_LET %s" (emit_ident variant);
        ] in
        compile_variants (code :: acc) rest
      | Node (tag, _, _) :: _ ->
        invalid "stmt:enum-variant" (Printf.sprintf "Expected symbol node, got '%s'" tag)
    in
    let* variant_code = compile_variants [] variant_nodes in
    Ok (emit_loc meta :: variant_code)
  | Node ("enum", _, [name; _]) ->
    let tag = tag_of name in
    invalid "stmt:enum-name" (Printf.sprintf "Expected symbol node for enum name, got '%s'" tag)
  | Node ("let", meta, [name; e]) ->
    let* n' = sym_name "stmt:let-name" name in
    let* e_code = compile_expr st e in
    Ok (emit_loc meta :: e_code @ [Printf.sprintf "STORE_LET %s" (emit_ident n')])
  | Node ("set", meta, [name; e]) ->
    let* n' = sym_name "stmt:set-name" name in
    let* e_code = compile_expr st e in
    Ok (emit_loc meta :: e_code @ [Printf.sprintf "STORE %s" (emit_ident n')])
  | Node ("set-index", meta, [target; idx; value]) ->
    let* t_code = compile_expr st target in
    let* i_code = compile_expr st idx in
    let* v_code = compile_expr st value in
    Ok (emit_loc meta :: t_code @ i_code @ v_code @ ["INDEX_SET"])
  | Node ("match", meta, [subject; Node ("cases", _, case_nodes)]) ->
    let subject_slot = fresh_temp st "match" in
    let end_label = fresh_label st "match_end" in
    let* subject_code = compile_expr st subject in
    let rec compile_cases = function
      | [] -> Ok []
      | Node ("case", _, [Node ("wildcard", _, []); Node ("do", _, body_nodes)]) :: _ ->
        let* body_code = compile_block st body_nodes in
        Ok (body_code @ [Printf.sprintf "JUMP %s" end_label])
      | Node ("case", _, [Node ("pattern", _, [pattern_expr]); Node ("do", _, body_nodes)]) :: rest ->
        let next_label = fresh_label st "match_next" in
        let* pattern_code = compile_expr st pattern_expr in
        let* body_code = compile_block st body_nodes in
        let* rest_code = compile_cases rest in
        Ok (
          [Printf.sprintf "LOAD %s" (emit_ident subject_slot)]
          @ pattern_code
          @ ["EQ"; Printf.sprintf "JUMP_IF_FALSE %s" next_label]
          @ body_code
          @ [Printf.sprintf "JUMP %s" end_label; Printf.sprintf "LABEL %s" next_label]
          @ rest_code
        )
      | Node ("case", _, [pattern_node; Node ("do", _, _)]) :: _ ->
        let tag = tag_of pattern_node in
        invalid "stmt:match-pattern" (Printf.sprintf "Expected wildcard/pattern node, got '%s'" tag)
      | Node (tag, _, _) :: _ ->
        invalid "stmt:match-case" (Printf.sprintf "Expected case node, got '%s'" tag)
    in
    let* cases_code = compile_cases case_nodes in
    Ok (
      emit_loc meta
      :: subject_code
      @ [Printf.sprintf "STORE_LET %s" (emit_ident subject_slot)]
      @ cases_code
      @ [Printf.sprintf "LABEL %s" end_label]
    )
  | Node ("if", meta, [cond; Node ("do", _, then_nodes); Node ("do", _, else_nodes)]) ->
    let else_label = fresh_label st "else" in
    let end_label = fresh_label st "ifend" in
    let* cond_code = compile_expr st cond in
    let* then_code = compile_block st then_nodes in
    let* else_code = compile_block st else_nodes in
    Ok (
      emit_loc meta
      :: cond_code
      @ [Printf.sprintf "JUMP_IF_FALSE %s" else_label]
      @ then_code
      @ [Printf.sprintf "JUMP %s" end_label; Printf.sprintf "LABEL %s" else_label]
      @ else_code
      @ [Printf.sprintf "LABEL %s" end_label]
    )
  | Node ("while", meta, [cond; Node ("do", _, body_nodes)]) ->
    let loop_label = fresh_label st "while" in
    let end_label = fresh_label st "while_end" in
    let* cond_code = compile_expr st cond in
    let* body_code =
      with_loop_context st ~break_label:end_label ~continue_label:loop_label (fun () ->
        compile_block st body_nodes
      )
    in
    Ok (
      emit_loc meta
      :: Printf.sprintf "LABEL %s" loop_label
      :: cond_code
      @ [Printf.sprintf "JUMP_IF_FALSE %s" end_label]
      @ body_code
      @ [Printf.sprintf "JUMP %s" loop_label; Printf.sprintf "LABEL %s" end_label]
    )
  | Node ("for", meta, [name; iter; Node ("do", _, body_nodes)]) ->
    let* var_name = sym_name "stmt:for-name" name in
    let iter_slot = fresh_temp st "iter" in
    let loop_label = fresh_label st "for" in
    let end_label = fresh_label st "for_end" in
    let* iter_code = compile_expr st iter in
    let* body_code =
      with_loop_context st ~break_label:end_label ~continue_label:loop_label (fun () ->
        compile_block st body_nodes
      )
    in
    Ok (
      emit_loc meta
      :: iter_code
      @ [Printf.sprintf "ITER_INIT %s" (emit_ident iter_slot)]
      @ [Printf.sprintf "LABEL %s" loop_label]
      @ [Printf.sprintf "ITER_NEXT %s %s %s" (emit_ident iter_slot) (emit_ident var_name) end_label]
      @ body_code
      @ [Printf.sprintf "JUMP %s" loop_label; Printf.sprintf "LABEL %s" end_label]
    )
  | Node ("defn", meta, [name; Node ("params", _, params); Node ("do", _, body_nodes)]) ->
    let* fn_name = sym_name "stmt:defn-name" name in
    let* param_names = map_results (sym_name "stmt:defn-param") params in
    let fn_id = fn_name in
    let* body_code = compile_block st body_nodes in
    let body_code = ensure_terminal_return body_code in
    st.functions <- st.functions @ [{
      id = fn_id;
      params = param_names;
      body = body_code;
      is_rec = false;
      meta;
    }];
    Ok (emit_loc meta :: [Printf.sprintf "MAKE_FUNC %s %d" (emit_ident fn_id) (List.length param_names);
                           Printf.sprintf "STORE %s" (emit_ident fn_name)])
  | Node ("return", meta, [e]) ->
    let* e_code = compile_expr st e in
    Ok (emit_loc meta :: e_code @ ["RETURN"])
  | Node ("break", meta, []) ->
    begin
      match st.loop_stack with
      | (break_label, _) :: _ ->
        Ok [emit_loc meta; Printf.sprintf "JUMP %s" break_label]
      | [] ->
        invalid "stmt:break" "break used outside of loop"
    end
  | Node ("continue", meta, []) ->
    begin
      match st.loop_stack with
      | (_, continue_label) :: _ ->
        Ok [emit_loc meta; Printf.sprintf "JUMP %s" continue_label]
      | [] ->
        invalid "stmt:continue" "continue used outside of loop"
    end
  | _ ->
    let meta = meta_of n in
    let* e_code = compile_expr st n in
    Ok (emit_loc meta :: e_code @ ["POP"])

and compile_block st nodes =
  let rec aux acc = function
    | [] -> Ok (List.concat (List.rev acc))
    | n :: rest ->
      let* code = compile_stmt st n in
      aux (code :: acc) rest
  in
  aux [] nodes

and ensure_terminal_return code =
  match List.rev code with
  | "RETURN" :: _ -> code
  | _ -> code @ ["PUSH_NIL"; "RETURN"]

let render_function b f =
  Buffer.add_string b
    (Printf.sprintf ".func %s %d%s\n"
       (emit_ident f.id)
       (List.length f.params)
       (if f.is_rec then " rec" else ""));
  Buffer.add_string b (Printf.sprintf "  %s\n" (emit_loc f.meta));
  List.iter (fun p ->
    Buffer.add_string b (Printf.sprintf "  PARAM %s\n" (emit_ident p))
  ) f.params;
  List.iter (fun ins ->
    Buffer.add_string b (Printf.sprintf "  %s\n" ins)
  ) f.body;
  Buffer.add_string b ".end\n\n"

let generate (program : program) : (string, Errors.compile_error) result =
  let st = create_state () in
  match program with
  | Node ("program", meta, stmts) ->
    let* main_code = compile_block st stmts in
    let main_code = ensure_terminal_return main_code in
    let out = Buffer.create 4096 in
    Buffer.add_string out ".bytecode 1\n\n";
    render_function out {
      id = "main";
      params = [];
      body = main_code;
      is_rec = false;
      meta;
    };
    List.iter (render_function out) st.functions;
    Ok (Buffer.contents out)
  | Node (tag, _, _) ->
    invalid "program" (Printf.sprintf "Expected 'program', got '%s'" tag)

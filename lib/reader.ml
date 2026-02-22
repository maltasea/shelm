let is_space = function
  | ' ' | '\t' -> true
  | _ -> false

let trim = String.trim

exception Reader_error of {
  line : int;
  message : string;
}

let is_symbol_start = function
  | 'a' .. 'z' | 'A' .. 'Z' | '_' -> true
  | _ -> false

let is_symbol_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' | '?' -> true
  | _ -> false

let is_operator_prefix = function
  | '+' | '-' | '*' | '/' | '%' | '<' | '>' | '=' | '!' -> true
  | _ -> false

let is_lc_keyword_char = function
  | 'a' .. 'z' | '0' .. '9' | '_' | '-' | '?' -> true
  | _ -> false

let is_ident_text s =
  let n = String.length s in
  if n = 0 || not (is_symbol_start s.[0]) then false
  else
    let rec loop i =
      if i >= n then true
      else if is_symbol_char s.[i] then loop (i + 1)
      else false
    in
    loop 1

let is_lc_keyword_text s =
  let n = String.length s in
  if n = 0 || s.[0] < 'a' || s.[0] > 'z' then false
  else
    let rec loop i =
      if i >= n then true
      else if is_lc_keyword_char s.[i] then loop (i + 1)
      else false
    in
    loop 1

let is_ucfirst_type_text s =
  let n = String.length s in
  if n = 0 || s.[0] < 'A' || s.[0] > 'Z' then false
  else
    let rec loop i =
      if i >= n then true
      else if is_symbol_char s.[i] then loop (i + 1)
      else false
    in
    loop 1

let is_boundary s i =
  i < 0 || i >= String.length s || not (is_symbol_char s.[i])

let ends_with_keyword s kw =
  let t = trim s in
  let n = String.length t and k = String.length kw in
  n >= k
  && String.sub t (n - k) k = kw
  && is_boundary t (n - k - 1)

let strip_trailing_keyword s kw =
  if ends_with_keyword s kw then
    let t = trim s in
    let n = String.length t and k = String.length kw in
    Some (trim (String.sub t 0 (n - k)))
  else
    None

let strip_trailing_block_opener s =
  strip_trailing_keyword s "do"

let ends_with_char s ch =
  let t = trim s in
  let n = String.length t in
  n > 0 && t.[n - 1] = ch

let starts_with_keyword s kw =
  let n = String.length kw in
  String.length s >= n
  && String.sub s 0 n = kw
  && is_boundary s n

let find_top_level s ch =
  let len = String.length s in
  let rec loop i parens braces brackets in_string escaped =
    if i >= len then None
    else
      let c = s.[i] in
      if in_string then
        if escaped then loop (i + 1) parens braces brackets true false
        else if c = '\\' then loop (i + 1) parens braces brackets true true
        else if c = '"' then loop (i + 1) parens braces brackets false false
        else loop (i + 1) parens braces brackets true false
      else
        match c with
        | '"' -> loop (i + 1) parens braces brackets true false
        | '(' -> loop (i + 1) (parens + 1) braces brackets false false
        | ')' -> loop (i + 1) (max 0 (parens - 1)) braces brackets false false
        | '{' -> loop (i + 1) parens (braces + 1) brackets false false
        | '}' -> loop (i + 1) parens (max 0 (braces - 1)) brackets false false
        | '[' -> loop (i + 1) parens braces (brackets + 1) false false
        | ']' -> loop (i + 1) parens braces (max 0 (brackets - 1)) false false
        | _ when c = ch && parens = 0 && braces = 0 && brackets = 0 -> Some i
        | _ -> loop (i + 1) parens braces brackets false false
  in
  loop 0 0 0 0 false false

let split_top_level_commas s =
  let rec split acc rest =
    match find_top_level rest ',' with
    | None ->
      let part = trim rest in
      List.rev (if part = "" then acc else part :: acc)
    | Some i ->
      let left = trim (String.sub rest 0 i) in
      let right = String.sub rest (i + 1) (String.length rest - i - 1) in
      split (if left = "" then acc else left :: acc) right
  in
  split [] s

let strip_outer_parens s =
  let s = trim s in
  let len = String.length s in
  if len >= 2 && s.[0] = '(' && s.[len - 1] = ')' then
    match find_top_level (String.sub s 1 (len - 2)) ')' with
    | None -> Some (String.sub s 1 (len - 2))
    | Some _ -> None
  else
    None

(* ~r/regex/ is now handled directly by the lexer; no reader rewriting needed *)
let normalize_regex_literals s = s

let is_host_ident_start = function
  | 'a' .. 'z' | 'A' .. 'Z' | '_' -> true
  | _ -> false

let is_host_ident_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' | '?' -> true
  | _ -> false

let read_host_ident_end s i =
  let len = String.length s in
  if i >= len || not (is_host_ident_start s.[i]) then None
  else
    let rec loop j =
      if j < len && is_host_ident_char s.[j] then loop (j + 1) else j
    in
    Some (loop (i + 1))

let read_host_path s i =
  let len = String.length s in
  match read_host_ident_end s i with
  | None -> None
  | Some first_end ->
    let j = ref first_end in
    let valid = ref true in
    while !valid && !j < len && s.[!j] = '/' do
      match read_host_ident_end s (!j + 1) with
      | None -> valid := false
      | Some next_end -> j := next_end
    done;
    if not !valid then None
    else Some (String.sub s i (!j - i), !j)

let find_matching_paren s open_i =
  let len = String.length s in
  let rec loop i parens braces brackets in_string escaped =
    if i >= len then None
    else
      let c = s.[i] in
      if in_string then
        if escaped then loop (i + 1) parens braces brackets true false
        else if c = '\\' then loop (i + 1) parens braces brackets true true
        else if c = '"' then loop (i + 1) parens braces brackets false false
        else loop (i + 1) parens braces brackets true false
      else
        match c with
        | '"' -> loop (i + 1) parens braces brackets true false
        | '(' ->
          if i = open_i then loop (i + 1) 1 braces brackets false false
          else loop (i + 1) (parens + 1) braces brackets false false
        | ')' ->
          if parens = 1 then Some i
          else loop (i + 1) (max 0 (parens - 1)) braces brackets false false
        | '{' -> loop (i + 1) parens (braces + 1) brackets false false
        | '}' -> loop (i + 1) parens (max 0 (braces - 1)) brackets false false
        | '[' -> loop (i + 1) parens braces (brackets + 1) false false
        | ']' -> loop (i + 1) parens braces (max 0 (brackets - 1)) false false
        | _ -> loop (i + 1) parens braces brackets false false
  in
  if open_i < 0 || open_i >= len || s.[open_i] <> '(' then None
  else loop open_i 0 0 0 false false

let find_top_level_fat_arrow s =
  let len = String.length s in
  let rec loop i parens braces brackets in_string escaped =
    if i + 1 >= len then None
    else
      let c = s.[i] in
      if in_string then
        if escaped then loop (i + 1) parens braces brackets true false
        else if c = '\\' then loop (i + 1) parens braces brackets true true
        else if c = '"' then loop (i + 1) parens braces brackets false false
        else loop (i + 1) parens braces brackets true false
      else
        match c with
        | '"' -> loop (i + 1) parens braces brackets true false
        | '(' -> loop (i + 1) (parens + 1) braces brackets false false
        | ')' -> loop (i + 1) (max 0 (parens - 1)) braces brackets false false
        | '{' -> loop (i + 1) parens (braces + 1) brackets false false
        | '}' -> loop (i + 1) parens (max 0 (braces - 1)) brackets false false
        | '[' -> loop (i + 1) parens braces (brackets + 1) false false
        | ']' -> loop (i + 1) parens braces (max 0 (brackets - 1)) false false
        | '=' when s.[i + 1] = '>' && parens = 0 && braces = 0 && brackets = 0 -> Some i
        | _ -> loop (i + 1) parens braces brackets false false
  in
  loop 0 0 0 0 false false

let strip_optional_return_type (s : string) : string option =
  match find_top_level_fat_arrow s with
  | None -> Some (trim s)
  | Some i ->
    let left = trim (String.sub s 0 i) in
    let right = trim (String.sub s (i + 2) (String.length s - i - 2)) in
    if left = "" then None
    else if is_ucfirst_type_text right then Some left
    else None

let normalize_typed_name (s : string) : string option =
  let t = trim s in
  match find_top_level t ':' with
  | None ->
    if is_ident_text t then Some t else None
  | Some i ->
    let left = trim (String.sub t 0 i) in
    let right = trim (String.sub t (i + 1) (String.length t - i - 1)) in
    if is_ident_text left && is_ucfirst_type_text right then Some left else None

let normalize_typed_params (s : string) : string list option =
  let t = trim s in
  if t = "" then Some []
  else
    let parts = split_top_level_commas t in
    let rec loop acc = function
      | [] -> Some (List.rev acc)
      | p :: rest ->
        begin
          match normalize_typed_name p with
          | Some name -> loop (name :: acc) rest
          | None -> None
        end
    in
    loop [] parts

let normalize_defun_signature (line : string) : string option =
  let t = trim line in
  if not (starts_with_keyword t "defun") then None
  else
    let raw = trim (String.sub t 5 (String.length t - 5)) in
    match strip_optional_return_type raw with
    | None -> None
    | Some rest ->
      if rest = "" then None
      else
        match String.index_opt rest '(' with
        | Some open_i ->
          let name = trim (String.sub rest 0 open_i) in
          begin
            match find_matching_paren rest open_i with
            | Some close_i when close_i = String.length rest - 1 && is_ident_text name ->
              let inner = String.sub rest (open_i + 1) (close_i - open_i - 1) in
              begin
                match normalize_typed_params inner with
                | Some ps -> Some (Printf.sprintf "defun %s(%s)" name (String.concat ", " ps))
                | None -> None
              end
            | _ -> None
          end
        | None ->
          begin
            match find_top_level rest ' ' with
            | None ->
              if is_ident_text rest then Some ("defun " ^ rest) else None
            | Some first_space ->
              let name = trim (String.sub rest 0 first_space) in
              let raw_params = trim (String.sub rest (first_space + 1) (String.length rest - first_space - 1)) in
              if not (is_ident_text name) then None
              else
                match normalize_typed_params raw_params with
                | Some [] -> Some ("defun " ^ name)
                | Some ps -> Some (Printf.sprintf "defun %s %s" name (String.concat ", " ps))
                | None -> None
          end

let normalize_fun_signature (line : string) : string option =
  let t = trim line in
  if not (starts_with_keyword t "fun") then None
  else
    let raw = trim (String.sub t 3 (String.length t - 3)) in
    match strip_optional_return_type raw with
    | None -> None
    | Some rest ->
      if rest = "" then Some "fun"
      else if rest.[0] = '(' then
        begin
          match find_matching_paren rest 0 with
          | Some close_i when close_i = String.length rest - 1 ->
            let inner = String.sub rest 1 (close_i - 1) in
            begin
              match normalize_typed_params inner with
              | Some ps -> Some (Printf.sprintf "fun(%s)" (String.concat ", " ps))
              | None -> None
            end
          | _ -> None
        end
      else
        match normalize_typed_params rest with
        | Some [] -> Some "fun"
        | Some ps -> Some (Printf.sprintf "fun %s" (String.concat ", " ps))
        | None -> None

let normalize_binding_left (left : string) : string =
  let t = trim left in
  let normalize_kw kw =
    if starts_with_keyword t kw then
      let rest = trim (String.sub t (String.length kw) (String.length t - String.length kw)) in
      match find_top_level rest ':' with
      | None -> t
      | Some i ->
        let name = trim (String.sub rest 0 i) in
        let ty = trim (String.sub rest (i + 1) (String.length rest - i - 1)) in
        if is_ident_text name && is_ucfirst_type_text ty then
          kw ^ " " ^ name
        else
          t
    else
      t
  in
  if starts_with_keyword t "let" then normalize_kw "let"
  else if starts_with_keyword t "def" then normalize_kw "def"
  else t

let find_compact_keyword_or_type_colon (s : string) : string option =
  let len = String.length s in
  let rec loop i in_string escaped =
    if i >= len then None
    else
      let c = s.[i] in
      if in_string then
        if escaped then loop (i + 1) true false
        else if c = '\\' then loop (i + 1) true true
        else if c = '"' then loop (i + 1) false false
        else loop (i + 1) true false
      else if is_symbol_start c && is_boundary s (i - 1) then
        let rec read_ident j =
          if j < len && is_symbol_char s.[j] then read_ident (j + 1) else j
        in
        let ident_end = read_ident (i + 1) in
        if ident_end + 1 < len && s.[ident_end] = ':' && s.[ident_end + 1] >= 'A' && s.[ident_end + 1] <= 'Z' then
          let rec read_type j =
            if j < len && is_symbol_char s.[j] then read_type (j + 1) else j
          in
          let ty_end = read_type (ident_end + 2) in
          Some (String.sub s i (ty_end - i))
        else
          loop ident_end false false
      else
        loop (i + 1) false false
  in
  loop 0 false false

let find_non_lc_postfix_keyword (s : string) : string option =
  let len = String.length s in
  let rec loop i in_string escaped =
    if i >= len then None
    else
      let c = s.[i] in
      if in_string then
        if escaped then loop (i + 1) true false
        else if c = '\\' then loop (i + 1) true true
        else if c = '"' then loop (i + 1) false false
        else loop (i + 1) true false
      else if is_symbol_start c && is_boundary s (i - 1) then
        let rec read_ident j =
          if j < len && is_symbol_char s.[j] then read_ident (j + 1) else j
        in
        let ident_end = read_ident (i + 1) in
        if ident_end < len && s.[ident_end] = ':' && is_boundary s (ident_end + 1) then
          let name = String.sub s i (ident_end - i) in
          if is_lc_keyword_text name then loop (ident_end + 1) false false
          else Some (name ^ ":")
        else
          loop ident_end false false
      else
        loop (i + 1) false false
  in
  loop 0 false false

let find_ffi_tail_end s start_i =
  let len = String.length s in
  let rec loop i parens braces brackets in_string escaped =
    if i >= len then len
    else
      let c = s.[i] in
      if in_string then
        if escaped then loop (i + 1) parens braces brackets true false
        else if c = '\\' then loop (i + 1) parens braces brackets true true
        else if c = '"' then loop (i + 1) parens braces brackets false false
        else loop (i + 1) parens braces brackets true false
      else
        match c with
        | '"' -> loop (i + 1) parens braces brackets true false
        | '(' -> loop (i + 1) (parens + 1) braces brackets false false
        | ')' when parens = 0 && braces = 0 && brackets = 0 -> i
        | ')' -> loop (i + 1) (max 0 (parens - 1)) braces brackets false false
        | '{' -> loop (i + 1) parens (braces + 1) brackets false false
        | '}' when parens = 0 && braces = 0 && brackets = 0 -> i
        | '}' -> loop (i + 1) parens (max 0 (braces - 1)) brackets false false
        | '[' -> loop (i + 1) parens braces (brackets + 1) false false
        | ']' when parens = 0 && braces = 0 && brackets = 0 -> i
        | ']' -> loop (i + 1) parens braces (max 0 (brackets - 1)) false false
        | ',' when parens = 0 && braces = 0 && brackets = 0 -> i
        | _ -> loop (i + 1) parens braces brackets false false
  in
  loop start_i 0 0 0 false false

let rec rewrite_ffi_expr s =
  let len = String.length s in
  let b = Buffer.create len in
  let rec skip_spaces j =
    if j < len && is_space s.[j] then skip_spaces (j + 1) else j
  in
  let rec loop i in_string escaped =
    if i >= len then ()
    else
      let c = s.[i] in
      if in_string then begin
        Buffer.add_char b c;
        if escaped then loop (i + 1) true false
        else if c = '\\' then loop (i + 1) true true
        else if c = '"' then loop (i + 1) false false
        else loop (i + 1) true false
      end else
        match c with
        | '"' ->
          Buffer.add_char b c;
          loop (i + 1) true false
        | '$' ->
          begin match read_host_path s (i + 1) with
          | Some (path, next_i) ->
            Buffer.add_string b (Printf.sprintf "host_get(%S)" path);
            loop next_i false false
          | None ->
            Buffer.add_char b c;
            loop (i + 1) false false
          end
        | '&' ->
          begin match read_host_path s (i + 1) with
          | None ->
            Buffer.add_char b c;
            loop (i + 1) false false
          | Some (path, path_end) ->
            let after_path = skip_spaces path_end in
            if after_path < len && s.[after_path] = '(' then begin
              match find_matching_paren s after_path with
              | Some close_i ->
                let inner = String.sub s (after_path + 1) (close_i - after_path - 1) in
                let inner = trim (rewrite_ffi_expr inner) in
                if inner = "" then
                  Buffer.add_string b (Printf.sprintf "host_call(%S)" path)
                else
                  Buffer.add_string b (Printf.sprintf "host_call(%S, %s)" path inner);
                loop (close_i + 1) false false
              | None ->
                Buffer.add_char b c;
                loop (i + 1) false false
            end else begin
              let tail_end = find_ffi_tail_end s after_path in
              let raw_tail =
                if tail_end > after_path
                then String.sub s after_path (tail_end - after_path)
                else ""
              in
              let tail = trim (rewrite_ffi_expr raw_tail) in
              if tail = "" then
                Buffer.add_string b (Printf.sprintf "host_call(%S)" path)
              else
                Buffer.add_string b (Printf.sprintf "host_call(%S, %s)" path tail);
              loop tail_end false false
            end
          end
        | _ ->
          Buffer.add_char b c;
          loop (i + 1) false false
  in
  loop 0 false false;
  Buffer.contents b

let rec normalize_expr s =
  let s = rewrite_ffi_expr (normalize_regex_literals (trim s)) in
  if s = "" then s
  else
    match strip_outer_parens s with
    | Some inner -> "(" ^ normalize_expr inner ^ ")"
    | None -> begin
        match normalize_call_form s with
        | Some x -> x
        | None -> s
      end

and normalize_call_form s =
  let s = trim s in
  let len = String.length s in
  if len = 0 || not (is_symbol_start s.[0]) then None
  else
    let rec read_sym i =
      if i < len && is_symbol_char s.[i] then read_sym (i + 1) else i
    in
    let sym_end = read_sym 1 in
    let head = String.sub s 0 sym_end in
    if head = "if" || head = "else" || head = "while" || head = "foreach"
       || head = "let" || head = "def" || head = "defun" || head = "fun"
       || head = "for" || head = "fn" || head = "rec"
       || head = "return" || head = "unless"
       || head = "match" || head = "case" || head = "enum" || head = "type"
       || head = "break" || head = "continue" then None
    else
      let rest = trim (String.sub s sym_end (len - sym_end)) in
      if rest = "" then None
      else if is_operator_prefix rest.[0] then None
      else if rest.[0] = ':' then None
      else if rest.[0] = '[' || rest.[0] = '{' then None
      else
        let args =
          if rest.[0] = '(' then
            match strip_outer_parens rest with
            | Some inner -> split_top_level_commas inner
            | None -> split_top_level_commas rest
          else
            split_top_level_commas rest
        in
        let normalized_args = List.map normalize_expr args in
        Some (Printf.sprintf "%s(%s)" head (String.concat ", " normalized_args))

let find_assignment_eq s =
  match find_top_level s '=' with
  | None -> None
  | Some i ->
    let prev = if i > 0 then s.[i - 1] else '\x00' in
    let next = if i + 1 < String.length s then s.[i + 1] else '\x00' in
    if prev = '=' || prev = '!' || prev = '<' || prev = '>' || next = '=' || next = '~'
    then None
    else Some i

let normalize_if_like prefix line =
  let p = String.length prefix in
  if String.length line >= p + 1 && String.sub line 0 p = prefix then
    let rest = trim (String.sub line p (String.length line - p)) in
    match strip_trailing_block_opener rest with
    | Some cond -> Some (prefix ^ normalize_expr cond ^ " {")
    | None -> None
  else None

let normalize_foreach line =
  if not (starts_with_keyword line "foreach") then None
  else
    let rest = trim (String.sub line 7 (String.length line - 7)) in
    let inner_opt = strip_trailing_block_opener rest in
    match inner_opt with
    | None -> None
    | Some inner ->
      match find_top_level inner ' ' with
      | None -> None
      | Some first_space ->
        let name = trim (String.sub inner 0 first_space) in
        let tail = trim (String.sub inner (first_space + 1) (String.length inner - first_space - 1)) in
        if not (starts_with_keyword tail "in") then None
        else
          let iter_expr = trim (String.sub tail 2 (String.length tail - 2)) in
          Some (Printf.sprintf "foreach %s in %s {" name (normalize_expr iter_expr))

let normalize_defun_header line =
  let t = trim line in
  if not (starts_with_keyword t "defun") then None
  else
    match strip_trailing_block_opener t with
    | Some body_head ->
      begin
        match normalize_defun_signature body_head with
        | Some normalized -> Some (normalized ^ " {")
        | None -> None
      end
    | None -> None

let normalize_fun_binding_header line =
  match find_assignment_eq line with
  | None -> None
  | Some i ->
    let left = trim (String.sub line 0 i) in
    let right = trim (String.sub line (i + 1) (String.length line - i - 1)) in
    begin
      match strip_trailing_block_opener right with
      | None -> None
      | Some rhs_head when starts_with_keyword rhs_head "fun" ->
        begin
          match normalize_fun_signature rhs_head with
          | Some normalized_fun -> Some (normalize_binding_left left ^ " = " ^ normalized_fun ^ " {")
          | None -> None
        end
      | Some _ -> None
    end

let normalize_fun_expr_header line =
  let t = trim line in
  if not (starts_with_keyword t "fun") then None
  else
    match strip_trailing_block_opener t with
    | Some head ->
      begin
        match normalize_fun_signature head with
        | Some normalized -> Some (normalized ^ " {")
        | None -> None
      end
    | None -> None

let normalize_unless line =
  if not (starts_with_keyword line "unless") then None
  else
    let rest = trim (String.sub line 6 (String.length line - 6)) in
    let mk cond = Printf.sprintf "if not (%s) {" (normalize_expr cond) in
    match strip_trailing_block_opener rest with
    | Some cond -> Some (mk cond)
    | None -> None

let normalize_match_line line =
  if starts_with_keyword line "match" then
    let rest = trim (String.sub line 5 (String.length line - 5)) in
    match strip_trailing_block_opener rest with
    | Some subject -> Some (Printf.sprintf "match %s {" (normalize_expr subject))
    | None -> None
  else None

let normalize_case_line line =
  if starts_with_keyword line "case" then
    let rest = trim (String.sub line 4 (String.length line - 4)) in
    match strip_trailing_block_opener rest with
    | Some pattern -> Some (Printf.sprintf "case %s {" (normalize_expr pattern))
    | None -> None
  else None

let normalize_else_line line =
  let t = trim line in
  if t = "else {" || t = "else do" || t = "else:" then Some "} else {"
  else if starts_with_keyword t "else if" then
    let rest = trim (String.sub t 4 (String.length t - 4)) in
    let cond_tail =
      if starts_with_keyword rest "if" then
        trim (String.sub rest 2 (String.length rest - 2))
      else
        rest
    in
    match strip_trailing_block_opener cond_tail with
    | Some cond -> Some (Printf.sprintf "} else if %s {" (normalize_expr cond))
    | None -> None
  else None

let find_top_level_arrow s =
  let len = String.length s in
  let rec loop i parens braces brackets in_string escaped =
    if i + 1 >= len then None
    else
      let c = s.[i] in
      if in_string then
        if escaped then loop (i + 1) parens braces brackets true false
        else if c = '\\' then loop (i + 1) parens braces brackets true true
        else if c = '"' then loop (i + 1) parens braces brackets false false
        else loop (i + 1) parens braces brackets true false
      else
        match c with
        | '"' -> loop (i + 1) parens braces brackets true false
        | '(' -> loop (i + 1) (parens + 1) braces brackets false false
        | ')' -> loop (i + 1) (max 0 (parens - 1)) braces brackets false false
        | '{' -> loop (i + 1) parens (braces + 1) brackets false false
        | '}' -> loop (i + 1) parens (max 0 (braces - 1)) brackets false false
        | '[' -> loop (i + 1) parens braces (brackets + 1) false false
        | ']' -> loop (i + 1) parens braces (max 0 (brackets - 1)) false false
        | '-' when s.[i + 1] = '>' && parens = 0 && braces = 0 && brackets = 0 -> Some i
        | _ -> loop (i + 1) parens braces brackets false false
  in
  loop 0 0 0 0 false false

type keyword_block_frame =
  | Regular_block
  | Match_block of bool ref

let rewrite_keyword_blocks (lines : string list) : string list =
  let stack : keyword_block_frame list ref = ref [] in
  let open_regular line acc =
    stack := Regular_block :: !stack;
    line :: acc
  in
  let open_match line acc =
    stack := Match_block (ref false) :: !stack;
    line :: acc
  in
  let close_end acc =
    match !stack with
    | Match_block case_open :: rest ->
      stack := rest;
      if !case_open then "}" :: "}" :: acc else "}" :: acc
    | Regular_block :: rest ->
      stack := rest;
      "}" :: acc
    | [] ->
      "end" :: acc
  in
  let rec loop acc = function
    | [] -> List.rev acc
    | line :: rest ->
      let t = trim line in
      if t = "" || (String.length t > 0 && t.[0] = '#') then
        loop (line :: acc) rest
      else if t = "end" then
        loop (close_end acc) rest
      else if starts_with_keyword t "if" then
        let tail = trim (String.sub t 2 (String.length t - 2)) in
        let cond_opt = strip_trailing_keyword tail "then" in
        begin match cond_opt with
        | Some cond ->
          loop (open_regular (Printf.sprintf "if %s {" (normalize_expr cond)) acc) rest
        | None ->
          loop (line :: acc) rest
        end
      else if starts_with_keyword t "elif" then
        let tail = trim (String.sub t 4 (String.length t - 4)) in
        let cond_opt = strip_trailing_keyword tail "then" in
        begin match cond_opt with
        | Some cond ->
          loop ((Printf.sprintf "} else if %s {" (normalize_expr cond)) :: acc) rest
        | None ->
          loop (line :: acc) rest
        end
      else if t = "else" then
        loop ("} else {" :: acc) rest
      else if starts_with_keyword t "while" then
        let tail = trim (String.sub t 5 (String.length t - 5)) in
        begin match strip_trailing_keyword tail "do" with
        | Some cond ->
          loop (open_regular (Printf.sprintf "while %s {" (normalize_expr cond)) acc) rest
        | None ->
          loop (line :: acc) rest
        end
      else if starts_with_keyword t "foreach" then
        begin match normalize_foreach t with
        | Some normalized when String.length normalized > 0
                              && normalized.[String.length normalized - 1] = '{' ->
          loop (open_regular normalized acc) rest
        | _ ->
          loop (line :: acc) rest
        end
      else if starts_with_keyword t "enum" then
        let tail = trim (String.sub t 4 (String.length t - 4)) in
        begin match strip_trailing_keyword tail "do" with
        | Some name ->
          loop (open_regular (Printf.sprintf "enum %s {" (trim name)) acc) rest
        | None ->
          loop (line :: acc) rest
        end
      else if starts_with_keyword t "defun" then
        begin match normalize_defun_header t with
        | Some normalized when String.length normalized > 0
                              && normalized.[String.length normalized - 1] = '{' ->
          loop (open_regular normalized acc) rest
        | _ ->
          loop (line :: acc) rest
        end
      else if starts_with_keyword t "fun" then
        begin match normalize_fun_expr_header t with
        | Some normalized when String.length normalized > 0
                              && normalized.[String.length normalized - 1] = '{' ->
          loop (open_regular normalized acc) rest
        | _ ->
          loop (line :: acc) rest
        end
      else if starts_with_keyword t "match" then
        let tail = trim (String.sub t 5 (String.length t - 5)) in
        begin match strip_trailing_keyword tail "with" with
        | Some subject ->
          loop (open_match (Printf.sprintf "match %s {" (normalize_expr subject)) acc) rest
        | None ->
          loop (line :: acc) rest
        end
      else if String.length t > 0 && t.[0] = '|' then
        begin
          match !stack with
          | Match_block case_open :: _ ->
            let rhs_line =
              match find_top_level_arrow t with
              | Some arrow_i ->
                let raw_pat = trim (String.sub t 1 (arrow_i - 1)) in
                let raw_rhs = trim (String.sub t (arrow_i + 2) (String.length t - arrow_i - 2)) in
                let pat = normalize_expr raw_pat in
                let prefix = if !case_open then ["}"] else [] in
                if raw_rhs = "" then begin
                  case_open := true;
                  prefix @ [Printf.sprintf "case %s {" pat]
                end else begin
                  case_open := false;
                  prefix @ [Printf.sprintf "case %s { %s }" pat (normalize_expr raw_rhs)]
                end
              | None ->
                [line]
            in
            loop (List.rev_append rhs_line acc) rest
          | _ ->
            loop (line :: acc) rest
        end
      else if String.contains t '=' then
        begin match normalize_fun_binding_header t with
        | Some normalized ->
          loop (open_regular normalized acc) rest
        | None ->
          loop (line :: acc) rest
        end
      else
        loop (line :: acc) rest
  in
  loop [] lines

let normalize_line line =
  let t = trim line in
  if t = "" then line
  else if t.[0] = '#' then line
  else if t = "end" then "}"
  else
    match normalize_else_line t with
    | Some x -> x
    | None ->
      begin
        match normalize_defun_header t with
        | Some x -> x
        | None ->
          begin
            match normalize_unless t with
            | Some x -> x
            | None ->
          begin
            match normalize_match_line t with
            | Some x -> x
            | None ->
          begin
            match normalize_case_line t with
            | Some x -> x
            | None ->
          begin
            match normalize_foreach t with
            | Some x -> x
            | None ->
          if ends_with_keyword t "do" then
            normalize_expr (match strip_trailing_keyword t "do" with Some h -> h | None -> t) ^ " {"
          else
            begin
              match normalize_if_like "if " t with
              | Some x -> x
              | None -> begin
                  match normalize_if_like "while " t with
                  | Some x -> x
                  | None -> begin
                      match normalize_foreach t with
                      | Some x -> x
                      | None ->
                        if starts_with_keyword t "return" then
                          let expr = trim (String.sub t 6 (String.length t - 6)) in
                          if expr = "" then t
                          else "return " ^ normalize_expr expr
                        else if starts_with_keyword t "let" || starts_with_keyword t "def" then begin
                          match find_assignment_eq t with
                          | Some i ->
                            let left = trim (String.sub t 0 i) in
                            let right = trim (String.sub t (i + 1) (String.length t - i - 1)) in
                            normalize_binding_left left ^ " = " ^ normalize_expr right
                          | None -> t
                        end else begin
                          match find_assignment_eq t with
                          | Some i ->
                            let left = trim (String.sub t 0 i) in
                            let right = trim (String.sub t (i + 1) (String.length t - i - 1)) in
                            left ^ " = " ^ normalize_expr right
                          | None ->
                            normalize_expr t
                        end
                    end
                end
            end
          end
          end
          end
          end
      end

let is_rec_fn_header t =
  starts_with_keyword t "rec"
  && let rest = trim (String.sub t 3 (String.length t - 3)) in
     starts_with_keyword rest "fn"

let reject line_no message =
  raise (Reader_error { line = line_no; message })

let validate_source_syntax (lines : string list) : unit =
  let check_header line_no t kw sample =
    if ends_with_keyword t kw then
      ()
    else if ends_with_char t ':' then
      reject line_no (Printf.sprintf "Colon blocks are not supported; use `%s`." sample)
    else if find_top_level t '{' <> None || t = "}" then
      reject line_no (Printf.sprintf "Brace blocks are not supported; use `%s`." sample)
    else
      ()
  in
  let check_typed_binding line_no t =
    if starts_with_keyword t "let" || starts_with_keyword t "def" then
      match find_assignment_eq t with
      | None -> ()
      | Some i ->
        let left = trim (String.sub t 0 i) in
        let kw_len =
          if starts_with_keyword left "let" then 3
          else if starts_with_keyword left "def" then 3
          else 0
        in
        if kw_len = 0 then ()
        else
          let rest = trim (String.sub left kw_len (String.length left - kw_len)) in
          if find_top_level rest ':' <> None && normalize_binding_left left = left then
            reject line_no "Invalid typed binding; use `let/def <name> : <Type> = ...` with a Ucfirst type."
          else
            ()
    else
      ()
  in
  let check_typed_fun_binding line_no t =
    match find_assignment_eq t with
    | None -> ()
    | Some i ->
      let right = trim (String.sub t (i + 1) (String.length t - i - 1)) in
      begin
        match strip_trailing_block_opener right with
        | Some rhs when starts_with_keyword rhs "fun" ->
          if normalize_fun_signature rhs = None then
            reject line_no "Invalid `fun` signature; use `fun(<name> : <Type>, ...) => <Type> do ... end`."
        | _ -> ()
      end
  in
  let rec loop line_no = function
    | [] -> ()
    | line :: rest ->
      let t = trim line in
      if t = "" || (String.length t > 0 && t.[0] = '#') then
        loop (line_no + 1) rest
      else begin
        begin
          match find_compact_keyword_or_type_colon t with
          | Some token ->
            reject line_no
              (Printf.sprintf "`%s` is not supported; use `<name> : <Type>` for type annotations or `:<kw>`/`<kw>:` for keywords." token)
          | None -> ()
        end;
        begin
          match find_non_lc_postfix_keyword t with
          | Some kw ->
            reject line_no
              (Printf.sprintf "Postfix keyword literals must be lowercase; `%s` is invalid. Use `:<kw>` or lowercase `<kw>:`." kw)
          | None -> ()
        end;
        check_typed_binding line_no t;
        check_typed_fun_binding line_no t;
        if t = "}" then
          reject line_no "Brace blocks are not supported; use `end`."
        else if starts_with_keyword t "else if" then
          reject line_no "Use `elif ... then` instead of `else if`."
        else if starts_with_keyword t "case" then
          reject line_no "Case blocks are not supported in source; use `| pattern -> ...` inside `match ... with`."
        else if starts_with_keyword t "if" then begin
          if ends_with_keyword t "do" then
            reject line_no "`if ... do` is not supported; use `if ... then`."
          else
            check_header line_no t "then" "if <cond> then ... end";
          loop (line_no + 1) rest
        end else if starts_with_keyword t "elif" then begin
          if ends_with_keyword t "do" then
            reject line_no "`elif ... do` is not supported; use `elif ... then`."
          else
            check_header line_no t "then" "elif <cond> then ... end";
          loop (line_no + 1) rest
        end else if t = "else" then
          loop (line_no + 1) rest
        else if starts_with_keyword t "else" then begin
          if t = "else do" then
            reject line_no "`else do` is not supported; use `else`."
          else if ends_with_char t ':' then
            reject line_no "Colon blocks are not supported; use `else ... end`."
          else if find_top_level t '{' <> None then
            reject line_no "Brace blocks are not supported; use `else ... end`."
          else
            ();
          loop (line_no + 1) rest
        end else if starts_with_keyword t "while" then begin
          check_header line_no t "do" "while <cond> do ... end";
          loop (line_no + 1) rest
        end else if starts_with_keyword t "for" then begin
          reject line_no "`for` is not supported; use `foreach <name> in <expr> do ... end`."
        end else if starts_with_keyword t "foreach" then begin
          check_header line_no t "do" "foreach <name> in <expr> do ... end";
          loop (line_no + 1) rest
        end else if starts_with_keyword t "enum" then begin
          check_header line_no t "do" "enum <name> do ... end";
          loop (line_no + 1) rest
        end else if starts_with_keyword t "fn" || is_rec_fn_header t then begin
          reject line_no "`fn`/`rec fn` are not supported; use `defun <name> ... do ... end`."
        end else if starts_with_keyword t "defun" then begin
          check_header line_no t "do" "defun <name> ... do ... end";
          begin
            match strip_trailing_block_opener t with
            | Some head when normalize_defun_signature head = None ->
              reject line_no "Invalid `defun` signature; use `defun <name>(<p> : <Type>, ...) => <Type> do ... end`."
            | _ -> ()
          end;
          loop (line_no + 1) rest
        end else if starts_with_keyword t "fun" then begin
          check_header line_no t "do" "fun(...) do ... end";
          begin
            match strip_trailing_block_opener t with
            | Some head when normalize_fun_signature head = None ->
              reject line_no "Invalid `fun` signature; use `fun(<p> : <Type>, ...) => <Type> do ... end`."
            | _ -> ()
          end;
          loop (line_no + 1) rest
        end else if starts_with_keyword t "match" then begin
          check_header line_no t "with" "match <expr> with ... end";
          loop (line_no + 1) rest
        end else if starts_with_keyword t "unless" then begin
          check_header line_no t "do" "unless <cond> do ... end";
          loop (line_no + 1) rest
        end else
          loop (line_no + 1) rest
      end
  in
  loop 1 lines

let rewrite_source ?(module_name = "") (source : string) : string =
  let lines = String.split_on_char '\n' source in
  let _ = module_name in
  validate_source_syntax lines;
  let lines = rewrite_keyword_blocks lines in
  String.concat "\n" (List.map normalize_line lines)

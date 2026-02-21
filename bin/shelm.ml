let () =
  let usage =
    "shelm - a proglang for lanzy people\n\
     Usage: shelm <file.shlm> --target perl|ocaml|go|bytecode\n\
     Benchmark: shelm <file.shlm> --benchmark <reference.pl> [--iterations N] [--host <host.pl>]"
  in
  let target = ref "" in
  let benchmark_ref = ref "" in
  let benchmark_iterations = ref 20 in
  let benchmark_host = ref "" in
  let filename = ref "" in
  let speclist = [
    ("--target", Arg.Set_string target, "Target language: perl, ocaml, go, or bytecode");
    ("--benchmark", Arg.Set_string benchmark_ref, "Run Perl-vs-Shelm benchmark against reference Perl file");
    ("--iterations", Arg.Set_int benchmark_iterations, "Benchmark iterations (default: 20)");
    ("--host", Arg.Set_string benchmark_host, "Host file for generated Shelm Perl (benchmark mode)");
  ] in
  Arg.parse speclist (fun f -> filename := f) usage;
  if !filename = "" then (
    Printf.eprintf "%s\n" usage;
    exit 1
  );
  if Filename.extension !filename <> ".shlm" then (
    Printf.eprintf "Error: Shelm source file must use .shlm extension (got: %s)\n" !filename;
    exit 1
  );
  if !benchmark_ref <> "" then (
    if !target <> "" then (
      Printf.eprintf "Error: --target cannot be used with --benchmark\n";
      exit 1
    );
    if !benchmark_iterations < 1 then (
      Printf.eprintf "Error: --iterations must be >= 1\n";
      exit 1
    );
    let script = "scripts/compare-perl-vs-shelm.sh" in
    if not (Sys.file_exists script) then (
      Printf.eprintf "Error: benchmark script not found: %s\n" script;
      exit 1
    );
    let quoted = Filename.quote in
    let cmd_parts =
      [
        quoted script;
        "--perl"; quoted !benchmark_ref;
        "--shelm"; quoted !filename;
        "--iterations"; string_of_int !benchmark_iterations;
      ]
      @ (if !benchmark_host = "" then [] else ["--host"; quoted !benchmark_host])
    in
    let code = Sys.command (String.concat " " cmd_parts) in
    exit code
  );
  if !target = "" then (
    Printf.eprintf "Error: --target is required (perl, ocaml, go, or bytecode)\n";
    exit 1
  );
  match Shelm_lib.Shelm.compile_file_target !target !filename with
  | Ok code -> print_string code
  | Error err ->
    Printf.eprintf "%s\n" (Shelm_lib.Errors.format_error err);
    exit 1

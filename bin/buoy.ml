let () =
  let usage =
    "buoy - a proglang for lanzy people\n\
     Usage: buoy <file.by> --target perl|ocaml|go|bytecode\n\
     Benchmark: buoy <file.by> --benchmark <reference.pl> [--iterations N] [--host <host.pl>]"
  in
  let target = ref "" in
  let benchmark_ref = ref "" in
  let benchmark_iterations = ref 20 in
  let benchmark_host = ref "" in
  let filename = ref "" in
  let speclist = [
    ("--target", Arg.Set_string target, "Target language: perl, ocaml, go, or bytecode");
    ("--benchmark", Arg.Set_string benchmark_ref, "Run Perl-vs-Buoy benchmark against reference Perl file");
    ("--iterations", Arg.Set_int benchmark_iterations, "Benchmark iterations (default: 20)");
    ("--host", Arg.Set_string benchmark_host, "Host file for generated Buoy Perl (benchmark mode)");
  ] in
  Arg.parse speclist (fun f -> filename := f) usage;
  if !filename = "" then (
    Printf.eprintf "%s\n" usage;
    exit 1
  );
  if Filename.extension !filename <> ".by" then (
    Printf.eprintf "Error: Buoy source file must use .by extension (got: %s)\n" !filename;
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
    let script = "scripts/compare-perl-vs-buoy.sh" in
    if not (Sys.file_exists script) then (
      Printf.eprintf "Error: benchmark script not found: %s\n" script;
      exit 1
    );
    let quoted = Filename.quote in
    let cmd_parts =
      [
        quoted script;
        "--perl"; quoted !benchmark_ref;
        "--buoy"; quoted !filename;
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
  match Buoy_lib.Buoy.compile_file_target !target !filename with
  | Ok code -> print_string code
  | Error err ->
    Printf.eprintf "%s\n" (Buoy_lib.Errors.format_error err);
    exit 1

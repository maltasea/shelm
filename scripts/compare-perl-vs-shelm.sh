#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/compare-perl-vs-shelm.sh --perl <reference.pl> --shelm <equivalent.shlm> [options]

Options:
  --iterations <n>     Number of timed runs per program (default: 20)
  --host <file>        Perl host file loaded by generated Shelm Perl via SHELM_PERL_HOST
  --no-output-check    Skip strict output equality check before timing
  -h, --help           Show this help
EOF
}

abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s\n' "$(pwd)/$p"
  fi
}

perl_file=""
shelm_file=""
host_file=""
iterations=20
output_check=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --perl)
      perl_file="$2"
      shift 2
      ;;
    --shelm)
      shelm_file="$2"
      shift 2
      ;;
    --host)
      host_file="$2"
      shift 2
      ;;
    --iterations)
      iterations="$2"
      shift 2
      ;;
    --no-output-check)
      output_check=0
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$perl_file" || -z "$shelm_file" ]]; then
  usage >&2
  exit 1
fi

if ! [[ "$iterations" =~ ^[0-9]+$ ]] || [[ "$iterations" -lt 1 ]]; then
  echo "--iterations must be a positive integer" >&2
  exit 1
fi

perl_file="$(abs_path "$perl_file")"
shelm_file="$(abs_path "$shelm_file")"
if [[ -n "$host_file" ]]; then
  host_file="$(abs_path "$host_file")"
fi

if [[ ! -f "$perl_file" ]]; then
  echo "Perl file not found: $perl_file" >&2
  exit 1
fi

if [[ ! -f "$shelm_file" ]]; then
  echo "Shelm file not found: $shelm_file" >&2
  exit 1
fi

if [[ -n "$host_file" && ! -f "$host_file" ]]; then
  echo "Host file not found: $host_file" >&2
  exit 1
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/shelm-bench.XXXXXX")"
compiled_shelm="$tmp_dir/shelm_equiv.pl"
trap 'rm -rf "$tmp_dir"' EXIT

build_shelm_compiler() {
  if command -v opam >/dev/null 2>&1; then
    opam exec -- dune build ./bin/shelm.exe >/dev/null
  else
    dune build ./bin/shelm.exe >/dev/null
  fi
}

(
  cd "$root_dir"
  build_shelm_compiler
  ./_build/default/bin/shelm.exe "$shelm_file" --target perl > "$compiled_shelm"
)

run_perl_capture() {
  local file="$1"
  if [[ -n "$host_file" ]]; then
    SHELM_PERL_HOST="$host_file" perl "$file"
  else
    perl "$file"
  fi
}

if [[ "$output_check" -eq 1 ]]; then
  native_out_file="$tmp_dir/native.out"
  shelm_out_file="$tmp_dir/shelm.out"

  perl "$perl_file" >"$native_out_file"
  run_perl_capture "$compiled_shelm" >"$shelm_out_file"

  if ! diff -u "$native_out_file" "$shelm_out_file" >/dev/null; then
    echo "Output mismatch between reference Perl and Shelm->Perl. Timing aborted." >&2
    echo "Re-run with --no-output-check if this is expected." >&2
    diff -u "$native_out_file" "$shelm_out_file" || true
    exit 1
  fi
fi

measure_avg_ms() {
  local file="$1"
  local runs="$2"
  local host="${3:-}"
  perl -MTime::HiRes=time -e '
    use File::Spec ();
    my ($prog, $n, $host_file) = @ARGV;
    my $total = 0.0;
    open my $report, ">&", \*STDOUT or die "dup stdout failed: $!";
    open STDOUT, ">", File::Spec->devnull() or die "redirect stdout failed: $!";
    open STDERR, ">", File::Spec->devnull() or die "redirect stderr failed: $!";
    for (1..$n) {
      local $ENV{SHELM_PERL_HOST} = $host_file if defined $host_file && length $host_file;
      my $t0 = time();
      my $rc = system($^X, $prog);
      if ($rc != 0) {
        my $code = $rc >> 8;
        die "Program failed during benchmark with exit code $code: $prog\n";
      }
      $total += (time() - $t0);
    }
    print {$report} sprintf("%.6f\n", ($total * 1000.0 / $n));
  ' "$file" "$runs" "$host"
}

native_ms="$(measure_avg_ms "$perl_file" "$iterations")"
shelm_ms="$(measure_avg_ms "$compiled_shelm" "$iterations" "$host_file")"
ratio="$(perl -e 'my ($a, $b) = @ARGV; printf "%.4f\n", ($b == 0 ? 0 : $a / $b);' "$shelm_ms" "$native_ms")"

echo "Perl benchmark comparison"
echo "  Reference Perl : $perl_file"
echo "  Shelm source    : $shelm_file"
echo "  Shelm->Perl file: $compiled_shelm"
if [[ -n "$host_file" ]]; then
  echo "  Host file      : $host_file"
fi
echo "  Iterations     : $iterations"
echo ""
echo "Average wall-clock time per run (ms):"
echo "  Perl reference : $native_ms"
echo "  Shelm -> Perl   : $shelm_ms"
echo "  Ratio          : ${ratio}x (Shelm->Perl / Perl)"

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/compare-perl-vs-buoy.sh --perl <reference.pl> --buoy <equivalent.by> [options]

Options:
  --iterations <n>     Number of timed runs per program (default: 20)
  --host <file>        Perl host file loaded by generated Buoy Perl via BUOY_PERL_HOST
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
buoy_file=""
host_file=""
iterations=20
output_check=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --perl)
      perl_file="$2"
      shift 2
      ;;
    --buoy)
      buoy_file="$2"
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

if [[ -z "$perl_file" || -z "$buoy_file" ]]; then
  usage >&2
  exit 1
fi

if ! [[ "$iterations" =~ ^[0-9]+$ ]] || [[ "$iterations" -lt 1 ]]; then
  echo "--iterations must be a positive integer" >&2
  exit 1
fi

perl_file="$(abs_path "$perl_file")"
buoy_file="$(abs_path "$buoy_file")"
if [[ -n "$host_file" ]]; then
  host_file="$(abs_path "$host_file")"
fi

if [[ ! -f "$perl_file" ]]; then
  echo "Perl file not found: $perl_file" >&2
  exit 1
fi

if [[ ! -f "$buoy_file" ]]; then
  echo "Buoy file not found: $buoy_file" >&2
  exit 1
fi

if [[ -n "$host_file" && ! -f "$host_file" ]]; then
  echo "Host file not found: $host_file" >&2
  exit 1
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/buoy-bench.XXXXXX")"
compiled_buoy="$tmp_dir/buoy_equiv.pl"
trap 'rm -rf "$tmp_dir"' EXIT

build_buoy_compiler() {
  if command -v opam >/dev/null 2>&1; then
    opam exec -- dune build ./bin/buoy.exe >/dev/null
  else
    dune build ./bin/buoy.exe >/dev/null
  fi
}

(
  cd "$root_dir"
  build_buoy_compiler
  ./_build/default/bin/buoy.exe "$buoy_file" --target perl > "$compiled_buoy"
)

run_perl_capture() {
  local file="$1"
  if [[ -n "$host_file" ]]; then
    BUOY_PERL_HOST="$host_file" perl "$file"
  else
    perl "$file"
  fi
}

if [[ "$output_check" -eq 1 ]]; then
  native_out_file="$tmp_dir/native.out"
  buoy_out_file="$tmp_dir/buoy.out"

  perl "$perl_file" >"$native_out_file"
  run_perl_capture "$compiled_buoy" >"$buoy_out_file"

  if ! diff -u "$native_out_file" "$buoy_out_file" >/dev/null; then
    echo "Output mismatch between reference Perl and Buoy->Perl. Timing aborted." >&2
    echo "Re-run with --no-output-check if this is expected." >&2
    diff -u "$native_out_file" "$buoy_out_file" || true
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
      local $ENV{BUOY_PERL_HOST} = $host_file if defined $host_file && length $host_file;
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
buoy_ms="$(measure_avg_ms "$compiled_buoy" "$iterations" "$host_file")"
ratio="$(perl -e 'my ($a, $b) = @ARGV; printf "%.4f\n", ($b == 0 ? 0 : $a / $b);' "$buoy_ms" "$native_ms")"

echo "Perl benchmark comparison"
echo "  Reference Perl : $perl_file"
echo "  Buoy source    : $buoy_file"
echo "  Buoy->Perl file: $compiled_buoy"
if [[ -n "$host_file" ]]; then
  echo "  Host file      : $host_file"
fi
echo "  Iterations     : $iterations"
echo ""
echo "Average wall-clock time per run (ms):"
echo "  Perl reference : $native_ms"
echo "  Buoy -> Perl   : $buoy_ms"
echo "  Ratio          : ${ratio}x (Buoy->Perl / Perl)"

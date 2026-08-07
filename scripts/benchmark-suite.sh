#!/bin/sh
set -eu

processes=${BENCHMARK_PROCESSES:-5}
ticks=${BENCHMARK_TICKS:-5000}
warmup=${BENCHMARK_WARMUP:-500}
samples=${BENCHMARK_SAMPLES:-7}
sizes=${BENCHMARK_SIZES:-80x24,120x40,200x60}
timeout_seconds=${BENCHMARK_TIMEOUT_SECONDS:-120}
output=${BENCHMARK_OUTPUT:-benchmark-results.tsv}
log_dir=${BENCHMARK_LOG_DIR:-${output}.d}

case "$processes:$ticks:$warmup:$samples:$timeout_seconds" in
  *[!0-9:]*|0:*)
    printf '%s\n' "benchmark-suite: numeric settings must be non-negative integers and processes must be positive" >&2
    exit 2
    ;;
esac

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$log_dir"

printf '%s\n' 'width	height	process	workload	median_ns_per_tick	median_bytes_per_tick	log' >"$output"

old_ifs=$IFS
IFS=,
for size in $sizes; do
  IFS=x
  set -- $size
  IFS=$old_ifs
  if [ "$#" -ne 2 ]; then
    printf 'benchmark-suite: invalid size %s; expected WIDTHxHEIGHT\n' "$size" >&2
    exit 2
  fi
  width=$1
  height=$2
  case "$width:$height" in
    *[!0-9:]*|0:*|*:0)
      printf 'benchmark-suite: invalid size %s; dimensions must be positive integers\n' "$size" >&2
      exit 2
      ;;
  esac

  process=1
  while [ "$process" -le "$processes" ]; do
    log="$log_dir/${width}x${height}-${process}.log"
    perl -e '
      use strict;
      use warnings;
      my $timeout = shift @ARGV;
      $SIG{ALRM} = sub { die "benchmark process timed out after ${timeout}s\n" };
      alarm $timeout;
      exec @ARGV or die "cannot exec benchmark: $!\n";
    ' "$timeout_seconds" sbcl --script "$root/scripts/benchmark.lisp" \
      --width "$width" --height "$height" --ticks "$ticks" \
      --warmup "$warmup" --samples "$samples" >"$log"

    perl -e '
      use strict;
      use warnings;
      my ($width, $height, $process, $log) = @ARGV;
      open my $fh, "<", $log or die "cannot read $log: $!\n";
      my $workload;
      my $found = 0;
      while (<$fh>) {
        chomp;
        if (/^(matrix advance(?: \+ dirty render)?)$/) {
          $workload = $1;
          next;
        }
        if (defined $workload && /^  median:\s+([0-9,]+) ns\/tick,\s+([0-9,]+) bytes-consed\/tick$/) {
          my ($ns, $bytes) = ($1, $2);
          $ns =~ tr/,//d;
          $bytes =~ tr/,//d;
          print join("\t", $width, $height, $process, $workload, $ns, $bytes, $log), "\n";
          ++$found;
          undef $workload;
        }
      }
      die "benchmark log $log contained $found workload medians, expected 2\n" if $found != 2;
    ' "$width" "$height" "$process" "$log" >>"$output"
    process=$((process + 1))
  done
  IFS=,
done
IFS=$old_ifs

expected=$((processes * 2))
for size in $(printf '%s' "$sizes" | perl -pe 's/,/ /g'); do
  rows=$(perl -F'\t' -lane 'BEGIN { $target = shift @ARGV; $n = 0 } $F[0]."x".$F[1] eq $target and ++$n; END { print $n }' "$size" "$output")
  if [ "$rows" -ne "$expected" ]; then
    printf 'benchmark-suite: %s produced %s rows, expected %s\n' "$size" "$rows" "$expected" >&2
    exit 1
  fi
done

printf 'benchmark-suite: wrote %s workload results per size to %s\n' "$((processes * 2))" "$output"

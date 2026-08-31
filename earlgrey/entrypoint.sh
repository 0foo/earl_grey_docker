#!/usr/bin/env bash
set -euo pipefail

# Wraps earlGrey: on a non-zero exit (crash, OOM-kill, interruption), flags
# the run clearly in the log and writes an INCOMPLETE_RUN.txt marker into
# the output dir so a partial result never gets mistaken for a completed
# one later.

args=("$@")
output_dir=""

i=0
while [ $i -lt ${#args[@]} ]; do
	if [ "${args[$i]}" = "-o" ]; then
		output_dir="${args[$((i + 1))]:-}"
	fi
	i=$((i + 1))
done

status=0
# earlGrey's progress bars redraw with \r (carriage return), which a real
# terminal overwrites in place — but redirected to a file (docker logs > file,
# a log from run-queue.sh, anything non-TTY) every redraw instead piles up as
# its own line, ballooning the log. `sed 's/.*\r//'` collapses each burst of
# \r-redraws down to just the last one, i.e. what a terminal would have shown.
# Requires merging stderr into stdout (2>&1) so warnings interleaved with a
# progress line by RepeatModeler survive the same transform in the same order.
conda run --no-capture-output -n earlgrey earlGrey "${args[@]}" 2>&1 | sed -u 's/.*\r//' || status=$?

if [ "$status" -ne 0 ]; then
	echo "=== earlGrey exited with status $status — did NOT complete successfully. Any output below is PARTIAL. ===" >&2
	if [ -n "$output_dir" ] && [ -d "$output_dir" ]; then
		{
			echo "INCOMPLETE RUN"
			echo "earlGrey exited with status $status before finishing — this output is partial, not a completed result."
			echo "Terminated at: $(date -u +%FT%TZ)"
		} >"$output_dir/INCOMPLETE_RUN.txt" 2>/dev/null || true
	fi
fi

exit "$status"

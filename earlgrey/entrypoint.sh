#!/usr/bin/env bash
set -euo pipefail

# Wraps earlGrey so -g/-o accept either a local path (bind-mounted for local
# testing) or an s3:// URI (for the vps/ work-queue running on dedicated/VPS
# boxes): s3 inputs are downloaded before the run, and if -o is an s3:// URI,
# results are synced back up afterward.
#
# DFAM_S3_URI, if set, is synced once per host into the fixed famdb path
# below instead of requiring a bind mount — a flock guards concurrent
# containers on the same host from downloading it twice, in case more than
# one is ever run against the same host path at once.

dfam_path="/opt/conda/envs/earlgrey/share/famdb-3.0.0/Libraries/famdb"

if [ -n "${DFAM_S3_URI:-}" ]; then
	mkdir -p "$dfam_path"
	(
		flock -x 200
		if [ ! -e "$dfam_path/.cache-complete" ]; then
			echo "Caching Dfam data from $DFAM_S3_URI to $dfam_path ..." >&2
			aws s3 sync --no-progress "$DFAM_S3_URI" "$dfam_path"
			touch "$dfam_path/.cache-complete"
		fi
	) 200>"$dfam_path/.download.lock"
fi

args=("$@")

genome_local=""
output_local=""
output_s3=""
new_args=()

i=0
while [ $i -lt ${#args[@]} ]; do
	arg="${args[$i]}"
	case "$arg" in
	-g)
		i=$((i + 1))
		val="${args[$i]:-}"
		if [[ "$val" == s3://* ]]; then
			mkdir -p /tmp/earlgrey-input
			genome_local="/tmp/earlgrey-input/$(basename "$val")"
			aws s3 cp --no-progress "$val" "$genome_local"
			if [[ "$genome_local" == *.gz ]]; then
				gunzip -f "$genome_local"
				genome_local="${genome_local%.gz}"
			fi
			new_args+=("-g" "$genome_local")
		else
			new_args+=("-g" "$val")
		fi
		;;
	-o)
		i=$((i + 1))
		val="${args[$i]:-}"
		if [[ "$val" == s3://* ]]; then
			output_s3="$val"
			output_local="/tmp/earlgrey-output"
			mkdir -p "$output_local"
			new_args+=("-o" "$output_local")
		else
			new_args+=("-o" "$val")
		fi
		;;
	*)
		new_args+=("$arg")
		;;
	esac
	i=$((i + 1))
done

status=0
conda run --no-capture-output -n earlgrey earlGrey "${new_args[@]}" || status=$?

# A crash, an OOM-kill, or the process being interrupted all surface here as
# a non-zero exit rather than the container disappearing before this point
# runs — flag it clearly, in the log AND in the synced output itself, so a
# partial result never gets mistaken for a completed one later.
if [ "$status" -ne 0 ]; then
	echo "=== earlGrey exited with status $status — did NOT complete successfully. Any output below is PARTIAL. ===" >&2
	if [ -n "$output_local" ] && [ -d "$output_local" ]; then
		{
			echo "INCOMPLETE RUN"
			echo "earlGrey exited with status $status before finishing — this output is partial, not a completed result."
			echo "Terminated at: $(date -u +%FT%TZ)"
		} >"$output_local/INCOMPLETE_RUN.txt" 2>/dev/null || true
	fi
fi

if [ -n "$output_s3" ]; then
	aws s3 sync --no-progress "$output_local" "$output_s3"
	if [ "$status" -eq 0 ]; then
		# aws s3 sync never deletes — an earlier failed/interrupted attempt's
		# INCOMPLETE_RUN.txt would otherwise linger in S3 forever even after
		# a later retry succeeds, wrongly flagging a good result as partial.
		# Deliberately not `sync --delete` in general: a resubmit that
		# crashes very early (empty local output dir) would otherwise wipe
		# out a previously-successful result sitting under the same path.
		aws s3 rm --quiet "${output_s3%/}/INCOMPLETE_RUN.txt" >/dev/null 2>&1 || true
	fi
fi

exit "$status"

#!/usr/bin/env bash
set -euo pipefail

# Wraps earlGrey so -g/-o accept either a local path (bind-mounted for local
# testing) or an s3:// URI (for AWS Batch): s3 inputs are downloaded before
# the run, and if -o is an s3:// URI, results are synced back up afterward.
#
# AWS Batch array-job mode: if MANIFEST_S3_URI is set and no -g is passed as
# an argument, the genome/species for this job are resolved from line
# (AWS_BATCH_JOB_ARRAY_INDEX + 1) of that manifest — a tab-separated
# "<species>\t<genome-s3-uri>" file. OUTPUT_S3_PREFIX then supplies -o as
# "<prefix>/<species>", and THREADS (if set) supplies -t.
#
# DFAM_S3_URI, if set, is synced once per EC2 host into the fixed famdb path
# below instead of requiring a bind mount or baking Dfam into the image —
# the Batch job definition host-mounts that path so every job on the same
# instance shares the cache. A flock guards concurrent jobs on the same host
# from downloading it twice.

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

if [ -n "${MANIFEST_S3_URI:-}" ]; then
	has_g=0
	for a in "${args[@]}"; do
		if [ "$a" = "-g" ]; then
			has_g=1
		fi
	done
	if [ "$has_g" -eq 0 ]; then
		index="${AWS_BATCH_JOB_ARRAY_INDEX:-0}"
		manifest_local="/tmp/earlgrey-manifest.tsv"
		aws s3 cp --no-progress "$MANIFEST_S3_URI" "$manifest_local"
		line="$(sed -n "$((index + 1))p" "$manifest_local")"
		if [ -z "$line" ]; then
			echo "No manifest line at index $index in $MANIFEST_S3_URI" >&2
			exit 1
		fi
		species="$(cut -f1 <<<"$line")"
		genome_uri="$(cut -f2 <<<"$line")"
		: "${OUTPUT_S3_PREFIX:?OUTPUT_S3_PREFIX must be set when MANIFEST_S3_URI is used}"
		# Printed unconditionally, before anything that could OOM/crash, so a
		# failed job's CloudWatch log always identifies which genome it was
		# even if earlGrey itself never got to log anything.
		echo "Batch array index ${index}: species=${species} genome=${genome_uri}" >&2
		args+=(-g "$genome_uri" -s "$species" -o "${OUTPUT_S3_PREFIX%/}/$species")
		if [ -n "${THREADS:-}" ]; then
			args+=(-t "$THREADS")
		fi
	fi
fi

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

# A Spot interruption, OOM-kill, or timeout all surface here as a non-zero
# exit rather than the container being torn down before this point runs —
# flag it clearly, in the log AND in the synced output itself, so a partial
# result never gets mistaken for a live/still-running or silently-broken
# run later.
if [ "$status" -ne 0 ]; then
	echo "=== earlGrey exited with status $status — did NOT complete successfully. Any output below is PARTIAL. Common causes: Spot Instance interruption, an out-of-memory kill, or the job's timeout being reached. ===" >&2
	if [ -n "$output_local" ] && [ -d "$output_local" ]; then
		{
			echo "INCOMPLETE RUN"
			echo "earlGrey exited with status $status before finishing — this output is partial, not a completed result."
			echo "Common causes: a Spot Instance interruption, an out-of-memory kill, or the job hitting its timeout."
			echo "Terminated at: $(date -u +%FT%TZ)"
		} >"$output_local/INCOMPLETE_RUN.txt" 2>/dev/null || true
	fi
fi

if [ -n "$output_s3" ]; then
	aws s3 sync --no-progress "$output_local" "$output_s3"
fi

exit "$status"

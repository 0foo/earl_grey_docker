#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 4 ]; then
	echo "Usage: $(basename "$0") <image> <manifest-slice.tsv> <dfam-path-or-s3-uri> <output-path-or-s3-prefix> [threads]" >&2
	echo "  Works sequentially through every '<species>\\t<genome-path-or-uri>'" >&2
	echo "  line in the manifest slice: skips a species whose output already" >&2
	echo "  completed successfully (resume-safe across restarts — detected by" >&2
	echo "  an EarlGrey log existing with no INCOMPLETE_RUN.txt marker)," >&2
	echo "  otherwise runs earlGrey via Docker. A failed genome is logged and" >&2
	echo "  skipped — it does not stop the queue, so one bad genome can't" >&2
	echo "  halt a multi-week unattended run." >&2
	echo "  dfam/output/genome (the manifest's 2nd column) can each" >&2
	echo "  independently be an s3:// URI or a local path — mixing is fine." >&2
	echo "  Local Dfam is bind-mounted read-only; s3:// Dfam is cached once" >&2
	echo "  into /root/dfam-cache and reused for every genome on this box." >&2
	echo "  threads defaults to 4 — sized for 64GB RAM at ~12GB/thread with" >&2
	echo "  headroom, since a single RepeatModeler worker has been observed" >&2
	echo "  spiking to ~60GB RSS by itself; the setup script's swap file is" >&2
	echo "  the backstop if that headroom isn't enough." >&2
	echo "Example (S3): $(basename "$0") earlgrey-insects:latest \\" >&2
	echo "    manifest-01.tsv s3://my-bucket/dfam_data s3://my-bucket/output" >&2
	echo "Example (local): $(basename "$0") earlgrey-insects:latest \\" >&2
	echo "    manifest-01.tsv /data/dfam_data /data/output" >&2
	exit 1
fi

image="$1"
manifest="$2"
dfam="$3"
output_prefix="${4%/}"
threads="${5:-4}"

dfam_is_s3=0
if [[ "$dfam" == s3://* ]]; then
	dfam_is_s3=1
fi
output_is_s3=0
if [[ "$output_prefix" == s3://* ]]; then
	output_is_s3=1
fi

if [ "$dfam_is_s3" -eq 1 ]; then
	mkdir -p /root/dfam-cache
else
	dfam="$(realpath "$dfam")"
fi
if [ "$output_is_s3" -eq 0 ]; then
	output_prefix="$(realpath -m "$output_prefix")"
	mkdir -p "$output_prefix"
fi

log="queue-$(basename "$manifest" .tsv).log"
echo "Starting queue from $manifest — logging to $log" | tee -a "$log"

total="$(wc -l <"$manifest" | tr -d ' ')"
n=0
while IFS=$'\t' read -r species genome; do
	n=$((n + 1))
	if [ -z "$species" ]; then
		continue
	fi

	dest="${output_prefix}/${species}"
	log_marker="${dest}/${species}_EarlGrey/${species}_EarlGrey.log"
	incomplete_marker="${dest}/INCOMPLETE_RUN.txt"

	is_done=0
	if [ "$output_is_s3" -eq 1 ]; then
		if aws s3 ls "$log_marker" >/dev/null 2>&1; then
			if ! aws s3 ls "$incomplete_marker" >/dev/null 2>&1; then
				is_done=1
			fi
		fi
	else
		if [ -f "$log_marker" ] && [ ! -f "$incomplete_marker" ]; then
			is_done=1
		fi
	fi

	if [ "$is_done" -eq 1 ]; then
		echo "[$n/$total] $species — already completed, skipping" | tee -a "$log"
		continue
	fi

	mounts=(-v ~/.aws:/root/.aws:ro)
	env_args=()
	if [ "$dfam_is_s3" -eq 1 ]; then
		mounts+=(-v /root/dfam-cache:/opt/conda/envs/earlgrey/share/famdb-3.0.0/Libraries/famdb)
		env_args+=(-e "DFAM_S3_URI=$dfam")
	else
		mounts+=(-v "$dfam:/opt/conda/envs/earlgrey/share/famdb-3.0.0/Libraries/famdb:ro")
	fi

	if [ "$output_is_s3" -eq 0 ]; then
		mounts+=(-v "$output_prefix:$output_prefix")
	fi

	genome_arg="$genome"
	if [[ "$genome" != s3://* ]]; then
		genome="$(realpath "$genome")"
		genome_arg="$genome"
		genome_dir="$(dirname "$genome")"
		if [ "$genome_dir" != "$output_prefix" ]; then
			mounts+=(-v "$genome_dir:$genome_dir")
		fi
	fi

	echo "[$n/$total] $species — starting $(date -u +%FT%TZ)" | tee -a "$log"
	if docker run --rm "${mounts[@]}" "${env_args[@]}" \
		"$image" -g "$genome_arg" -s "$species" -o "$dest" -t "$threads" >>"$log" 2>&1; then
		echo "[$n/$total] $species — SUCCEEDED $(date -u +%FT%TZ)" | tee -a "$log"
	else
		echo "[$n/$total] $species — FAILED $(date -u +%FT%TZ), see $log for details" | tee -a "$log"
	fi
done <"$manifest"

echo "Queue finished: $total genomes processed. See $log for the full run history." | tee -a "$log"

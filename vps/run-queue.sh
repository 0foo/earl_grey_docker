#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 4 ]; then
	echo "Usage: $(basename "$0") <image> <manifest-slice.tsv> <dfam-s3-uri> <output-s3-prefix> [threads]" >&2
	echo "  Works sequentially through every '<species>\\t<genome-s3-uri>'" >&2
	echo "  line in the manifest slice: skips a species whose output already" >&2
	echo "  completed successfully in S3 (resume-safe across restarts —" >&2
	echo "  detected by an EarlGrey log existing with no INCOMPLETE_RUN.txt" >&2
	echo "  marker), otherwise runs earlGrey via Docker and syncs results to" >&2
	echo "  S3. A failed genome is logged and skipped — it does not stop the" >&2
	echo "  queue, so one bad genome can't halt a multi-week unattended run." >&2
	echo "  Dfam is cached once into /root/dfam-cache (host-mounted) and" >&2
	echo "  reused for every genome on this box, not re-downloaded per run." >&2
	echo "  threads defaults to 4 — sized for 64GB RAM at ~12GB/thread with" >&2
	echo "  headroom, since a single RepeatModeler worker has been observed" >&2
	echo "  spiking to ~60GB RSS by itself; the setup script's swap file is" >&2
	echo "  the backstop if that headroom isn't enough." >&2
	echo "Example: $(basename "$0") earlgrey-insects:7.3.1 \\" >&2
	echo "    manifest-01.tsv s3://my-bucket/dfam_data s3://my-bucket/output" >&2
	exit 1
fi

image="$1"
manifest="$2"
dfam_uri="$3"
output_prefix="${4%/}"
threads="${5:-4}"

mkdir -p /root/dfam-cache
log="queue-$(basename "$manifest" .tsv).log"
echo "Starting queue from $manifest — logging to $log" | tee -a "$log"

total="$(wc -l <"$manifest" | tr -d ' ')"
n=0
while IFS=$'\t' read -r species genome_uri; do
	n=$((n + 1))
	if [ -z "$species" ]; then
		continue
	fi

	dest="${output_prefix}/${species}"
	if aws s3 ls "${dest}/${species}_EarlGrey/${species}_EarlGrey.log" >/dev/null 2>&1 \
		&& ! aws s3 ls "${dest}/INCOMPLETE_RUN.txt" >/dev/null 2>&1; then
		echo "[$n/$total] $species — already completed, skipping" | tee -a "$log"
		continue
	fi

	echo "[$n/$total] $species — starting $(date -u +%FT%TZ)" | tee -a "$log"
	if docker run --rm \
		-v ~/.aws:/root/.aws:ro \
		-v /root/dfam-cache:/opt/conda/envs/earlgrey/share/famdb-3.0.0/Libraries/famdb \
		-e DFAM_S3_URI="$dfam_uri" \
		"$image" -g "$genome_uri" -s "$species" -o "$dest" -t "$threads" >>"$log" 2>&1; then
		echo "[$n/$total] $species — SUCCEEDED $(date -u +%FT%TZ)" | tee -a "$log"
	else
		echo "[$n/$total] $species — FAILED $(date -u +%FT%TZ), see $log for details" | tee -a "$log"
	fi
done <"$manifest"

echo "Queue finished: $total genomes processed. See $log for the full run history." | tee -a "$log"

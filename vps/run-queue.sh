#!/usr/bin/env bash
set -euo pipefail

print_usage() {
	echo "Usage: $(basename "$0") [manifest-slice.tsv] [options]" >&2
	echo "  Settings can come from --flags, a config file, or both (flags win" >&2
	echo "  over the config file for anything set in both):" >&2
	echo "    manifest-slice.tsv  The manifest to process. Required as a" >&2
	echo "                      positional arg or as MANIFEST in the config" >&2
	echo "                      file — a positional arg always wins." >&2
	echo "    --config <path>   Config file (default: ./run-queue.conf if it" >&2
	echo "                      exists — see vps/run-queue.conf.example)." >&2
	echo "    --image <image>   Docker image to run. Required (flag or config)." >&2
	echo "    --dfam <path>     Dfam path or s3:// URI. Required (flag or config)." >&2
	echo "    --output <path>   Output path or s3:// prefix. Required (flag or config)." >&2
	echo "    --threads <n>     Threads per job. Default: 4." >&2
	echo >&2
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
	echo "Example (config file supplies everything, MANIFEST included): $(basename "$0")" >&2
	echo "Example (all flags): $(basename "$0") manifest-01.tsv --image earlgrey-insects:latest \\" >&2
	echo "    --dfam /data/dfam_data --output /data/output --threads 4" >&2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	print_usage
	exit 1
fi

manifest=""
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
	manifest="$1"
	shift
fi

config=""
image=""
dfam=""
output_prefix=""
threads=""

while [ $# -gt 0 ]; do
	case "$1" in
	--config)
		config="$2"
		shift 2
		;;
	--image)
		image="$2"
		shift 2
		;;
	--dfam)
		dfam="$2"
		shift 2
		;;
	--output)
		output_prefix="$2"
		shift 2
		;;
	--threads)
		threads="$2"
		shift 2
		;;
	*)
		echo "Unknown option: $1" >&2
		print_usage
		exit 1
		;;
	esac
done

if [ -z "$config" ] && [ -f "./run-queue.conf" ]; then
	config="./run-queue.conf"
fi

if [ -n "$config" ]; then
	if [ ! -f "$config" ]; then
		echo "Config file not found: $config" >&2
		exit 1
	fi
	# Config sets MANIFEST/IMAGE/DFAM/OUTPUT/THREADS (distinct names from
	# this script's own manifest/image/dfam/output_prefix/threads) so a
	# --flag (or positional manifest) already set on the command line is
	# never clobbered by sourcing this file.
	# shellcheck disable=SC1090
	source "$config"
	if [ -z "$manifest" ]; then
		manifest="${MANIFEST:-}"
	fi
	if [ -z "$image" ]; then
		image="${IMAGE:-}"
	fi
	if [ -z "$dfam" ]; then
		dfam="${DFAM:-}"
	fi
	if [ -z "$output_prefix" ]; then
		output_prefix="${OUTPUT:-}"
	fi
	if [ -z "$threads" ]; then
		threads="${THREADS:-}"
	fi
fi

threads="${threads:-4}"

if [ -z "$manifest" ]; then
	echo "Missing manifest — supply it positionally or as MANIFEST in a config file (see --help)." >&2
	exit 1
fi
if [ -z "$image" ] || [ -z "$dfam" ] || [ -z "$output_prefix" ]; then
	echo "Missing --image/--dfam/--output — supply each via a flag or a config file (see --help)." >&2
	exit 1
fi

output_prefix="${output_prefix%/}"

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

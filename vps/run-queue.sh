#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run_earlgrey="$script_dir/../earlgrey/bin/run-earlgrey"

print_usage() {
	echo "Usage: $(basename "$0") [manifest-slice.tsv] [options]" >&2
	echo "  Iterates a manifest slice and runs ../earlgrey/bin/run-earlgrey for" >&2
	echo "  each '<species>\\t<genome-path>' line in it. This script only" >&2
	echo "  manages the manifest — Dfam/output/threads are configured on" >&2
	echo "  run-earlgrey's side (see ../earlgrey/bin/run-earlgrey.conf.example)," >&2
	echo "  not here." >&2
	echo "    manifest-slice.tsv       The manifest to process. Required as a" >&2
	echo "                             positional arg or as MANIFEST in this" >&2
	echo "                             script's config file — positional wins." >&2
	echo "    --config <path>          This script's config file (default:" >&2
	echo "                             ./run-queue.conf if it exists)." >&2
	echo "    --earlgrey-config <path> Passed through as run-earlgrey's" >&2
	echo "                             --config, if it's not at run-earlgrey's" >&2
	echo "                             own default lookup location." >&2
	echo >&2
	echo "  Resume-safe across restarts: run-earlgrey itself skips a species" >&2
	echo "  whose output already completed successfully. A failed genome is" >&2
	echo "  logged and the queue moves on — one bad genome can't halt a" >&2
	echo "  multi-week unattended run." >&2
	echo "Example (config file supplies everything, MANIFEST included): $(basename "$0")" >&2
	echo "Example: $(basename "$0") manifest-01.tsv" >&2
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
earlgrey_config=""

while [ $# -gt 0 ]; do
	case "$1" in
	--config)
		config="$2"
		shift 2
		;;
	--earlgrey-config)
		earlgrey_config="$2"
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
	# Config sets MANIFEST/EARLGREY_CONFIG (distinct names from this
	# script's own manifest/earlgrey_config) so a --flag (or positional
	# manifest) already set on the command line is never clobbered by
	# sourcing this file.
	# shellcheck disable=SC1090
	source "$config"
	if [ -z "$manifest" ]; then
		manifest="${MANIFEST:-}"
	fi
	if [ -z "$earlgrey_config" ]; then
		earlgrey_config="${EARLGREY_CONFIG:-}"
	fi
fi

if [ -z "$manifest" ]; then
	echo "Missing manifest — supply it positionally or as MANIFEST in a config file (see --help)." >&2
	exit 1
fi

earlgrey_args=()
if [ -n "$earlgrey_config" ]; then
	earlgrey_args+=(--config "$earlgrey_config")
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

	echo "[$n/$total] $species — starting $(date -u +%FT%TZ)" | tee -a "$log"
	if "$run_earlgrey" "$genome" "$species" "${earlgrey_args[@]}" >>"$log" 2>&1; then
		echo "[$n/$total] $species — done $(date -u +%FT%TZ)" | tee -a "$log"
	else
		echo "[$n/$total] $species — FAILED $(date -u +%FT%TZ), see $log for details" | tee -a "$log"
	fi
done <"$manifest"

echo "Queue finished: $total genomes processed. See $log for the full run history." | tee -a "$log"

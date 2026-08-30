#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
	echo "Usage: $(basename "$0") <output-csv> [interval-seconds]" >&2
	echo "  Samples host CPU/memory/swap/load every interval-seconds (default 1)" >&2
	echo "  and appends one CSV row per sample to <output-csv> until killed" >&2
	echo "  (SIGTERM/SIGINT) — runs forever otherwise, so it's meant to be" >&2
	echo "  started/stopped by something else around a single job, not run" >&2
	echo "  standalone in the foreground. bin/run-earlgrey does this" >&2
	echo "  automatically for its own run." >&2
	echo "  Host-level, not per-container: accurate for a box running one" >&2
	echo "  job at a time (the normal case here), but reflects combined" >&2
	echo "  usage if something else is also running on the box." >&2
	exit 1
fi

outfile="$1"
interval="${2:-1}"

echo "timestamp,cpu_pct,mem_used_mb,mem_total_mb,swap_used_mb,load1,load5,load15" >"$outfile"

# CPU% needs a delta between two /proc/stat reads — take a throwaway first
# read now so the first emitted row already reflects one real interval,
# rather than the meaningless since-boot average a single reading would give.
read -r _ user nice system idle iowait irq softirq steal _ </proc/stat
prev_idle="$idle"
prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))

while true; do
	sleep "$interval"

	read -r _ user nice system idle iowait irq softirq steal _ </proc/stat
	total=$((user + nice + system + idle + iowait + irq + softirq + steal))
	diff_idle=$((idle - prev_idle))
	diff_total=$((total - prev_total))
	cpu_pct=0
	if [ "$diff_total" -gt 0 ]; then
		cpu_pct=$(((1000 * (diff_total - diff_idle) / diff_total + 5) / 10))
	fi
	prev_idle="$idle"
	prev_total="$total"

	mem_total_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
	mem_avail_kb="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)"
	swap_total_kb="$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)"
	swap_free_kb="$(awk '/^SwapFree:/{print $2}' /proc/meminfo)"
	read -r load1 load5 load15 _ </proc/loadavg

	echo "$(date -u +%FT%TZ),$cpu_pct,$(((mem_total_kb - mem_avail_kb) / 1024)),$((mem_total_kb / 1024)),$(((swap_total_kb - swap_free_kb) / 1024)),$load1,$load5,$load15" >>"$outfile"
done

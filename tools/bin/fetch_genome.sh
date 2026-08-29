#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
	echo "Usage: $(basename "$0") <accession> [output relative to \$GENOMES_DIR, default raw_data/<accession>.fna]" >&2
	echo "Example: $(basename "$0") GCF_016746365.2" >&2
	exit 1
fi

accession="$1"
output="${2:-raw_data/${accession}.fna}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Runs inside the container: download the accession's genome zip via NCBI
# datasets, unzip it, and pull the .fna out to $output. $1/$2 (not expanded
# host-side) are the accession/output, passed in below as real argv so
# nothing needs escaping into the script text.
"$script_dir/run.sh" bash -c '
set -euo pipefail
accession="$1"
output="$2"
tmp="/genomes/.fetch-tmp-$accession"
mkdir -p "/genomes/$(dirname "$output")" "$tmp"
cd "$tmp"
datasets download genome accession "$accession" --include genome --filename genome.zip
unzip -q -o genome.zip
fna="$(find "ncbi_dataset/data/$accession" -name "*.fna" | head -n1)"
mv "$fna" "/genomes/$output"
cd /genomes
rm -rf "$tmp"
' _ "$accession" "$output"

echo "Wrote \$GENOMES_DIR/$output"

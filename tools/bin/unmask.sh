#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
	echo "Usage: $(basename "$0") <input relative to \$GENOMES_DIR> [output relative to \$GENOMES_DIR]" >&2
	echo "Example: $(basename "$0") raw_data/genome.fna  ->  raw_data/genome.unmasked.fna" >&2
	exit 1
fi

input="$1"
output="${2:-${input%.*}.unmasked.${input##*.}}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/run.sh" seqkit seq -u "/genomes/$input" -o "/genomes/$output"

echo "Wrote \$GENOMES_DIR/$output"

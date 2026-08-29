#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
	echo "Usage: $(basename "$0") <command> [args...]" >&2
	echo "Example: $(basename "$0") bedtools intersect -a /genomes/a.bed -b /genomes/b.bed" >&2
	exit 1
fi

# Resolve relative to this script so it works regardless of the caller's cwd.
cd "$(dirname "${BASH_SOURCE[0]}")/.."
docker compose --env-file ../.env run --rm tools "$@"

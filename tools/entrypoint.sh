#!/usr/bin/env bash
set -eo pipefail

# Activates the env and execs directly, instead of wrapping the command in
# `conda run` — conda run dumps the entire wrapped command to stderr with an
# "ERROR conda.cli.main_run" banner whenever it exits non-zero, even for an
# intentional non-zero exit (e.g. compare-fasta reporting a diff). exec here
# replaces this process, so the real exit code propagates cleanly instead.
source /opt/conda/etc/profile.d/conda.sh
conda activate bioinfo
exec "$@"

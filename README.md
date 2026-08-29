## Data sources

* Primary article: https://pmc.ncbi.nlm.nih.gov/articles/PMC12928591/
* All data: https://zenodo.org/records/18453526

## What's here

* [`earlgrey/`](earlgrey/README.md) — Earl Grey repeat-annotation pipeline image.
* [`tools/`](tools/README.md) — general genome toolbox image (`seqkit`, `bedtools`, `samtools`, NCBI `datasets`, etc.) plus `tools/bin/` shortcut scripts.

Each build is self-contained (`context: .`).

* `earlgrey` needs fixed `DFAM_DATA_DIR`/`GENOMES_DIR`/`OUTPUT_DIR` mounts, read from a `docker/earlgrey/.env` file (compose auto-loads it from that directory) — the pipeline's own `-g`/`-o` flags only understand container paths.
* `tools` has no fixed mounts or env vars at all — `tools/bin/` scripts take real host paths per invocation and mount only what's needed for that run.

See each subfolder's README for build/run instructions.

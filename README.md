## Data sources

* Primary article: https://pmc.ncbi.nlm.nih.gov/articles/PMC12928591/
* All data: https://zenodo.org/records/18453526

## What's here

* [`earlgrey/`](earlgrey/README.md) — Earl Grey repeat-annotation pipeline image.
* [`tools/`](tools/README.md) — general genome toolbox image (`seqkit`, `bedtools`, `samtools`, NCBI `datasets`, etc.) plus `tools/bin/` shortcut scripts.

Both compose files read the same variables (`DFAM_DATA_DIR`, `GENOMES_DIR`, `OUTPUT_DIR` — `tools` only needs the latter two), so one `.env` works for both. Keep it at `docker/.env` and pass `--env-file ../.env` when running `docker compose` from either subfolder:

```
docker/.env:
  DFAM_DATA_DIR=/data/bioinfo/data/dfam_data
  GENOMES_DIR=/data/bioinfo/data/genomes
  OUTPUT_DIR=/data/bioinfo/data/output
```

See each subfolder's README for build/run instructions.

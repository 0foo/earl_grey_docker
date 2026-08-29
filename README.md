## Data sources

* Primary article: https://pmc.ncbi.nlm.nih.gov/articles/PMC12928591/
* All data: https://zenodo.org/records/18453526

## What's here

* [`earlgrey/`](earlgrey/README.md) — Earl Grey repeat-annotation pipeline image.
* [`tools/`](tools/README.md) — general genome toolbox image (`seqkit`, `bedtools`, `samtools`, NCBI `datasets`, etc.) plus `tools/bin/` shortcut scripts.

Both compose files read `DFAM_DATA_DIR`, `GENOMES_DIR`, `OUTPUT_DIR` (`tools` only needs the latter two). Each build is self-contained (`context: .`), and each expects its own `.env` file next to its `docker-compose.yml` — `docker/earlgrey/.env` and `docker/tools/.env` — since `docker compose` auto-loads `.env` from the directory it runs in (or is `cd`'d into, as `tools/bin/*.sh` do):

```
docker/earlgrey/.env:
  DFAM_DATA_DIR=/data/bioinfo/data/dfam_data
  GENOMES_DIR=/data/bioinfo/data/genomes
  OUTPUT_DIR=/data/bioinfo/data/output

docker/tools/.env:
  GENOMES_DIR=/data/bioinfo/data/genomes
  OUTPUT_DIR=/data/bioinfo/data/output
```

See each subfolder's README for build/run instructions.

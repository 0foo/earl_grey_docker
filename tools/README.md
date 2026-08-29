## What's here

`bioinfo-tools` bundles `seqkit`, `seqtk`, `bedtools`, `samtools`, `bcftools`, `gffread`, and NCBI's `datasets`/`dataformat` CLI in one image, for one-off tasks (unmasking a genome, downloading from NCBI, interval math on annotations) that don't need the earlGrey pipeline.

* `Dockerfile` — builds `bioinfo-tools:latest`.
* `docker-compose.yml` — builds the image and mounts `GENOMES_DIR`/`OUTPUT_DIR` (no `DFAM_DATA_DIR` needed here).
* `bin/run.sh` — runs any command in the container.
* `bin/unmask.sh` — unmasks a genome FASTA with `seqkit seq -u` (built on `run.sh`).

## Prerequisites

* Docker with Compose.
* `GENOMES_DIR` and `OUTPUT_DIR` set — inline, in a `tools/.env` file, or in the shared `docker/.env` (see [../README.md](../README.md)) referenced with `--env-file`.

## Build & run

```
docker compose build
docker compose run --rm tools seqkit seq -u /genomes/raw_data/<genome>.fna > /genomes/raw_data/<genome>.unmasked.fna
```

Or drop into a shell with every tool on PATH:

```
docker compose run --rm tools bash
```

With a shared `docker/.env` instead of a local one:

```
docker compose --env-file ../.env run --rm tools bash
```

## `bin/` shortcuts

Skip the `docker compose --env-file ...` boilerplate with these (both assume `docker/.env` holds `GENOMES_DIR`/`OUTPUT_DIR`, and work from any cwd):

* `bin/run.sh <command> [args...]` — runs any command in the container.
  ```
  tools/bin/run.sh bedtools intersect -a /genomes/a.bed -b /genomes/b.bed
  ```
* `bin/unmask.sh <input> [output]` — unmasks a genome FASTA with `seqkit seq -u`. Paths are relative to `$GENOMES_DIR`; output defaults to `<input>.unmasked.<ext>`.
  ```
  tools/bin/unmask.sh raw_data/genome.fna
  # -> writes $GENOMES_DIR/raw_data/genome.unmasked.fna
  ```

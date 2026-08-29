## What's here

`bioinfo-tools` bundles `seqkit`, `seqtk`, `bedtools`, `samtools`, `bcftools`, `gffread`, and NCBI's `datasets`/`dataformat` CLI in one image, for one-off tasks (unmasking a genome, downloading from NCBI, interval math on annotations) that don't need the earlGrey pipeline.

* `Dockerfile` — builds `bioinfo-tools:latest`.
* `docker-compose.yml` — builds the image and mounts `GENOMES_DIR`/`OUTPUT_DIR` (no `DFAM_DATA_DIR` needed here).
* `bin/run-bio` — runs any command in the container.
* `bin/unmask-genome` — unmasks a genome FASTA with `seqkit seq -u` (built on `run-bio`).
* `bin/fetch-genome` — downloads a genome from NCBI by accession via `datasets` (built on `run-bio`).

## Prerequisites

* Docker with Compose.
* `GENOMES_DIR` and `OUTPUT_DIR` set — inline, or in a `tools/.env` file (compose auto-loads it from the project directory).

## Build & run

```
docker compose build
docker compose run --rm tools seqkit seq -u /genomes/raw_data/<genome>.fna > /genomes/raw_data/<genome>.unmasked.fna
```

Or drop into a shell with every tool on PATH:

```
docker compose run --rm tools bash
```

## `bin/` shortcuts

These wrap the `docker compose run` calls above and read `tools/.env` for `GENOMES_DIR`/`OUTPUT_DIR` (they `cd` into `tools/` first, so they work from any cwd):

* `bin/run-bio <command> [args...]` — runs any command in the container.
  ```
  tools/bin/run-bio bedtools intersect -a /genomes/a.bed -b /genomes/b.bed
  ```
* `bin/unmask-genome <input> [output]` — unmasks a genome FASTA with `seqkit seq -u`. Paths are relative to `$GENOMES_DIR`; output defaults to `<input>.unmasked.<ext>`.
  ```
  tools/bin/unmask-genome raw_data/genome.fna
  # -> writes $GENOMES_DIR/raw_data/genome.unmasked.fna
  ```
* `bin/fetch-genome <accession> [output]` — downloads a genome FASTA from NCBI. Output is relative to `$GENOMES_DIR`, defaults to `raw_data/<accession>.fna`.
  ```
  tools/bin/fetch-genome GCF_016746365.2
  # -> writes $GENOMES_DIR/raw_data/GCF_016746365.2.fna
  ```

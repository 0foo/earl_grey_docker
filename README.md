## Data sources

* Primary article: https://pmc.ncbi.nlm.nih.gov/articles/PMC12928591/
* All data: https://zenodo.org/records/18453526

## What's here

* `earlgrey.Dockerfile` — builds `earlgrey-insects:7.3.1` (Earl Grey 7.3.1 + Python 3.11 + awscli).
* `entrypoint.sh` — wraps `earlGrey` so `-g`/`-o` accept local paths or `s3://` URIs, for local + AWS Batch use.
* `tools.Dockerfile` — builds `bioinfo-tools:latest`, a general genome toolbox: `seqkit`, `seqtk`, `bedtools`, `samtools`, `bcftools`, `gffread`, `ncbi-datasets-cli` (`datasets`/`dataformat`), `awscli`.
* `docker-compose.yml` — local dev: builds both images and mounts `DFAM_DATA_DIR`/`GENOMES_DIR`/`OUTPUT_DIR` from the host (the `tools` service only needs `GENOMES_DIR`/`OUTPUT_DIR`).

Expected layout:

```
$GENOMES_DIR/
  raw_data/    # input genomes land here

$OUTPUT_DIR/   # earlGrey output — separate from $GENOMES_DIR
```

## Prerequisites

* Docker with Compose.
* A `DFAM_DATA_DIR` populated with the Dfam famdb files, a `GENOMES_DIR`, and an `OUTPUT_DIR` (see [Run locally](#run-locally)).
* An uncompressed genome FASTA under `$GENOMES_DIR/raw_data/` (local runs only — `earlGrey` won't unzip `.gz` itself; `s3://` inputs auto-unzip, see below).

## Build

```
docker compose build
```

## Run locally

```
docker compose run --rm earlgrey -g /genomes/raw_data/<genome>.fna -s <species> -o /output -t <threads>
```

`-g` is container-side, under `/genomes` (mapped to `$GENOMES_DIR`); `-o` is under `/output` (mapped to `$OUTPUT_DIR`) — a separate mount, so output doesn't land inside the genomes directory.

`DFAM_DATA_DIR`, `GENOMES_DIR`, and `OUTPUT_DIR` are required — compose refuses to run without them, no repo-relative fallback. Set them inline or in a `.env` file next to `docker-compose.yml`:

```
DFAM_DATA_DIR=/data/bioinfo/data/dfam_data \
GENOMES_DIR=/data/bioinfo/data/genomes \
OUTPUT_DIR=/data/bioinfo/data/output \
  docker compose run --rm earlgrey -g /genomes/raw_data/<genome>.fna -s <species> -o /output -t <threads>
```

**Note:** the container runs as root, so output is owned by `root`. Clean it up with a throwaway container instead of `sudo rm`:

```
docker run --rm -v /path/to/repo/data/output:/output busybox rm -rf /output
```

## Genome toolbox

`bioinfo-tools` bundles `seqkit`, `seqtk`, `bedtools`, `samtools`, `bcftools`, `gffread`, and NCBI's `datasets`/`dataformat` CLI in one image, for one-off tasks (unmasking a genome, downloading from NCBI, interval math on annotations) that don't need the earlGrey pipeline.

```
docker compose run --rm tools seqkit seq -u /genomes/raw_data/<genome>.fna > /genomes/raw_data/<genome>.unmasked.fna
```

Or drop into a shell with every tool on PATH:

```
docker compose run --rm tools bash
```

## Run on AWS Batch

Same image and entrypoint — pass `s3://` URIs instead of local paths:

```
-g s3://my-bucket/genomes/<genome>.fna.gz -s <species> -o s3://my-bucket/output/<species>
```

`-g` is downloaded and auto-unzipped if `.gz`; `-o` runs locally then syncs to S3 on completion. AWS credentials come from the Batch job's IAM role.

**Not yet done:**
* Getting `dfam_data` to the container on Batch — either bake it into the image with `COPY` (~35GB+, requires EC2 not Fargate) or mount via EFS.
* ECR repo, compute environment, job queue, job definition (no IaC written yet).

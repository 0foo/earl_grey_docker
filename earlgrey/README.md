## What's here

* `Dockerfile` — builds `earlgrey-insects:7.3.1` (Earl Grey 7.3.1 + Python 3.11 + awscli).
* `entrypoint.sh` — wraps `earlGrey` so `-g`/`-o` accept local paths or `s3://` URIs, for local + AWS Batch use.
* `docker-compose.yml` — builds the image. No fixed data mount — mounts are added per invocation (see below).
* `bin/run-earlgrey` — runs earlGrey from plain host paths (genome file, Dfam dir, output dir), no config needed.

## Prerequisites

* Docker with Compose.
* A local Dfam famdb directory, a genome FASTA, and an output directory (any paths — passed per run, not pre-configured).
* The genome can be `.gz` or already uncompressed — `bin/run-earlgrey` auto-`gunzip`s a `.gz` input before handing it to `earlGrey` (which doesn't unzip local paths itself; only the `s3://` path in the entrypoint auto-`gunzip`s — see below). Calling `docker compose run` directly without the script, the input must already be uncompressed.

## Build

```
docker compose build
```

## Run locally

```
bin/run-earlgrey <genome-file> <dfam-dir> <output-dir> <species> [threads]
```

All four/five arguments are real paths/values on your local filesystem — nothing needs to live at a fixed location, and there's no `.env` file. `run-earlgrey` mounts the genome's directory, the output directory, and the Dfam dir (at the fixed internal path earlGrey's conda env expects it) for just that run. A `.gz` genome is auto-decompressed into a temp file inside `<output-dir>`, cleaned up once the run finishes.

```
bin/run-earlgrey /data/bioinfo/data/genomes/2_unmasked_datasets/genome.fna.gz /data/bioinfo/data/dfam_data /data/bioinfo/data/output dmel 8
```

`threads` defaults to `4` if omitted.

Without the script, the equivalent manual command:

```
docker compose run --rm \
  -v /data/bioinfo/data/dfam_data:/opt/conda/envs/earlgrey/share/famdb-3.0.0/Libraries/famdb \
  -v /data/bioinfo/data/genomes:/data/bioinfo/data/genomes \
  -v /data/bioinfo/data/output:/data/bioinfo/data/output \
  earlgrey -g /data/bioinfo/data/genomes/raw_data/<genome>.fna -s <species> -o /data/bioinfo/data/output -t <threads>
```

**Note:** the container runs as root, so output is owned by `root`. Clean it up with a throwaway container instead of `sudo rm`:

```
docker run --rm -v /data/bioinfo/data/output:/data/bioinfo/data/output busybox rm -rf /data/bioinfo/data/output
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

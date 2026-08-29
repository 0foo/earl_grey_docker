## Data sources

### Primary article
* https://pmc.ncbi.nlm.nih.gov/articles/PMC12928591/

### All data gathered from here
* https://zenodo.org/records/18453526

## What's here

* `Dockerfile` — builds `earlgrey-insects:7.3.1`: Earl Grey 7.3.1 + Python 3.11 in a conda env (`earlgrey`), plus `awscli` in the base env.
* `entrypoint.sh` — wraps `earlGrey` so `-g` (genome) and `-o` (output dir) each accept either a local path or an `s3://` URI, so the same image runs locally and on AWS Batch.
* `docker-compose.yml` — local dev convenience: builds the image and bind-mounts data in from `../data`.

Expected host layout (repo root, i.e. the parent of `docker/`):

```
data/
  dfam_data/     # Dfam famdb library files (bind-mounted, not baked into the image yet)
  genomes/       # input genomes + earlGrey output land here
    raw_data/
```

## Prerequisites

* Docker with Compose (`docker compose ...`).
* `data/dfam_data` populated with the Dfam famdb files.
* A genome FASTA under `data/genomes/...`. **It must be uncompressed** — `earlGrey` reads the file directly and doesn't unzip `.gz` inputs on its own (the `s3://` path in the entrypoint *does* auto-`gunzip` after download — see below).

## Build

From the repo root (the parent of `docker/` and `data/`) — the build context has to be the repo root because `dfam_data`/`genomes` live outside `docker/` and Docker can't `COPY` from outside the build context:

```
docker compose build
```

or without Compose:

```
docker build -f docker/Dockerfile -t earlgrey-insects:7.3.1 .
```

## Run locally

Via Compose (recommended — mounts are already wired up):

```
docker compose run --rm earlgrey -g /data/raw_data/<genome>.fna -s <species> -o /data/output -t <threads>
```

Paths after `-g`/`-o` are container-side paths under `/data`, which maps to `data/genomes` on the host.

Without Compose:

```
docker run --rm -it \
  -v /path/to/repo/data/dfam_data:/opt/conda/envs/earlgrey/share/famdb-3.0.0/Libraries/famdb \
  -v /path/to/repo/data/genomes:/data \
  earlgrey-insects:7.3.1 -g /data/raw_data/<genome>.fna -s <species> -o /data/output -t <threads>
```

**Note:** the container runs as root, so output files land on your host owned by `root`. To inspect/delete them as yourself later, use a throwaway container rather than `rm`/`sudo`:

```
docker run --rm -v /path/to/repo/data/genomes:/data busybox rm -rf /data/output
```

## Run on AWS Batch

Same image, same entrypoint — just pass `s3://` URIs instead of local paths:

```
-g s3://my-bucket/genomes/<genome>.fna.gz -s <species> -o s3://my-bucket/output/<species>
```

* `-g` as an `s3://` URI is downloaded to the container before the run; if it ends in `.gz` it's automatically unzipped first.
* `-o` as an `s3://` URI runs earlGrey to a local temp dir, then `aws s3 sync`s the results up when the run finishes.
* AWS credentials come from the Batch job's IAM role — nothing to configure in the image itself.

**Not yet done:** `dfam_data` still has to reach the container somehow on Batch, since there's no host bind mount there. Options, still to be decided/set up:
* Bake it into the image with `COPY` (simplest, but makes the image ~35GB+ and requires EC2 launch type, not Fargate).
* Mount an EFS volume at the famdb path via the job definition.

Also not yet done: the ECR repo, compute environment, job queue, and job definition themselves (no CloudFormation/Terraform written yet).

## Switching `dfam_data` from bind mount to baked-in

Once things are working and you're ready to make the image self-contained (needed either way for AWS Batch unless you go the EFS route):

1. In `Dockerfile`, replace the `# Dfam data is bind-mounted...` comment with:
   ```
   COPY data/dfam_data /opt/conda/envs/earlgrey/share/famdb-3.0.0/Libraries/famdb
   ```
2. Remove the `dfam_data` line from `volumes:` in `docker-compose.yml`.
3. Rebuild.

## What's here

* `Dockerfile` — builds `earlgrey-insects:latest` (Earl Grey 7.3.1 + Python 3.11).
* `entrypoint.sh` — wraps `earlGrey`, flagging any run that didn't finish cleanly (crash, OOM-kill, interruption) with an `INCOMPLETE_RUN.txt` marker in the output dir.
* `docker-compose.yml` — builds the image. No fixed data mount — mounts are added per invocation (see below).
* `bin/run-earlgrey` — runs earlGrey from plain host paths (genome file, Dfam dir, output dir), skipping a species whose output already completed; dfam/output/threads can optionally come from a config file (`bin/run-earlgrey.conf.example`) instead of retyping them every run. [`../vps/run-queue.sh`](../vps/README.md) calls this once per genome to run a manifest slice.
* `bin/generate-manifest` — lists genome FASTAs under a local directory into a `<species>\t<genome-path>` manifest, consumed by [`../vps/`](../vps/README.md) to distribute genomes across multiple machines.
* `bin/monitor-resources.sh` — samples host CPU/memory/swap/load once a second; `run-earlgrey` starts/stops this automatically around its Docker run (see below), so it's not usually invoked directly.

## Prerequisites

* Docker with Compose.
* A local Dfam famdb directory, a genome FASTA, and an output directory (any paths — passed per run, not pre-configured).
* The genome can be `.gz` or already uncompressed — `bin/run-earlgrey` auto-`gunzip`s a `.gz` input before handing it to `earlGrey` (which doesn't unzip inputs itself). Calling `docker compose run` directly without the script, the input must already be uncompressed.

## Build

```
docker compose build
```

## Run locally

```
bin/run-earlgrey <genome-file> <species> [options]
```

`genome-file` and `species` are positional since they change on every run; `--dfam`/`--output`/`--threads` tend to stay the same across runs, so they can come from **flags, a config file, or both** — flags win over the config file for anything set in both:

```
# Config file once (copy the example, then edit):
cp bin/run-earlgrey.conf.example run-earlgrey.conf
$EDITOR run-earlgrey.conf   # set DFAM/OUTPUT/THREADS

bin/run-earlgrey /data/bioinfo/data/genomes/2_unmasked_datasets/genome.fna.gz dmel
```

Or skip the config file and pass everything as flags (also how to override just one setting from an otherwise-used config file, e.g. `--threads 8`):

```
bin/run-earlgrey /data/bioinfo/data/genomes/2_unmasked_datasets/genome.fna.gz dmel \
  --dfam /data/bioinfo/data/dfam_data --output /data/bioinfo/data/output --threads 8
```

`--config <path>` points at a specific config file instead of the default (`./run-earlgrey.conf` in the directory you run the script from, if it exists). `threads` defaults to `4` if not set by a flag or config.

All paths are real paths on your local filesystem — nothing needs to live at a fixed location. Each species gets its own subdirectory under `output-dir` (`<output-dir>/<species>/`, passed as `-o` to earlGrey) — not just for organization, but so the resume/`INCOMPLETE_RUN.txt` marker below is unambiguous even when many species share the same `output-dir` over time. `run-earlgrey` mounts the genome's directory, the output directory, and the Dfam dir (at the fixed internal path earlGrey's conda env expects it) for just that run.

Rerunning with the same `genome-file`/`species` is resume-safe: if `<output-dir>/<species>/<species>_EarlGrey/<species>_EarlGrey.log` already exists with no `<output-dir>/<species>/INCOMPLETE_RUN.txt` next to it (the marker `entrypoint.sh` writes on any non-zero exit), `run-earlgrey` skips the Docker run entirely and exits successfully. This is what lets `../vps/run-queue.sh` restart a whole manifest slice after a crash/reboot without redoing already-finished genomes.

A `.gz` genome is auto-decompressed once into `<output-dir>/<species>/<species>.genome.fna` — a persistent, deterministic path, not a temp file — and reused as-is on a later rerun rather than regenerated. This is deliberate: earlGrey resumes a stopped run by checking which output files already exist, and its later stages end up referencing the genome path internally, so a rerun must see the *same* path or resume breaks (as it did when this used a randomly-named temp file deleted on exit). Clean up by deleting the whole `<output-dir>/<species>` directory, not this file alone.

`run-earlgrey` also writes `<output-dir>/<species>/resource-usage.csv` — one row every 10 seconds (`timestamp,cpu_pct,mem_used_mb,mem_total_mb,swap_used_mb,load1,load5,load15`) for just this run's duration, via `bin/monitor-resources.sh` started right before the Docker run and killed right after (success, failure, or interruption alike). It's host-level, not per-container — accurate as long as the box only runs one job at a time (the normal case for `run-queue.sh`), but would blend numbers from multiple jobs if you ever ran more than one concurrently on the same box. A retry on the same species overwrites this file with the new attempt's data rather than appending to the old one.

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

For running many genomes across multiple machines (not all on one box), see [`../vps/README.md`](../vps/README.md), which uses `bin/generate-manifest` to build the genome list from a local directory on each box.

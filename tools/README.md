## What's here

`bioinfo-tools` bundles `seqkit`, `seqtk`, `bedtools`, `samtools`, `bcftools`, `gffread`, and NCBI's `datasets`/`dataformat` CLI in one image, for one-off tasks (unmasking a genome, downloading from NCBI, interval math on annotations) that don't need the earlGrey pipeline.

* `Dockerfile` — builds `bioinfo-tools:latest`.
* `docker-compose.yml` — builds the image. No fixed data mount — mounts are added per invocation (see below).
* `bin/run-bio` — runs any command in the container.
* `bin/unmask-genome` — unmasks a genome FASTA with `seqkit seq -u` (built on `run-bio`).
* `bin/fetch-genome` — downloads a genome from NCBI by accession via `datasets` (built on `run-bio`).
* `bin/compare-fasta` — checks whether two FASTA files have the same sequences with `seqkit` (built on `run-bio`).
* `bin/report-mask` — reports hard-mask (`N`) and soft-mask (lowercase) extent in a genome FASTA (built on `run-bio`).
* `bin/batch-unmask` — runs `unmask-genome` over every file in a directory.
* `bin/check-fasta` — validates that a file is well-formed FASTA/FASTQ (built on `run-bio`).
* `bin/batch-check-fasta` — runs `check-fasta` over every file in a directory.
* `bin/batch-verify-ncbi` — for every file in a directory whose name contains an NCBI accession, fetches that assembly and compares sequences, logging results.

## Prerequisites

* Docker with Compose.

No environment variables or `.env` file needed — paths are passed per command.

## Build & run

```
docker compose build
docker compose run --rm -v /data/bioinfo/data/genomes:/data/bioinfo/data/genomes \
  tools seqkit seq -u /data/bioinfo/data/genomes/raw_data/<genome>.fna
```

Or drop into a shell with every tool on PATH:

```
docker compose run --rm tools bash
```

## `bin/` shortcuts

Prefer these over calling `docker compose run` directly — they take real host paths (absolute, or relative to your cwd) and figure out the right `-v` mounts for you, so nothing needs to live at a fixed location:

* `bin/run-bio <command> [args...]` — runs any command in the container. Every absolute host path found among the arguments is bind-mounted into the container at that exact same path (so tools see it unchanged).
  ```
  tools/bin/run-bio bedtools intersect -a /data/bioinfo/data/genomes/a.bed -b /data/bioinfo/data/output/b.bed
  ```
* `bin/unmask-genome <input.fna> [output.fna]` — unmasks a genome FASTA with `seqkit seq -u`. Output defaults to `<input>.unmasked.<ext>` next to the input.
  ```
  tools/bin/unmask-genome /data/bioinfo/data/genomes/raw_data/genome.fna
  # -> writes /data/bioinfo/data/genomes/raw_data/genome.unmasked.fna
  ```
* `bin/fetch-genome <accession> [output.fna]` — downloads a genome FASTA from NCBI. Output defaults to `./<accession>.fna` in your current directory.
  ```
  tools/bin/fetch-genome GCF_016746365.2 /data/bioinfo/data/genomes/raw_data/GCF_016746365.2.fna
  ```
* `bin/compare-fasta <file1.fna> <file2.fna>` — checks whether two FASTAs have the same sequences, ignoring headers, line-wrap, and record order. Prints a hash per file and `MATCH`/`DIFFER`; exits `0` on match, `1` on differ (scriptable).
  ```
  tools/bin/compare-fasta genome_a.fna genome_b.fna
  ```
* `bin/report-mask <genome.fna>` — reports hard-mask (`N`) and soft-mask (lowercase) extent: total length, `N` base count/percentage/run count, and lowercase base count/percentage. Hard-masked `N`s are unrecoverable (the original base was deleted when masked) — this only tells you how much of the genome is affected, it doesn't undo it. Soft-masking *is* recoverable — see `unmask-genome`.
  ```
  tools/bin/report-mask genome.fna
  ```
* `bin/batch-unmask <input-dir> <output-dir>` — runs `unmask-genome` on every file in `<input-dir>`, writing same-named files into `<output-dir>` (created if missing). A failure on one file is logged and skipped, not fatal to the batch; prints a success/failure summary at the end and exits `1` if anything failed. A failed conversion can leave a 0-byte stub at the output path — worth checking for (`find <output-dir> -type f -empty`) and removing before re-running.
  ```
  tools/bin/batch-unmask /data/bioinfo/data/genomes/1_masked_datasets/genomes_dhakad /data/bioinfo/data/genomes/2_unmasked_datasets
  ```
* `bin/check-fasta <file>` — validates the file parses as FASTA/FASTQ (`seqkit seq`, which fails hard on malformed input — unlike `seqkit stats`, which logs an error but still exits `0`). Prints `seqkit stats -a` on success. Exits `0`/`1`.
  ```
  tools/bin/check-fasta genome.fna.gz
  ```
* `bin/batch-check-fasta <dir>` — runs `check-fasta` over every file in `<dir>`; a failure is logged and skipped, not fatal. Prints a summary and exits `1` if anything was invalid.
  ```
  tools/bin/batch-check-fasta /data/bioinfo/data/genomes/1_masked_datasets/genomes_dhakad
  ```
* `bin/batch-verify-ncbi <dir> [log-file]` — for every file in `<dir>` whose name contains an NCBI assembly accession (`GCF_`/`GCA_#########.#`), fetches that assembly from NCBI, unmasks both the fetched copy and the local file, and runs `compare-fasta` between them — so it verifies "same genome regardless of masking," not byte-identity. Files without a recognizable accession in the name (e.g. `*.nanopore.*`) are skipped. A fetch failure or a real sequence difference is logged per-file and does not stop the batch; downloaded copies are discarded after each comparison. Writes one tab-separated line per processed file to `[log-file]` (default `./ncbi-verify.log`): `<name>  <accession>  MATCH|DIFFER|FETCH_FAILED`. Prints a console summary too, and exits `1` if anything differed or failed to fetch.
  ```
  tools/bin/batch-verify-ncbi /data/bioinfo/data/genomes/2_unmasked_datasets
  # -> logs to ./ncbi-verify.log

  tools/bin/batch-verify-ncbi /data/bioinfo/data/genomes/2_unmasked_datasets /data/bioinfo/data/genomes/ncbi-verify.log
  ```

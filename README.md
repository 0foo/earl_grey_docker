## Data sources

* Primary article: https://pmc.ncbi.nlm.nih.gov/articles/PMC12928591/
* All data: https://zenodo.org/records/18453526

## What's here

* [`earlgrey/`](earlgrey/README.md) — Earl Grey repeat-annotation pipeline image.
* [`tools/`](tools/README.md) — general genome toolbox image (`seqkit`, `bedtools`, `samtools`, NCBI `datasets`, etc.) plus `tools/bin/` shortcut scripts.
* [`infra/`](infra/README.md) — AWS Batch setup (CloudFormation) for running earlGrey across many genomes on EC2 Spot.

Each build is self-contained (`context: .`), and neither needs a `.env` file or fixed mounts — both `earlgrey/bin/run-earlgrey` and `tools/bin/` scripts take real host paths per invocation and mount only what's needed for that run.

See each subfolder's README for build/run instructions.

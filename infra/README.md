## AWS Batch setup for earlGrey

Runs the `earlgrey-insects` image (see [`../earlgrey/`](../earlgrey/README.md)) across 200 genomes on AWS Batch: EC2 Spot instances (diversified instance types, automatic retry on interruption), Dfam cached once per host from S3 (no EFS, no baking it into the image), and genomes processed in whatever batch sizes you choose rather than all 200 at once.

**Assumes one S3 bucket** holding genomes, the Dfam database, and output (in separate prefixes) — matches "a list of 200 genomes, the dfam database, and an output folder all in S3." The IAM job role is scoped to that single bucket.

Prerequisites: AWS CLI configured with credentials that can create IAM roles / VPC / Batch / ECR resources, and Docker to build the image.

### 1. Deploy the network stack

Minimal VPC: two public subnets (for Spot capacity diversity across AZs), an Internet Gateway (needed for ECR pulls), and a free S3 gateway endpoint (so genome/Dfam/output/manifest traffic never needs a NAT Gateway — this is the main cost lever kept off).

```
aws cloudformation deploy \
  --stack-name earlgrey-network \
  --template-file infra/cloudformation/network.yaml
```

**Check status** (`deploy` already blocks and prints progress, but if you ran it in the background, in another terminal, or it failed and you want to know why):

```
# current status (CREATE_IN_PROGRESS / CREATE_COMPLETE / ROLLBACK_COMPLETE / ...)
aws cloudformation describe-stacks --stack-name earlgrey-network \
  --query 'Stacks[0].StackStatus' --output text

# recent events, most useful when status is a *_FAILED or ROLLBACK_* state —
# find the row with a FAILED status and read its "ResourceStatusReason"
aws cloudformation describe-stack-events --stack-name earlgrey-network \
  --max-items 20 --query 'StackEvents[].[LogicalResourceId,ResourceStatus,ResourceStatusReason]' --output table

# or watch it live until it settles (blocks until complete or failed):
aws cloudformation wait stack-create-complete --stack-name earlgrey-network
```

Console alternative: CloudFormation → Stacks → `earlgrey-network` → **Events** tab shows the same history, and is often easier to scan for a failure than the CLI.

Grab its outputs — you'll pass them into the batch stack:

```
aws cloudformation describe-stacks --stack-name earlgrey-network \
  --query 'Stacks[0].Outputs'
```

### 2. Deploy the Batch stack

```
aws cloudformation deploy \
  --stack-name earlgrey-batch \
  --template-file infra/cloudformation/batch.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    VpcId=<VpcId from step 1> \
    SubnetIds=<PublicSubnetIds from step 1> \
    SecurityGroupId=<SecurityGroupId from step 1> \
    DataBucketName=<your-bucket-name>
```

**Check status** (same idea as step 1, swap the stack name):

```
aws cloudformation describe-stacks --stack-name earlgrey-batch \
  --query 'Stacks[0].StackStatus' --output text

aws cloudformation describe-stack-events --stack-name earlgrey-batch \
  --max-items 20 --query 'StackEvents[].[LogicalResourceId,ResourceStatus,ResourceStatusReason]' --output table

aws cloudformation wait stack-create-complete --stack-name earlgrey-batch
```

This stack takes longer than the network one (IAM roles, launch template, compute environment) — if it sits in `CREATE_IN_PROGRESS` for several minutes that's normal; a `ROLLBACK_IN_PROGRESS`/`ROLLBACK_COMPLETE` means something failed and rolled back, in which case `describe-stack-events` will show which resource and why (a common one: `DataBucketName` pointing at a bucket that doesn't exist, or `VpcId`/`SubnetIds`/`SecurityGroupId` copy-pasted wrong from step 1's outputs).

Defaults worth knowing (override with more `--parameter-overrides` if needed):

| Parameter | Default | Notes |
|---|---|---|
| `MaxvCpus` | 256 | Hard cap on total concurrent vCPUs — the real concurrency control, independent of how many jobs you submit. At `JobVcpus=10` this allows ~25 genomes running at once. |
| `JobVcpus` / `JobMemoryMiB` | 10 / 122880 (120GiB) | earlGrey's RepeatModeler/RepeatMasker stack runs ~10-12GB RAM per thread (sized here at 12GB/thread for headroom), so these stay paired at roughly a 1:12 ratio — bump both together (e.g. 16 / 196608) if a species needs more threads. |
| `InstanceTypes` | 8 memory-optimized types across r5/r5a/r6i/r6a | Memory-optimized only (8GiB/vCPU) — compute- or general-purpose families can't cover ~10-12GB/thread without OOM-killing RepeatModeler. Diversified across families/sizes to improve Spot availability. All are 16vCPU/128GiB or 32vCPU/256GiB, so the default job sizing (10 vCPU / 120GiB) fits any of them, one job per 4xlarge or up to two per 8xlarge. |
| `RootVolumeSizeGiB` | 350 | Needs room for the cached Dfam data (~35GB+), the decompressed genome, earlGrey/RepeatModeler scratch, and the swap file below. |
| `SwapSizeMiB` | 98304 (96GiB) | A swap file created on each instance at boot and granted to the container (`LinuxParameters.MaxSwap`, `Swappiness: 10`). Turns a memory overage into a slow-but-survives fallback instead of an instant OOM-kill that loses the whole multi-hour run — see the cost/tradeoff note below. |
| `ImageTag` | 7.3.1 | Must match the tag you push in step 3. |

Grab this stack's outputs too:

```
aws cloudformation describe-stacks --stack-name earlgrey-batch \
  --query 'Stacks[0].Outputs'
```

You'll get `EcrRepositoryUri`, `JobQueueName`, `JobDefinitionName`, `LogGroupName`.

### 3. Build and push the image

```
cd earlgrey
docker build -t <EcrRepositoryUri>:7.3.1 .
aws ecr get-login-password | docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com
docker push <EcrRepositoryUri>:7.3.1
```

### 4. Generate the genome manifest

```
earlgrey/bin/generate-manifest s3://<your-bucket>/genomes/ manifest.tsv
```

Review `manifest.tsv` — it's a plain `<species>\t<genome-s3-uri>` file, one line per genome. Species names are derived from filenames; fix any collisions or names you don't like before submitting (the warning printed by the script tells you if two files collapsed to the same species).

### 5. Run a pilot batch first

Validates the image, IAM permissions, Dfam caching, and manifest wiring before committing real spend — 3-5 genomes is enough:

```
earlgrey/bin/submit-batch manifest.tsv 1 5 \
  <JobQueueName> <JobDefinitionName> \
  s3://<your-bucket>/output s3://<your-bucket>/dfam_data
```

Check on it:

```
earlgrey/bin/batch-status <job-id-printed-above>
```

Once those 5 finish successfully and the output looks right in S3, move on.

### 6. Run the rest in batches

`submit-batch` doesn't submit anything AWS Batch wouldn't queue anyway — `MaxvCpus` already limits real concurrency regardless of how many jobs you submit. Batching here is about controlling blast radius (a bad config or a bad Spot day only affects one batch) and keeping monitoring manageable, not an API limit. **~20-25 genomes per batch** is a reasonable size for 200 total (about 8-10 batches):

```
earlgrey/bin/submit-batch manifest.tsv 6 25 \
  <JobQueueName> <JobDefinitionName> \
  s3://<your-bucket>/output s3://<your-bucket>/dfam_data

earlgrey/bin/submit-batch manifest.tsv 31 25 \
  <JobQueueName> <JobDefinitionName> \
  s3://<your-bucket>/output s3://<your-bucket>/dfam_data

# ... and so on through line 200
```

Adjust batch size freely — smaller if you want tighter control, larger once you trust the pipeline.

### Monitoring & troubleshooting

* `earlgrey/bin/batch-dashboard <JobQueueName> [log-group] [since]` — the one command for "show me everything": job counts by status on the queue, a per-array child breakdown for anything RUNNING/FAILED, and a recent CloudWatch log tail (default last 1h), all in one shot. Start here.
  ```
  earlgrey/bin/batch-dashboard earlgrey-queue
  earlgrey/bin/batch-dashboard earlgrey-queue /aws/batch/earlgrey 4h
  ```
* `earlgrey/bin/batch-status <job-id>` — status + per-child breakdown for a single job (a narrower version of the dashboard's per-job section, useful once you already know the job ID you care about).
* `earlgrey/bin/batch-failures <array-job-id> [retry-manifest.tsv]` — lists every failed child with its reason (OOM, Spot loss, or anything else) and writes a manifest of just those genomes, so a retry is one `submit-batch` call away instead of manually cross-referencing array indices against the manifest.
* AWS Batch console → Jobs, or `aws batch list-jobs --job-queue <JobQueueName>` — see everything queued/running/failed.
* Logs: CloudWatch Logs group `/aws/batch/earlgrey`, one stream per job attempt. Every manifest-mode job logs `Batch array index N: species=... genome=...` as its first line (before anything that could crash), so even a job that OOMs before earlGrey produces any output still identifies itself in its log stream.
* A job that fails with status reason matching `Host EC2*` was a Spot interruption — it auto-retries (up to 3 attempts total) with no action needed. A memory-related reason (e.g. "OutOfMemoryError...") means the job exceeded `JobMemoryMiB` **and** its swap allowance (`SwapSizeMiB`) — it does *not* auto-retry (retrying an OOM without changing anything would just fail again), so it needs either a resubmit at a smaller thread count or a bump to `JobMemoryMiB`/`SwapSizeMiB` for that genome. Any other reason means earlGrey itself failed — check its log stream.
* Swap is a safety net, not a free one: a job that's genuinely thrashing on swap runs slow rather than failing fast, and could occupy a Spot instance for hours before hitting the 12h `Timeout` instead of failing (and freeing that instance) quickly. If a genome routinely runs far longer than the rest of a batch, that's worth checking for swap thrashing rather than assuming it's just a big genome.
* First job on a fresh Spot instance takes longer (downloading + caching ~35GB of Dfam data); later jobs scheduled on the same instance skip that step. This is expected — see the `DFAM_S3_URI` handling in `earlgrey/entrypoint.sh`.
* earlGrey's memory use is driven by which repeat family a given thread is refining, not a fixed per-thread constant — a single RepeatModeler `Refiner` worker can spike far above average (observed ~60GB RSS on its own during local testing). `JobVcpus`/`JobMemoryMiB` are sized with that in mind (see the parameter table above); if a specific genome still OOMs, it likely has an unusually large repeat family (e.g. a satellite array) and may need a one-off resubmit at lower `THREADS`/higher `JobMemoryMiB` via `submit-batch`'s override, rather than raising the default for everything.

### Cost notes

* **No NAT Gateway, no EFS** — the two biggest avoidable recurring AWS Batch costs for this kind of pipeline. S3 traffic goes through the free gateway endpoint; ECR pulls and any other internet traffic go out through the Internet Gateway using each instance's public IP.
* **Spot** instances run well below On-Demand price (r5.4xlarge On-Demand is ~$1.01/hr; r5.8xlarge ~$1.84/hr, per AWS's public pricing), at the cost of occasional (historically <5% on average) interruption + automatic retry. Switch `ComputeResources.Type` in `batch.yaml` from `SPOT` to `EC2` (and drop `BidPercentage`/`SpotIamFleetRole`) if you need guaranteed no-interruption runs instead.
* `MinvCpus: 0` / `DesiredvCpus: 0` means the compute environment scales to zero and costs nothing when no jobs are queued.

### Tearing down

Neither template creates or manages an S3 bucket — `DataBucketName` is just a string parameter used to scope an IAM policy — so deleting both stacks never touches your genomes/Dfam/output data, regardless of order.

Two things to check first:

* **No active jobs.** `aws batch list-jobs --job-queue <JobQueueName> --job-status RUNNING` (and `RUNNABLE`) — cancel/wait these out first, or the job queue and compute environment can fail to disable/delete cleanly.
* **Empty the ECR repo.** `EmptyOnDelete` isn't set on it, so if you've pushed an image, deleting `earlgrey-batch` will fail on that one resource:
  ```
  aws ecr delete-repository --repository-name earlgrey-insects --force
  ```
  (safe to run before *or* after `delete-stack` — CloudFormation just skips a resource that's already gone).

Then delete in this order (batch stack's compute environment lives inside the network stack's VPC, so it has to go first):

```
aws cloudformation delete-stack --stack-name earlgrey-batch
aws cloudformation wait stack-delete-complete --stack-name earlgrey-batch

aws cloudformation delete-stack --stack-name earlgrey-network
aws cloudformation wait stack-delete-complete --stack-name earlgrey-network
```

If either lands in `DELETE_FAILED`, `aws cloudformation describe-stack-events --stack-name <name> --max-items 20` (same command from the status-check sections above) shows which resource blocked it — fix that (usually one of the two gotchas above) and re-run `delete-stack`; CloudFormation resumes and skips whatever already deleted successfully.

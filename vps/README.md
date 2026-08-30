## Running earlGrey on dedicated/VPS boxes instead of AWS Batch

An alternative to [`../infra/`](../infra/README.md)'s AWS Batch setup, for when the Spot/On-Demand cost doesn't fit the budget. Cheap 64GB-RAM dedicated servers (e.g. Hetzner's Server Auction) can run the same 200-genome workload for a fraction of the AWS cost — but with **none of Batch's automation**: no job queue, no auto-retry on interruption, no auto-scaling, no `batch-dashboard`. This directory is a much simpler, manual equivalent: each box works sequentially through its own fixed slice of the genome manifest.

Same image, same `entrypoint.sh`, unchanged — its `-g`/`-o` S3 handling and `DFAM_S3_URI` per-host caching already work outside Batch with no modification. The only new pieces here are the per-box setup and the work-queue loop.

### 1. Create an IAM user for these boxes

Batch's EC2 instances get S3/ECR access via an IAM role automatically; a box outside AWS needs an IAM **user** with an access key instead. Scope it narrowly — same permissions as the Batch job role, plus ECR pull:

```
aws iam create-user --user-name earlgrey-vps
aws iam put-user-policy --user-name earlgrey-vps --policy-name earlgrey-vps-access --policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect": "Allow", "Action": "s3:ListBucket", "Resource": "arn:aws:s3:::my-bioinfo-refdata-2026"},
    {"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject"], "Resource": "arn:aws:s3:::my-bioinfo-refdata-2026/*"},
    {"Effect": "Allow", "Action": ["ecr:GetAuthorizationToken"], "Resource": "*"},
    {"Effect": "Allow", "Action": ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], "Resource": "arn:aws:ecr:us-east-1:219647033290:repository/earlgrey-insects"}
  ]
}'
aws iam create-access-key --user-name earlgrey-vps
```

Save that access key/secret — you'll run `aws configure` with it on every box.

### 2. Partition the manifest

No runtime coordination between boxes — each one just gets a fixed, non-overlapping slice up front:

```
vps/partition-manifest manifest.tsv 5
# -> manifest-01.tsv .. manifest-05.tsv, one per box
```

### 3. Set up each box

Provision the box (e.g. a Hetzner Server Auction Ryzen 5 3600 / 64GB RAM / 2x2TB dedicated server), then per box:

```
scp manifest-0N.tsv vps/setup-box.sh vps/run-queue.sh root@<box-ip>:~
ssh root@<box-ip>

aws configure   # paste the earlgrey-vps access key/secret, set a default region
./setup-box.sh 219647033290.dkr.ecr.us-east-1.amazonaws.com/earlgrey-insects 7.3.1
```

`setup-box.sh` installs Docker if missing, creates a **96GiB swap file** (same OOM safety net as the AWS side — a single RepeatModeler worker has been observed spiking to ~60GB RSS by itself, and 2TB of disk makes this cheap insurance), and pulls the image from ECR.

### 4. Run the queue

This runs for days/weeks unattended — use `tmux`/`screen`/`nohup` so it survives your SSH session ending:

```
tmux new -s earlgrey
./run-queue.sh 219647033290.dkr.ecr.us-east-1.amazonaws.com/earlgrey-insects:7.3.1 \
  manifest-0N.tsv s3://my-bioinfo-refdata-2026/dfam_data s3://my-bioinfo-refdata-2026/output 4
# Ctrl-B D to detach; tmux attach -t earlgrey to check back in
```

`threads` (last arg, default 4) is sized for 64GB RAM at ~12GB/thread with headroom — see the box-sizing rationale in [`../infra/README.md`](../infra/README.md)'s parameter table. Adjust down if a box has less RAM, or up cautiously if you've confirmed headroom.

Dfam is downloaded once into `/root/dfam-cache` (host-mounted into every container run) and reused for every genome on that box — **not** re-downloaded per genome, which would otherwise mean 40+ redundant ~35GB downloads per box and real S3 egress cost (unlike AWS Batch, this transfer is a genuine cross-internet download from S3, not free intra-AWS traffic).

### 5. Monitor and handle failures

No `batch-dashboard` equivalent — check in manually:

```
tail -f queue-manifest-0N.log     # live progress on that box
aws s3 ls s3://my-bioinfo-refdata-2026/output/ --recursive | grep EarlGrey.log   # what's actually finished
```

A failed genome is logged and the queue moves on — it doesn't stop the box. Resume behavior is automatic and safe: rerunning `run-queue.sh` on the same manifest slice skips any species whose output already completed successfully (an `EarlGrey.log` exists in S3 with no `INCOMPLETE_RUN.txt` marker — the same marker `entrypoint.sh` writes on any non-zero exit) and retries anything that's missing or was left incomplete. So if a box reboots or the queue script dies, just restart it with the same command.

To go back and retry specifically the genomes that failed on a box, grep its log for `FAILED` and build a small manifest of just those lines, then rerun `run-queue.sh` against that instead of the full slice.

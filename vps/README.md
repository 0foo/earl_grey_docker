## Running earlGrey on dedicated/VPS boxes

Cheap 64GB-RAM dedicated servers (e.g. Hetzner's Server Auction) can run the 200-genome earlGrey workload for a fraction of what cloud compute costs, at the cost of doing the orchestration yourself: no managed job queue, no auto-retry, no auto-scaling, no dashboard. Each box just works sequentially through its own fixed slice of the genome manifest.

Same image, same `entrypoint.sh`, unchanged — its `-g`/`-o` S3 handling and `DFAM_S3_URI` per-host caching already work standalone with no modification (S3 remains the shared data store for genomes/Dfam/output regardless of where the compute runs). The only new pieces here are the per-box setup and the work-queue loop.

### 1. Create an IAM user for these boxes

These boxes aren't AWS-hosted, so there's no instance role to lean on — they need an IAM **user** with an access key instead, scoped to just S3 read/write on the data bucket (the image is built locally on each box from a git clone, so there's no ECR/container-registry permission needed at all):

```
aws iam create-user --user-name earlgrey-vps
aws iam put-user-policy --user-name earlgrey-vps --policy-name earlgrey-vps-access --policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect": "Allow", "Action": "s3:ListBucket", "Resource": "arn:aws:s3:::my-bioinfo-refdata-2026"},
    {"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject"], "Resource": "arn:aws:s3:::my-bioinfo-refdata-2026/*"}
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

Provision the box (e.g. a Hetzner Server Auction Ryzen 5 3600 / 64GB RAM / 2x2TB dedicated server), then per box — only the setup script and this box's manifest slice need copying over; everything else comes from the clone:

```
scp manifest-0N.tsv vps/setup-box.sh root@<box-ip>:~
ssh root@<box-ip>

TAILSCALE_AUTHKEY=tskey-... ./setup-box.sh git@0foo:0foo/earl_grey_docker.git 7.3.1
```

`setup-box.sh` installs Docker and git if missing, creates a **96GiB swap file** (same OOM safety net as the AWS side — a single RepeatModeler worker has been observed spiking to ~60GB RSS by itself, and 2TB of disk makes this cheap insurance), then clones (or pulls, if already cloned) the repo and builds the image locally — no AWS/ECR dependency for the image itself. If the repo URL is a private SSH remote, this box needs its own deploy key added to it, or your existing key copied over, before the clone will succeed.

If `TAILSCALE_AUTHKEY` is set, it also installs Tailscale and joins your tailnet non-interactively — no browser-click prompt, so this works unattended across all 5 boxes. Generate a **reusable** key (so the same one works for every box) at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys); omit the env var to skip Tailscale entirely, or run `tailscale up` manually later. Once joined, SSH into a box by its tailnet name/IP instead of its public one if you'd rather not expose SSH publicly.

### 4. Run the queue

This runs for days/weeks unattended — use `tmux`/`screen`/`nohup` so it survives your SSH session ending:

```
aws configure   # paste the earlgrey-vps access key/secret, set a default region

tmux new -s earlgrey
~/earl_grey_docker/vps/run-queue.sh earlgrey-insects:7.3.1 \
  manifest-0N.tsv s3://my-bioinfo-refdata-2026/dfam_data s3://my-bioinfo-refdata-2026/output 4
# Ctrl-B D to detach; tmux attach -t earlgrey to check back in
```

`threads` (last arg, default 4) is sized for 64GB RAM at ~12GB/thread with headroom: earlGrey's RepeatModeler/RepeatMasker stack runs ~10-12GB RAM per thread, and a single worker has been observed spiking to ~60GB RSS on its own — 4 threads leaves real margin against that on a 64GB box, backstopped by the swap file `setup-box.sh` creates. Adjust down if a box has less RAM, or up cautiously if you've confirmed headroom on yours.

Dfam is downloaded once into `/root/dfam-cache` (host-mounted into every container run) and reused for every genome on that box — **not** re-downloaded per genome, which would otherwise mean 40+ redundant ~35GB downloads per box and real S3 egress cost (unlike AWS Batch, this transfer is a genuine cross-internet download from S3, not free intra-AWS traffic).

### 5. Monitor and handle failures

No dashboard here — check in manually:

```
tail -f queue-manifest-0N.log     # live progress on that box
aws s3 ls s3://my-bioinfo-refdata-2026/output/ --recursive | grep EarlGrey.log   # what's actually finished
```

A failed genome is logged and the queue moves on — it doesn't stop the box. Resume behavior is automatic and safe: rerunning `run-queue.sh` on the same manifest slice skips any species whose output already completed successfully (an `EarlGrey.log` exists in S3 with no `INCOMPLETE_RUN.txt` marker — the same marker `entrypoint.sh` writes on any non-zero exit) and retries anything that's missing or was left incomplete. So if a box reboots or the queue script dies, just restart it with the same command.

To go back and retry specifically the genomes that failed on a box, grep its log for `FAILED` and build a small manifest of just those lines, then rerun `run-queue.sh` against that instead of the full slice.

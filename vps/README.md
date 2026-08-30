## Running earlGrey on dedicated/VPS boxes

Cheap 64GB-RAM dedicated servers (e.g. Hetzner's Server Auction) can run the 200-genome earlGrey workload for a fraction of what cloud compute costs, at the cost of doing the orchestration yourself: no managed job queue, no auto-retry, no auto-scaling, no dashboard. Each box just works sequentially through its own fixed slice of the genome manifest.

`run-queue.sh` here only manages that manifest: for each `<species>\t<genome-path>` line, it hands the genome and species off to [`../earlgrey/bin/run-earlgrey`](../earlgrey/README.md), which does the actual Docker run, resume-skip check, and `.gz` decompression. Dfam/output/threads are configured once on `run-earlgrey`'s side (see [`../earlgrey/bin/run-earlgrey.conf.example`](../earlgrey/bin/run-earlgrey.conf.example)) — `run-queue.sh` doesn't know about any of that, only the manifest. Both scripts work off local filesystem paths only, so if your genomes/Dfam data live in S3, sync them down to local disk on the box first (step 1 below).

### 1. Create an IAM user and sync data down locally

Skip this step entirely if your data is already on local disk (e.g. via a mounted volume) — nothing below needs AWS credentials in that case.

These boxes aren't AWS-hosted, so there's no instance role to lean on — they need an IAM **user** with an access key instead, scoped to just S3 read on the data bucket (the image is built locally on each box, so there's no ECR/container-registry permission needed at all):

```
aws iam create-user --user-name earlgrey-vps
aws iam put-user-policy --user-name earlgrey-vps --policy-name earlgrey-vps-access --policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect": "Allow", "Action": "s3:ListBucket", "Resource": "arn:aws:s3:::my-bioinfo-refdata-2026"},
    {"Effect": "Allow", "Action": "s3:GetObject", "Resource": "arn:aws:s3:::my-bioinfo-refdata-2026/*"}
  ]
}'
aws iam create-access-key --user-name earlgrey-vps
```

Save that access key/secret, then on each box:

```
aws configure   # paste the earlgrey-vps access key/secret, set a default region
aws s3 sync s3://my-bioinfo-refdata-2026/dfam_data /data/dfam_data
aws s3 sync s3://my-bioinfo-refdata-2026/genomes/2_unmasked_datasets /data/genomes/2_unmasked_datasets
```

`aws s3 sync` is resumable — if it's interrupted (dead connection, box reboot), just rerun the same command; it skips files that already match by size/mtime. If a sync did die mid-transfer, check for and delete any leftover partial-write temp files before rerunning (their names won't match the source manifest, so `sync` won't clean them up on its own).

### 2. Partition the manifest

No runtime coordination between boxes — each one just gets a fixed, non-overlapping slice up front. Build `manifest.tsv` from wherever your genomes actually are — `bin/generate-manifest` accepts either an `s3://` prefix or a local directory, but since `run-earlgrey` only handles local paths, point it at the **local, synced-down** directory from step 1:

```
earlgrey/bin/generate-manifest /data/genomes/2_unmasked_datasets manifest.tsv

vps/partition-manifest manifest.tsv 5
# -> manifest-01.tsv .. manifest-05.tsv, one per box
```

### 3. Set up each box

Provision the box, clone this repo onto it, then per box copy over just this box's manifest slice:

```
scp manifest-0N.tsv root@<box-ip>:~
ssh root@<box-ip>

~/earl_grey_docker/vps/setup-box.sh
tailscale up   # follow the printed login URL to approve this box in a browser
```

`setup-box.sh` installs Docker, Tailscale, and the AWS CLI if missing (needed for the one-time data sync in step 1, not by the queue itself), creates a **96GiB swap file** (same OOM safety net as the AWS side — a single RepeatModeler worker has been observed spiking to ~60GB RSS by itself, and 2TB of disk makes this cheap insurance), and builds the image locally as `earlgrey-insects:latest` from `../earlgrey` relative to the script — no path or tag to pass, no AWS/ECR dependency for the image itself. `tailscale up` is a separate manual step since it's interactive (no auth key involved) — once joined, SSH into the box by its tailnet name/IP instead of its public one if you'd rather not expose SSH publicly.

### 4. Run the queue

This runs for days/weeks unattended — use `tmux`/`screen`/`nohup` so it survives your SSH session ending. Configure both scripts' config files once per box, then just run `run-queue.sh`:

```
# run-earlgrey's config: where Dfam/output/threads live (shared by every genome this box runs)
cp earlgrey/bin/run-earlgrey.conf.example earlgrey/bin/run-earlgrey.conf
$EDITOR earlgrey/bin/run-earlgrey.conf   # set DFAM/OUTPUT/THREADS to this box's local paths

# run-queue's config: just this box's manifest slice
cp vps/run-queue.conf.example run-queue.conf
$EDITOR run-queue.conf   # set MANIFEST=manifest-0N.tsv

tmux new -s earlgrey
~/earl_grey_docker/vps/run-queue.sh
# Ctrl-B D to detach; tmux attach -t earlgrey to check back in
```

Or skip the config files and pass the manifest positionally / point at a non-default `run-earlgrey.conf`:

```
~/earl_grey_docker/vps/run-queue.sh manifest-0N.tsv --earlgrey-config /path/to/run-earlgrey.conf
```

`threads` (in `run-earlgrey.conf`, default 4) is sized for 64GB RAM at ~12GB/thread with headroom: earlGrey's RepeatModeler/RepeatMasker stack runs ~10-12GB RAM per thread, and a single worker has been observed spiking to ~60GB RSS on its own — 4 threads leaves real margin against that on a 64GB box, backstopped by the swap file `setup-box.sh` creates. Adjust down if a box has less RAM, or up cautiously if you've confirmed headroom on yours.

### 5. Monitor and handle failures

Check in manually:

```
tail -f queue-manifest-0N.log        # live progress on that box
find /data/output -name '*_EarlGrey.log'   # what's actually finished
cat /data/output/<species>/resource-usage.csv   # that species' own CPU/mem/swap/load history
```

A failed genome is logged and the queue moves on — it doesn't stop the box. Resume behavior is automatic and safe: rerunning `run-queue.sh` on the same manifest slice re-invokes `run-earlgrey` per genome, which skips any species whose output already completed successfully (an `EarlGrey.log` exists with no `INCOMPLETE_RUN.txt` marker next to it — the same marker `entrypoint.sh` writes on any non-zero exit) and retries anything that's missing or was left incomplete. So if a box reboots or the queue script dies, just restart it with the same command.

To go back and retry specifically the genomes that failed on a box, grep its log for `FAILED` and build a small manifest of just those lines, then rerun `run-queue.sh` against that instead of the full slice.

### 6. Optional: live dashboard and file browser

`vps/monitoring/docker-compose.yml` runs two small containers, both reachable only from the tailnet (same reasoning as the SSH/firewall setup above — no extra firewall rule needed, since Tailscale traffic is decrypted internally and the Robot firewall never sees these as connections from outside the tailnet):

```
docker compose -f ~/earl_grey_docker/vps/monitoring/docker-compose.yml up -d
```

- **[Glances](https://nicolargo.github.io/glances/)** at `http://<tailscale-ip>:61208` — a live, mobile-friendly view of the box as a whole (and per-container stats while a job is running). Complements `resource-usage.csv` (above), which is per-genome history instead of a live view.
- **[File Browser](https://github.com/filebrowser/filebrowser)** at `http://<tailscale-ip>:8080` — browse/manage everything under `/data` (genomes, Dfam, output) from a phone or laptop without SSH. First login: `admin` / check `docker logs filebrowser` for the random password it generates on first startup (change it immediately in the UI). It has read-write access to `/data` by default — edit the compose file's `filebrowser` volume to add `:ro` if you only want browsing, not editing/deleting.

Reachable at `http://<tailscale-ip>:19999` from any device on your tailnet — nowhere else, since it binds the host's network interfaces (including `tailscale0`) and the Robot firewall discards any new inbound connection from the public internet (see the firewall setup above). No extra firewall rule needed, same reasoning as SSH: Tailscale traffic is decrypted internally, so the firewall never sees "a connection to port 19999" from outside the tailnet at all.

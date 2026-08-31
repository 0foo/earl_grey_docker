## Running earlGrey on dedicated/VPS boxes

Cheap 64GB-RAM dedicated servers (e.g. Hetzner's Server Auction) can run the 200-genome earlGrey workload for a fraction of what cloud compute costs, at the cost of doing the orchestration yourself: no managed job queue, no auto-retry, no auto-scaling, no dashboard. Each box just works sequentially through its own fixed slice of the genome manifest.

`run-queue.sh` here only manages that manifest: for each `<species>\t<genome-path>` line, it hands the genome and species off to [`../earlgrey/bin/run-earlgrey`](../earlgrey/README.md), which does the actual Docker run, resume-skip check, and `.gz` decompression. Dfam/output/threads are configured once on `run-earlgrey`'s side (see [`../earlgrey/bin/run-earlgrey.conf.example`](../earlgrey/bin/run-earlgrey.conf.example)) — `run-queue.sh` doesn't know about any of that, only the manifest. Both scripts work off local filesystem paths only — get your genomes/Dfam data onto each box's local disk yourself (scp/rsync/mounted volume/whatever fits) before running the queue.

### 1. Partition the manifest

No runtime coordination between boxes — each one just gets a fixed, non-overlapping slice up front. Build `manifest.tsv` from wherever your genomes live on local disk (point `bin/generate-manifest` at that directory):

```
earlgrey/bin/generate-manifest /data/genomes/2_unmasked_datasets manifest.tsv

vps/partition-manifest manifest.tsv 5
# -> manifest-01.tsv .. manifest-05.tsv, one per box
```

### 2. Set up each box

Provision the box, clone this repo onto it, then per box copy over just this box's manifest slice, along with the genome files that slice references and the Dfam data (whatever transfer method fits — `scp`/`rsync`/a mounted volume):

```
scp manifest-0N.tsv root@<box-ip>:~
rsync -avz /local/genomes/ root@<box-ip>:/data/genomes/
rsync -avz /local/dfam_data/ root@<box-ip>:/data/dfam_data/
ssh root@<box-ip>

~/earl_grey_docker/vps/setup-box.sh
tailscale up   # follow the printed login URL to approve this box in a browser
```

`setup-box.sh` installs Docker, Tailscale, and Ansible if missing, creates a **96GiB swap file** (a single RepeatModeler worker has been observed spiking to ~60GB RSS by itself, and 2TB of disk makes this cheap insurance), and builds the image locally as `earlgrey-insects:latest` from `../earlgrey` relative to the script — no path or tag to pass. `tailscale up` is a separate manual step since it's interactive (no auth key involved) — once joined, SSH into the box by its tailnet name/IP instead of its public one if you'd rather not expose SSH publicly.

### 3. Run the queue

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

### 4. Monitor and handle failures

Check in manually:

```
tail -f queue-manifest-0N.log        # live progress on that box
find /data/output -name '*_EarlGrey.log'   # what's actually finished
cat /data/output/<species>/resource-usage.csv   # that species' own CPU/mem/swap/load history
```

A failed genome is logged and the queue moves on — it doesn't stop the box. Resume behavior is automatic and safe: rerunning `run-queue.sh` on the same manifest slice re-invokes `run-earlgrey` per genome, which skips any species whose output already completed successfully (an `EarlGrey.log` exists with no `INCOMPLETE_RUN.txt` marker next to it — the same marker `entrypoint.sh` writes on any non-zero exit) and retries anything that's missing or was left incomplete. So if a box reboots or the queue script dies, just restart it with the same command.

To go back and retry specifically the genomes that failed on a box, grep its log for `FAILED` and build a small manifest of just those lines, then rerun `run-queue.sh` against that instead of the full slice.

### 5. Optional: live dashboard and file browser

See [`monitoring/README.md`](monitoring/README.md).

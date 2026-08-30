## What's here

Two optional containers for watching a box and its data over the tailnet — neither is required for `run-queue.sh`/`run-earlgrey` to work.

* **[Glances](https://nicolargo.github.io/glances/)** — live, mobile-friendly CPU/memory/disk/network dashboard for the box (and per-container stats while an earlGrey job is running).
* **[File Browser](https://github.com/filebrowser/filebrowser)** — web file manager over `/data` (genomes, Dfam, output), so you can browse/manage files from a phone or laptop without SSH.

## Start

```
docker compose up -d
```

No build step — both pull prebuilt images.

## Access

Both bind to the host directly and are reachable only from the tailnet (same as SSH — the Robot firewall discards new inbound connections from the public internet regardless of how Docker publishes the port):

| Service | URL |
| --- | --- |
| Glances | `http://<tailscale-ip>:61208` |
| File Browser | `http://<tailscale-ip>:8080` |

File Browser's first login is `admin` with a random password — check `docker logs filebrowser` for it, and change it immediately in the UI. It has read-write access to `/data` by default; add `:ro` to its volume mount in `docker-compose.yml` if you only want browsing.

#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	echo "Usage: $(basename "$0") [swap-size-gib]" >&2
	echo "  One-time setup for a dedicated/VPS box, run from within the" >&2
	echo "  cloned repo (as vps/setup-box.sh): installs Docker, Tailscale, and" >&2
	echo "  Ansible if missing, creates a swap file (default 96GiB — a single" >&2
	echo "  RepeatModeler worker has been observed spiking to ~60GB RSS by" >&2
	echo "  itself) if not already present, and builds the earlgrey image" >&2
	echo "  from ../earlgrey relative to this script, tagged 'latest'." >&2
	echo "  Run 'tailscale up' afterward — it prints a login URL to approve" >&2
	echo "  in a browser, joining this box to your tailnet." >&2
	echo "  Run as root (the default login on a freshly-installed Hetzner" >&2
	echo "  dedicated server)." >&2
	echo "Example: $(basename "$0")" >&2
	exit 1
fi

swap_gib="${1:-96}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
earlgrey_dir="$script_dir/../earlgrey"

if ! command -v docker >/dev/null 2>&1; then
	echo "Installing Docker..." >&2
	curl -fsSL https://get.docker.com | sh
fi

if ! command -v tailscale >/dev/null 2>&1; then
	echo "Installing Tailscale..." >&2
	curl -fsSL https://tailscale.com/install.sh | sh
fi

if ! command -v ansible >/dev/null 2>&1; then
	echo "Installing Ansible..." >&2
	apt-get update && apt-get install -y ansible
fi

if swapon --show | grep -q '/swapfile'; then
	echo "Swap already configured, skipping." >&2
else
	echo "Creating ${swap_gib}GiB swap file at /swapfile..." >&2
	fallocate -l "${swap_gib}G" /swapfile || dd if=/dev/zero of=/swapfile bs=1G count="$swap_gib"
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile
	echo '/swapfile none swap sw 0 0' >>/etc/fstab
	sysctl -w vm.swappiness=10
	echo "vm.swappiness=10" >>/etc/sysctl.conf
fi

echo "Building earlgrey-insects:latest from $earlgrey_dir (docker compose build)..." >&2
(cd "$earlgrey_dir" && docker compose build)

echo >&2
echo "Setup complete." >&2
echo "  Run 'tailscale up' to join your tailnet (prints a login URL to approve in a browser)." >&2
echo "  Copy genomes/Dfam data onto this box's local disk if you haven't (scp/rsync)." >&2
echo "  Configure $earlgrey_dir/bin/run-earlgrey.conf (dfam/output/threads) and" >&2
echo "  $script_dir/run-queue.conf (manifest slice), then run the work queue with:" >&2
echo "    $script_dir/run-queue.sh" >&2

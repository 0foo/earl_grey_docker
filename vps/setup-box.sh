#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
	echo "Usage: $(basename "$0") <repo-path> [image-tag] [swap-size-gib]" >&2
	echo "  One-time setup for a dedicated/VPS box, assuming the repo is" >&2
	echo "  already cloned at <repo-path>: installs Docker and Tailscale if" >&2
	echo "  missing, creates a swap file (default 96GiB — a single" >&2
	echo "  RepeatModeler worker has been observed spiking to ~60GB RSS by" >&2
	echo "  itself) if not already present, and builds the earlgrey image" >&2
	echo "  from <repo-path>/earlgrey." >&2
	echo "  Run 'tailscale up' afterward — it prints a login URL to approve" >&2
	echo "  in a browser, joining this box to your tailnet." >&2
	echo "  Run as root (the default login on a freshly-installed Hetzner" >&2
	echo "  dedicated server)." >&2
	echo "Example: $(basename "$0") ~/earl_grey_docker 7.3.1" >&2
	exit 1
fi

repo_path="$1"
image_tag="${2:-7.3.1}"
swap_gib="${3:-96}"

if ! command -v docker >/dev/null 2>&1; then
	echo "Installing Docker..." >&2
	curl -fsSL https://get.docker.com | sh
fi

if ! command -v tailscale >/dev/null 2>&1; then
	echo "Installing Tailscale..." >&2
	curl -fsSL https://tailscale.com/install.sh | sh
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

mkdir -p /root/dfam-cache

echo "Building earlgrey-insects:${image_tag} from ${repo_path}/earlgrey..." >&2
docker build -t "earlgrey-insects:${image_tag}" "${repo_path}/earlgrey"

echo >&2
echo "Setup complete." >&2
echo "  Run 'tailscale up' to join your tailnet (prints a login URL to approve in a browser)." >&2
echo "  Configure AWS credentials for S3 access (aws configure) if you haven't." >&2
echo "  Then run the work queue with:" >&2
echo "    ${repo_path}/vps/run-queue.sh earlgrey-insects:${image_tag} <manifest-slice.tsv> <dfam-s3-uri> <output-s3-prefix> [threads]" >&2

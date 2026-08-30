#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
	echo "Usage: $(basename "$0") <git-repo-url> [image-tag] [swap-size-gib]" >&2
	echo "  One-time setup for a dedicated/VPS box: installs Docker and git" >&2
	echo "  if missing, creates a swap file (default 96GiB — a single" >&2
	echo "  RepeatModeler worker has been observed spiking to ~60GB RSS by" >&2
	echo "  itself) if not already present, then clones (or pulls, if" >&2
	echo "  already cloned) the repo and builds the earlgrey image locally." >&2
	echo "  No AWS dependency for the image itself — only the AWS" >&2
	echo "  credentials 'run-queue.sh' needs later, for S3 (genomes/Dfam/" >&2
	echo "  output)." >&2
	echo "  Run as root (the default login on a freshly-installed Hetzner" >&2
	echo "  dedicated server). The repo URL needs to be one this box can" >&2
	echo "  actually clone — e.g. an SSH deploy key added to the repo, or" >&2
	echo "  your own key copied over, if it's a private SSH remote." >&2
	echo "  If TAILSCALE_AUTHKEY is set in the environment, also installs" >&2
	echo "  Tailscale and joins your tailnet non-interactively (a reusable" >&2
	echo "  auth key from https://login.tailscale.com/admin/settings/keys" >&2
	echo "  lets the same key join all your boxes). Skipped if unset." >&2
	echo "Example: $(basename "$0") git@0foo:0foo/earl_grey_docker.git 7.3.1" >&2
	echo "Example: TAILSCALE_AUTHKEY=tskey-... $(basename "$0") git@0foo:0foo/earl_grey_docker.git 7.3.1" >&2
	exit 1
fi

repo_url="$1"
image_tag="${2:-7.3.1}"
swap_gib="${3:-96}"

if ! command -v git >/dev/null 2>&1; then
	echo "Installing git..." >&2
	apt-get update && apt-get install -y --no-install-recommends git
fi

if ! command -v docker >/dev/null 2>&1; then
	echo "Installing Docker..." >&2
	curl -fsSL https://get.docker.com | sh
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

if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
	if ! command -v tailscale >/dev/null 2>&1; then
		echo "Installing Tailscale..." >&2
		curl -fsSL https://tailscale.com/install.sh | sh
	fi
	echo "Joining tailnet..." >&2
	tailscale up --authkey="$TAILSCALE_AUTHKEY"
else
	echo "TAILSCALE_AUTHKEY not set — skipping Tailscale setup (see usage, or run 'tailscale up' manually later)." >&2
fi

mkdir -p /root/dfam-cache

repo_dir="$HOME/$(basename "$repo_url" .git)"
if [ -d "$repo_dir/.git" ]; then
	echo "Repo already cloned at $repo_dir, pulling latest..." >&2
	git -C "$repo_dir" pull
else
	echo "Cloning $repo_url into $repo_dir..." >&2
	git clone "$repo_url" "$repo_dir"
fi

echo "Building earlgrey-insects:${image_tag} from $repo_dir/earlgrey..." >&2
docker build -t "earlgrey-insects:${image_tag}" "$repo_dir/earlgrey"

echo >&2
echo "Setup complete. Configure AWS credentials for S3 access (aws configure)" >&2
echo "if you haven't, then run the work queue with:" >&2
echo "  $repo_dir/vps/run-queue.sh earlgrey-insects:${image_tag} <manifest-slice.tsv> <dfam-s3-uri> <output-s3-prefix> [threads]" >&2

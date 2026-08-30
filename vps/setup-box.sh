#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
	echo "Usage: $(basename "$0") <ecr-repository-uri> [image-tag] [swap-size-gib]" >&2
	echo "  One-time setup for a dedicated/VPS box: installs Docker if" >&2
	echo "  missing, creates a swap file (default 96GiB, same OOM safety" >&2
	echo "  net used on the AWS Batch side — a single RepeatModeler worker" >&2
	echo "  has been observed spiking to ~60GB RSS by itself) if not already" >&2
	echo "  present, and pulls the earlgrey image from ECR." >&2
	echo "  Run as root (the default login on a freshly-installed Hetzner" >&2
	echo "  dedicated server). Requires AWS credentials already configured" >&2
	echo "  ('aws configure', including a default region) with ECR pull" >&2
	echo "  permission." >&2
	echo "Example: $(basename "$0") 219647033290.dkr.ecr.us-east-1.amazonaws.com/earlgrey-insects 7.3.1" >&2
	exit 1
fi

ecr_repo="$1"
image_tag="${2:-7.3.1}"
swap_gib="${3:-96}"

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

mkdir -p /root/dfam-cache

region="$(echo "$ecr_repo" | sed -E 's/.*\.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com.*/\1/')"
registry="$(echo "$ecr_repo" | cut -d/ -f1)"
echo "Logging into ECR ($registry, region $region) and pulling ${ecr_repo}:${image_tag}..." >&2
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
docker pull "${ecr_repo}:${image_tag}"

echo >&2
echo "Setup complete. Run the work queue with:" >&2
echo "  vps/run-queue.sh ${ecr_repo}:${image_tag} <manifest-slice.tsv> <dfam-s3-uri> <output-s3-prefix> [threads]" >&2

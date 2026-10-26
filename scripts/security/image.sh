#!/usr/bin/env bash
# Container image security:
#   1. Dockerfile misconfigurations (running as root, no healthcheck...)
#   2. CVEs in the OS packages and node_modules inside the built image
#   3. Secrets accidentally baked into image layers
#
# Usage:
#   scripts/security/image.sh                 build dev-secops:local and scan it
#   scripts/security/image.sh <image:tag>     scan an image that already exists
source "$(dirname "$0")/lib.sh"

image="${1:-}"
if [[ -z "$image" ]]; then
  image="dev-secops:local"
  echo "==> Building $image"
  docker build -t "$image" "$REPO_ROOT"
fi

echo "==> Dockerfile misconfigurations"
run_trivy config \
  --format json \
  --output "$REPORTS_DIR/dockerfile.json" \
  Dockerfile
trivy_report_and_gate "$REPORTS_DIR/dockerfile.json" "$REPORTS_DIR/dockerfile.sarif"

echo "==> Vulnerabilities and secrets in $image"
# The image is exported to a tar file and Trivy reads that file. This way
# the Trivy container does not need access to the Docker socket, which
# would give it full control of the host.
docker save "$image" -o "$REPO_ROOT/$REPORTS_DIR/image.tar"
run_trivy image \
  --input "$REPORTS_DIR/image.tar" \
  --scanners vuln,secret \
  --ignore-unfixed \
  --format json \
  --output "$REPORTS_DIR/image.json"
rm -f "$REPO_ROOT/$REPORTS_DIR/image.tar"
trivy_report_and_gate "$REPORTS_DIR/image.json" "$REPORTS_DIR/image.sarif"

#!/usr/bin/env bash
# SBOM (Software Bill of Materials): the full inventory of what is
# inside the image, every OS package and npm module with its version.
#
# Usage: scripts/security/sbom.sh [image:tag]     (default: dev-secops:local)
source "$(dirname "$0")/lib.sh"

image="${1:-dev-secops:local}"

echo "==> Generating SBOM for $image"
docker save "$image" -o "$REPO_ROOT/$REPORTS_DIR/image.tar"
# Two standard formats of the same inventory:
#   CycloneDX: security oriented (OWASP), what most scanners prefer
#   SPDX:      license/compliance oriented (Linux Foundation, ISO standard)
# The syft image has no writable /tmp for a non-root user: give it one.
run_tool --tmpfs /tmp:mode=1777 -e HOME=/tmp "$SYFT_IMAGE" scan \
  "docker-archive:$REPORTS_DIR/image.tar" \
  --quiet \
  --output "cyclonedx-json=$REPORTS_DIR/sbom.cdx.json" \
  --output "spdx-json=$REPORTS_DIR/sbom.spdx.json"
rm -f "$REPO_ROOT/$REPORTS_DIR/image.tar"

# syft can exit 0 even when it fails to read the image, so check the result.
if [[ ! -s "$REPO_ROOT/$REPORTS_DIR/sbom.cdx.json" ]]; then
  echo "SBOM generation failed: $REPORTS_DIR/sbom.cdx.json is empty" >&2
  exit 1
fi
# Count packages only; syft also lists every individual file.
packages="$(python3 -c 'import json, sys; print(sum(c["type"] != "file" for c in json.load(open(sys.argv[1]))["components"]))' "$REPO_ROOT/$REPORTS_DIR/sbom.cdx.json")"
echo "==> Packages found: $packages"

# The SBOM can be scanned without the image. Months after a release,
# when a new CVE comes out, this answers "are we affected?" in seconds.
echo "==> Scanning the SBOM for vulnerabilities"
run_trivy sbom \
  --ignore-unfixed \
  --format json \
  --output "$REPORTS_DIR/sbom-vulns.json" \
  "$REPORTS_DIR/sbom.cdx.json"
trivy_report_and_gate "$REPORTS_DIR/sbom-vulns.json" "$REPORTS_DIR/sbom-vulns.sarif"

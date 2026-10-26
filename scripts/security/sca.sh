#!/usr/bin/env bash
# Software Composition Analysis: known vulnerabilities (CVEs) in our
# dependencies, read from package-lock.json.
source "$(dirname "$0")/lib.sh"

# --include-dev-deps: dev dependencies never reach production, but they
#   run on your machine and in CI, where secrets live. They count too.
# --ignore-unfixed: if there is no patched version yet we cannot act on
#   it; those are tracked by Dependabot alerts instead of breaking CI.
run_trivy fs \
  --scanners vuln \
  --include-dev-deps \
  --ignore-unfixed \
  --format json \
  --output "$REPORTS_DIR/sca.json" \
  .

trivy_report_and_gate "$REPORTS_DIR/sca.json" "$REPORTS_DIR/sca.sarif"

#!/usr/bin/env bash
# Runs every static security check, in the same order as the CI pipeline.
# DAST is not included because it needs the running stack:
#   SWAGGER_ENABLED=true scripts/stack.sh up && scripts/security/dast.sh
#
# Usage: scripts/security/all.sh
set -uo pipefail
cd "$(dirname "$0")"

checks=(
  "workflows.sh"
  "secrets.sh history"
  "sca.sh"
  "sast.sh test"
  "sast.sh scan"
  "image.sh"
  "sbom.sh"
  "iac.sh"
)

failed=()
for check in "${checks[@]}"; do
  echo
  echo "################ $check ################"
  # shellcheck disable=SC2086 # split "sast.sh test" into script + argument
  ./$check || failed+=("$check")
done

echo
if ((${#failed[@]} > 0)); then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "All checks passed."

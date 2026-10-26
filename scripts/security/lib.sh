# Shared helpers for the security scripts. Sourced, not executed.

set -euo pipefail

# Repository root, no matter where the script is called from.
REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"

# shellcheck source=images.sh
source "$REPO_ROOT/scripts/security/images.sh"

# Runs a tool image with the repository mounted at /repo.
# It runs as your own user so generated reports are not owned by root.
run_tool() {
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$REPO_ROOT:/repo" \
    -w /repo \
    "$@"
}

# Reports (JSON, SARIF, SBOM...) are written here. Git-ignored.
REPORTS_DIR="reports"
mkdir -p "$REPO_ROOT/$REPORTS_DIR"

# Severities that break the build. Lower ones are reported, not blocking.
GATE_SEVERITY="HIGH,CRITICAL"

# Runs Trivy with a persistent cache, so the vulnerability database
# (~80 MB) is downloaded once instead of on every run.
TRIVY_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/trivy"
mkdir -p "$TRIVY_CACHE"
run_trivy() {
  run_tool -v "$TRIVY_CACHE:/cache" -e TRIVY_CACHE_DIR=/cache "$TRIVY_IMAGE" "$@"
}

# Turns a Trivy JSON report into:
#   - a SARIF file, uploaded by CI to GitHub's "Security" tab
#   - a table on the console, which fails if findings reach GATE_SEVERITY
trivy_report_and_gate() {
  local json="$1" sarif="$2"
  run_trivy convert --quiet --format sarif --output "$sarif" "$json"
  run_trivy convert --quiet --format table --severity "$GATE_SEVERITY" --exit-code 1 "$json"
}

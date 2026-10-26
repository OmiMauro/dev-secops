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

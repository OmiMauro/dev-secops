#!/usr/bin/env bash
# Secret scanning with gitleaks.
#
# Usage:
#   scripts/security/secrets.sh           scan the whole git history
#   scripts/security/secrets.sh staged    scan only staged changes (pre-commit)
source "$(dirname "$0")/lib.sh"

mode="${1:-history}"

case "$mode" in
  history)
    # Every commit ever made: a secret deleted in a later commit is
    # still in the history and still leaked.
    args=(git --no-banner --redact --verbose .)
    ;;
  staged)
    # Only what is about to be committed. Fast enough for a git hook.
    args=(git --no-banner --redact --verbose --pre-commit --staged .)
    ;;
  *)
    echo "Unknown mode: $mode (use 'history' or 'staged')" >&2
    exit 2
    ;;
esac

# In a git worktree, .git is a file pointing to the main repository's .git
# directory, which lives outside the mounted folder. Mount it too, at the
# same path, or git cannot read anything inside the container.
git_common_dir="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir)"
extra_mounts=()
if [[ "$git_common_dir" != "$REPO_ROOT/.git" ]]; then
  extra_mounts=(-v "$git_common_dir:$git_common_dir:ro")
fi

# Fail closed: when git fails inside the container, gitleaks logs an error,
# scans nothing and still says "no leaks found" with exit code 0. A scanner
# that cannot scan must fail, so any ERR line counts as a failure.
output="$(run_tool "${extra_mounts[@]}" "$GITLEAKS_IMAGE" "${args[@]}" 2>&1)" && status=0 || status=$?
echo "$output"
if grep -q ' ERR ' <<<"$output"; then
  echo "gitleaks reported an error: the scan is not trustworthy." >&2
  exit 1
fi
exit "$status"

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
    run_tool "$GITLEAKS_IMAGE" git --no-banner --redact --verbose .
    ;;
  staged)
    # Only what is about to be committed. Fast enough for a git hook.
    run_tool "$GITLEAKS_IMAGE" git --no-banner --redact --verbose --pre-commit --staged .
    ;;
  *)
    echo "Unknown mode: $mode (use 'history' or 'staged')" >&2
    exit 2
    ;;
esac

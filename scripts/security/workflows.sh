#!/usr/bin/env bash
# Security of the pipeline itself. A CI workflow holds secrets and can
# publish releases, so it is an attack target like any other code.
#   actionlint: syntax errors and mistakes in workflow files
#   zizmor:     security issues (script injection, excessive permissions,
#               unpinned actions, credentials left on disk...)
source "$(dirname "$0")/lib.sh"

echo "==> actionlint"
run_tool "$ACTIONLINT_IMAGE" -no-color

echo "==> zizmor"
# --offline: only checks that need no GitHub API token.
run_tool "$ZIZMOR_IMAGE" --offline .github/workflows

#!/usr/bin/env bash
# Static Application Security Testing with Semgrep: looks for dangerous
# patterns in OUR code (SQL injection, eval, weak crypto...) without
# running it.
#
# Usage:
#   scripts/security/sast.sh         scan src/ (fails on any finding)
#   scripts/security/sast.sh test    run the unit tests of our custom rules
source "$(dirname "$0")/lib.sh"

# Community rule packs from the Semgrep Registry + our own rules.
RULESETS=(
  --config p/typescript
  --config p/nodejs
  --config p/owasp-top-ten
  --config .semgrep/rules
)

run_semgrep() {
  # HOME=/tmp: semgrep writes a settings file in $HOME, and our user
  # has no home directory inside the container.
  run_tool -e HOME=/tmp "$SEMGREP_IMAGE" semgrep scan --metrics=off "$@"
}

mode="${1:-scan}"

case "$mode" in
  scan)
    # --error: exit code 1 if there is any finding (this is the gate).
    # --sarif-output: also write SARIF for GitHub's Security tab.
    run_semgrep \
      "${RULESETS[@]}" \
      --error \
      --sarif-output "$REPORTS_DIR/sast.sarif" \
      src
    ;;
  test)
    # Each rule has a .ts file next to it with "ruleid:" (must match)
    # and "ok:" (must not match) annotations.
    run_semgrep --test .semgrep/rules
    ;;
  *)
    echo "Unknown mode: $mode (use 'scan' or 'test')" >&2
    exit 2
    ;;
esac

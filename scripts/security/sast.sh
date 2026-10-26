#!/usr/bin/env bash
# Static Application Security Testing with Semgrep: looks for dangerous
# patterns in OUR code (SQL injection, eval, weak crypto...) without
# running it.
#
# Usage:
#   scripts/security/sast.sh               scan src/ (fails on any finding)
#   scripts/security/sast.sh test          run the unit tests of our custom rules
#   scripts/security/sast.sh update-lock   accept the current registry rule packs
source "$(dirname "$0")/lib.sh"

# Community rule packs from the Semgrep Registry. They are downloaded on
# every run, so their content is pinned by SHA-256 in .semgrep/registry.lock,
# the same idea as package-lock.json: if a pack changes upstream, the scan
# fails until someone reviews the change and updates the lock. Without it,
# the same code could pass today and fail tomorrow (or the other way round).
# The packs are not committed: the Semgrep Rules License does not allow
# redistributing them.
REGISTRY_PACKS=(typescript nodejs owasp-top-ten)
REGISTRY_LOCK="$REPO_ROOT/.semgrep/registry.lock"
REGISTRY_DIR="$REPORTS_DIR/semgrep-registry"

run_semgrep() {
  # HOME=/tmp: semgrep writes a settings file in $HOME, and our user
  # has no home directory inside the container.
  run_tool -e HOME=/tmp "$SEMGREP_IMAGE" \
    semgrep scan --metrics=off --disable-version-check "$@"
}

download_packs() {
  mkdir -p "$REPO_ROOT/$REGISTRY_DIR"
  for pack in "${REGISTRY_PACKS[@]}"; do
    curl -sfL "https://semgrep.dev/c/p/$pack" -o "$REPO_ROOT/$REGISTRY_DIR/$pack.yml"
  done
}

# Prints "<sha256>  <pack>" lines, the format of the lock file.
hash_packs() {
  (cd "$REPO_ROOT/$REGISTRY_DIR" && sha256sum "${REGISTRY_PACKS[@]/%/.yml}")
}

mode="${1:-scan}"

case "$mode" in
  scan)
    download_packs
    if ! diff <(hash_packs) "$REGISTRY_LOCK" >/dev/null; then
      echo "Semgrep registry rules changed upstream:" >&2
      diff <(hash_packs) "$REGISTRY_LOCK" >&2 || true
      echo "Review the new rules, then run: scripts/security/sast.sh update-lock" >&2
      exit 1
    fi

    configs=(--config .semgrep/rules)
    for pack in "${REGISTRY_PACKS[@]}"; do
      configs+=(--config "$REGISTRY_DIR/$pack.yml")
    done

    # --error: exit code 1 if there is any finding (this is the gate).
    # --sarif-output: also write SARIF for GitHub's Security tab.
    run_semgrep \
      "${configs[@]}" \
      --error \
      --sarif-output "$REPORTS_DIR/sast.sarif" \
      src
    ;;
  test)
    # Each rule has a .ts file next to it with "ruleid:" (must match)
    # and "ok:" (must not match) annotations.
    run_semgrep --test .semgrep/rules
    ;;
  update-lock)
    download_packs
    hash_packs > "$REGISTRY_LOCK"
    echo "Updated $REGISTRY_LOCK:"
    cat "$REGISTRY_LOCK"
    for pack in "${REGISTRY_PACKS[@]}"; do
      echo "  p/$pack: $(grep -c '^- id:' "$REPO_ROOT/$REGISTRY_DIR/$pack.yml") rules"
    done
    ;;
  *)
    echo "Unknown mode: $mode (use 'scan', 'test' or 'update-lock')" >&2
    exit 2
    ;;
esac

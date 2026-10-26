#!/usr/bin/env bash
# Infrastructure as Code security for the Terraform in terraform/:
#   1. terraform fmt + validate   is it well formed?
#   2. Checkov                    does it follow cloud security best practices?
#   3. Conftest (OPA/Rego)        does it follow OUR organization's rules?
#
# Usage: scripts/security/iac.sh [terraform-dir]    (default: terraform)
source "$(dirname "$0")/lib.sh"

dir="${1:-terraform}"

# Providers are cached between runs (the AWS provider is ~150 MB).
TF_PLUGIN_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/terraform-plugins"
mkdir -p "$TF_PLUGIN_CACHE"
terraform() {
  run_tool -w "/repo/$dir" \
    -e HOME=/tmp -e TF_PLUGIN_CACHE_DIR=/plugins -v "$TF_PLUGIN_CACHE:/plugins" \
    "$TERRAFORM_IMAGE" "$@"
}

echo "==> terraform fmt / validate"
terraform fmt -check -diff
# -backend=false: no remote state and no cloud credentials needed.
terraform init -backend=false -input=false >/dev/null
terraform validate

# Checkov and Conftest both run even if the first one fails, so you see
# every problem at once. The script fails at the end if any did.
failed=0

echo "==> Checkov"
# SARIF goes to reports/checkov.sarif for the Security tab.
run_tool "$CHECKOV_IMAGE" \
  --directory "$dir" \
  --framework terraform \
  --compact --quiet \
  --output cli --output sarif \
  --output-file-path "console,$REPORTS_DIR/checkov.sarif" \
  || failed=1

echo "==> Conftest: testing the policies themselves"
run_tool "$CONFTEST_IMAGE" verify --no-color --policy policy/terraform

echo "==> Conftest: applying the policies"
# Only *.tf files: the .terraform/ directory holds provider binaries.
tf_files=()
for file in "$REPO_ROOT/$dir"/*.tf; do
  tf_files+=("$dir/$(basename "$file")")
done
run_tool "$CONFTEST_IMAGE" test --no-color --parser hcl2 --policy policy/terraform "${tf_files[@]}" \
  || failed=1

exit "$failed"

#!/usr/bin/env bash
# Dynamic Application Security Testing with OWASP ZAP: attacks the
# RUNNING API over HTTP, like an outsider would.
#
# ZAP reads the OpenAPI spec to learn every endpoint and parameter, then:
#   - passive scan: inspects every response (headers, cookies, leaks)
#   - active scan:  sends attacks (SQL injection, XSS, path traversal...)
#
# Requires the stack running with Swagger enabled:
#   SWAGGER_ENABLED=true scripts/stack.sh up
#
# Usage: scripts/security/dast.sh
source "$(dirname "$0")/lib.sh"

API_URL="http://localhost:3000/api"
# ZAP joins the API's Docker network, where the API is reachable by its
# service name.
TARGET_IN_NETWORK="http://api:3000"

if ! curl -sf "$API_URL/docs-json" >/dev/null; then
  echo "No OpenAPI spec at $API_URL/docs-json." >&2
  echo "Start the stack with: SWAGGER_ENABLED=true scripts/stack.sh up" >&2
  exit 1
fi

api_container="$(docker compose --profile app ps -q api)"
network="$(docker inspect "$api_container" \
  --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{end}}')"

echo "==> Creating a scan user and logging in"
# Authenticated scan: without a token ZAP would only see 401 responses
# and could not test anything behind the login.
email="zap-$(date +%s)@scan.local"
password="$(openssl rand -hex 16)"
credentials="{\"email\":\"$email\",\"password\":\"$password\"}"
curl -sf -H 'Content-Type: application/json' -d "$credentials" "$API_URL/auth/register" >/dev/null
token="$(curl -sf -H 'Content-Type: application/json' -d "$credentials" "$API_URL/auth/login" \
  | sed 's/.*"accessToken":"\([^"]*\)".*/\1/')"

echo "==> Running the ZAP API scan (takes a few minutes)"
mkdir -p "$REPO_ROOT/$REPORTS_DIR/zap"
cp "$REPO_ROOT/.zap/rules.tsv" "$REPO_ROOT/$REPORTS_DIR/zap/rules.tsv"
# ZAP runs as its own "zap" user and must be able to write the reports.
chmod a+rwx "$REPO_ROOT/$REPORTS_DIR/zap"

# ZAP_AUTH_HEADER*: ZAP adds "Authorization: Bearer <token>" to every
#   request sent to the "api" host.
# -c rules.tsv: which alerts FAIL the scan, which only WARN, which are IGNOREd.
# -I: do not fail on WARN, only on FAIL.
docker run --rm \
  --network "$network" \
  -v "$REPO_ROOT/$REPORTS_DIR/zap:/zap/wrk" \
  -e ZAP_AUTH_HEADER=Authorization \
  -e ZAP_AUTH_HEADER_VALUE="Bearer $token" \
  -e ZAP_AUTH_HEADER_SITE=api \
  "$ZAP_IMAGE" zap-api-scan.py \
    -t "$TARGET_IN_NETWORK/api/docs-json" \
    -f openapi \
    -c rules.tsv \
    -I \
    -r report.html \
    -J report.json \
    -w report.md

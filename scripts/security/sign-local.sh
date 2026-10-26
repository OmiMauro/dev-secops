#!/usr/bin/env bash
# Local lab for image signing with Cosign, using a key pair.
# (CI uses keyless signing instead, see .github/workflows/ci.yml.)
#
# It starts a throwaway registry, then:
#   1. pushes the image and signs it by digest
#   2. attaches the SBOM as a signed attestation
#   3. verifies both
#   4. pushes a tampered image under the same tag and shows that
#      verification fails
#
# Usage: scripts/security/sign-local.sh   (run sbom.sh first)
source "$(dirname "$0")/lib.sh"

NETWORK="devsecops-lab"
REGISTRY_NAME="lab-registry"
KEY_DIR="$REPORTS_DIR/cosign"
# Demo only. A real key password lives in a secret manager, never in a script.
export COSIGN_PASSWORD="lab-password"

cleanup() {
  docker rm -f "$REGISTRY_NAME" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cosign() {
  run_tool -e HOME=/tmp -e COSIGN_PASSWORD --network "$NETWORK" "$COSIGN_IMAGE" "$@"
}

echo "==> Starting a local registry"
cleanup
docker network create "$NETWORK" >/dev/null
docker run -d --name "$REGISTRY_NAME" --network "$NETWORK" \
  -p 127.0.0.1:5000:5000 "$REGISTRY_IMAGE" >/dev/null
sleep 2

# From the host the registry is localhost:5000; from the cosign container
# (same Docker network) it is lab-registry:5000. Same registry, two names.
push_ref="localhost:5000/dev-secops:demo"
repo_in_network="$REGISTRY_NAME:5000/dev-secops"

echo "==> Generating a key pair in $KEY_DIR"
mkdir -p "$REPO_ROOT/$KEY_DIR"
rm -f "$REPO_ROOT/$KEY_DIR"/cosign.{key,pub}
cosign generate-key-pair --output-key-prefix "$KEY_DIR/cosign"

echo "==> Pushing dev-secops:local"
docker tag dev-secops:local "$push_ref"
docker push -q "$push_ref"
digest="$(docker image inspect "$push_ref" --format '{{index .RepoDigests 0}}' | cut -d@ -f2)"
signed_ref="$repo_in_network@$digest"

# Always sign the DIGEST, never a tag: a tag can be moved to another image.
# --tlog-upload=false: keeps this demo out of the public Rekor log.
LOCAL_ONLY=(--use-signing-config=false --tlog-upload=false --allow-http-registry)
VERIFY_LOCAL=(--insecure-ignore-tlog --allow-http-registry)

echo "==> 1. Signing $signed_ref"
cosign sign --yes --key "$KEY_DIR/cosign.key" "${LOCAL_ONLY[@]}" "$signed_ref"

echo "==> 2. Attaching the SBOM as a signed attestation"
cosign attest --yes --key "$KEY_DIR/cosign.key" "${LOCAL_ONLY[@]}" \
  --type cyclonedx --predicate "$REPORTS_DIR/sbom.cdx.json" "$signed_ref"

echo "==> 3. Verifying signature and attestation"
cosign verify --key "$KEY_DIR/cosign.pub" "${VERIFY_LOCAL[@]}" "$signed_ref" >/dev/null
echo "    signature: OK"
cosign verify-attestation --key "$KEY_DIR/cosign.pub" "${VERIFY_LOCAL[@]}" \
  --type cyclonedx "$signed_ref" >/dev/null
echo "    SBOM attestation: OK"

echo "==> 4. Tampering: pushing a different image under the same tag"
printf 'FROM dev-secops:local\nLABEL tampered=true\n' \
  | docker build -q -t "$push_ref" - >/dev/null
docker push -q "$push_ref"
if output="$(cosign verify --key "$KEY_DIR/cosign.pub" "${VERIFY_LOCAL[@]}" \
  "$repo_in_network:demo" 2>&1)"; then
  echo "    UNEXPECTED: the tampered image verified" >&2
  exit 1
fi
echo "    tampered image: REJECTED"
echo "    cosign says: $(grep -m1 '^Error' <<<"$output")"
docker image rm "$push_ref" >/dev/null

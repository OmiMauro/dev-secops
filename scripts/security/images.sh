# Pinned versions of every security tool used by the scripts.
# Each image is pinned by tag (readable) AND digest (immutable): if
# someone re-pushes a malicious image under the same tag, the digest
# no longer matches and Docker refuses to run it.
# This file is the single place to bump tool versions.

GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"
TRIVY_IMAGE="aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c"

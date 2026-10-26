# Step 6 — SBOM and signing (Syft, Cosign)

## The problem

Two questions every deployment should be able to answer:

1. **What is inside this image?** When the next Log4Shell-style CVE is
   announced, "are we affected?" should take seconds, not a week.
   → an **SBOM** (Software Bill of Materials).
2. **Is this the image our pipeline built?** A registry account can be
   compromised and a tag silently pointed to another image.
   → a **signature** tied to the image digest.

## What was added

| File | Purpose |
|------|---------|
| `scripts/security/sbom.sh` | Syft → SBOM in CycloneDX and SPDX, then Trivy scans the SBOM |
| `scripts/security/sign-local.sh` | Local lab: registry, key pair, sign, attest, verify, tamper |
| `ci.yml` → `release` job | On `main`: push to GHCR, SBOM, keyless signing, verification |

## SBOM

```bash
scripts/security/sbom.sh             # SBOM for dev-secops:local
```

```
==> Packages found: 266        (at step 6; the number grows with new dependencies)
==> Scanning the SBOM for vulnerabilities
```

It writes two formats of the same inventory to `reports/`:

| Format | File | Focus |
|--------|------|-------|
| CycloneDX | `sbom.cdx.json` | Security (OWASP). Preferred by scanners |
| SPDX | `sbom.spdx.json` | Licenses and compliance (ISO/IEC 5962) |

The 266 packages are 250 npm modules, 14 Debian packages, Node itself and
the OS. Look inside:

```bash
python3 -c "import json; [print(c['name'], c['version']) for c in json.load(open('reports/sbom.cdx.json'))['components'] if c['type'] != 'file']" | grep -E 'multer|nestjs/core|libssl'
```

```
@nestjs/core 11.2.8
libssl3t64 3.5.7-1~deb13u3
multer 2.5.0                ← the override from step 3, recorded
```

**Why scan an SBOM instead of the image?** The SBOM is a 750 KB JSON file
stored next to each release. Months later you can re-scan every release
you ever shipped without pulling a single image:

```bash
source scripts/security/lib.sh
run_trivy sbom reports/sbom.cdx.json
```

## Signing

### Keyless in CI (the real one)

The `release` job uses Sigstore **keyless** signing:

```
GitHub Actions ──OIDC token──▶ Fulcio (Sigstore CA)
  "I am ci.yml in                 issues a certificate valid ~10 min
   OmiMauro/dev-secops,           for that identity
   on refs/heads/main"                 │
                                       ▼
cosign signs the image digest ──▶ Rekor (public transparency log)
                                  records the signature forever
```

There is no private key anywhere: nothing to store as a secret, nothing
to rotate, nothing to leak. The identity is the **workflow** itself.

Verify a published image from your machine (no key needed):

```bash
IMAGE=ghcr.io/omimauro/dev-secops:develop     # or :sha-<commit>, :prod...
cosign verify "$IMAGE" \
  --certificate-identity https://github.com/OmiMauro/dev-secops/.github/workflows/ci.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Change the identity (for example `refs/heads/other-branch`) and it fails:
an image built from a branch, a fork or someone's laptop does not pass.

> GHCR may create the package as private. If `docker pull` asks you to
> log in, open the package in your GitHub profile → *Package settings* →
> *Change visibility*.

### With a key pair (local lab)

Keyless needs an OIDC identity, which your laptop does not have in a
script. The lab uses a classic key pair and a throwaway local registry:

```bash
scripts/security/sbom.sh          # the lab attaches this SBOM
scripts/security/sign-local.sh
```

```
==> 1. Signing lab-registry:5000/dev-secops@sha256:f3082c...
==> 2. Attaching the SBOM as a signed attestation
==> 3. Verifying signature and attestation
    signature: OK
    SBOM attestation: OK
==> 4. Tampering: pushing a different image under the same tag
    tampered image: REJECTED
    cosign says: Error: no signatures found
```

Step 4 is the attack this whole step exists for: same name, same tag,
different content. The signature belongs to the old digest, so the new
image has none.

The lab passes `--tlog-upload=false` so test signatures do not end up in
the public Rekor log. Real signatures should always go to the log: that
is what makes them auditable.

## Signature vs attestation

| | `cosign sign` | `cosign attest` |
|-|---------------|-----------------|
| Says | "this digest was approved by X" | "X states this fact about this digest" |
| Payload | the digest only | a document (SBOM, test results, scan report...) |
| Verify | `cosign verify` | `cosign verify-attestation --type cyclonedx` |

Here the SBOM is attached as an attestation: whoever pulls the image can
also fetch its signed inventory.

## Enforcing it

Signing only helps if something **refuses** unsigned images. In
Kubernetes that is an admission controller, such as Sigstore
policy-controller or Kyverno `verifyImages`. See the Kubernetes course.

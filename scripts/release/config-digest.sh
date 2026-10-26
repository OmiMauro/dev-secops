#!/usr/bin/env bash
# Prints the config digest ("sha256:...") of an image saved with `docker save`.
#
# The config digest identifies the image content and survives every
# hop: docker save/load, push, pull, retag. It is the fingerprint that
# proves the image published in the release job is the same one that was
# built and scanned earlier in the pipeline.
#
# Usage: scripts/release/config-digest.sh image.tar
set -euo pipefail

# manifest.json names the config file: "blobs/sha256/<hex>" (Docker 25+,
# OCI layout) or "<hex>.json" (older Docker). Either way the hex is the digest.
tar -xOf "$1" manifest.json | python3 -c '
import json, sys
config = json.load(sys.stdin)[0]["Config"]
print("sha256:" + config.rsplit("/", 1)[-1].removesuffix(".json"))
'

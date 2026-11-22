#!/usr/bin/env bash
# Smoke-test the built image without booting it. Run from this directory.
set -euo pipefail

IMAGE="${1:-localhost/ryoku-on-rakuos:test}"
echo "Testing image: ${IMAGE}"

podman run --rm \
    -v "$(pwd)/image-check.sh":/image-check.sh:ro \
    "${IMAGE}" /bin/bash /image-check.sh

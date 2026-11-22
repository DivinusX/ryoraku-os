#!/usr/bin/env bash
# Refresh RakuRyo OS from upstream and rebuild the image.
# Run this on the build machine (the one with podman and this repo checkout).
set -euo pipefail

cd "$(dirname "$0")"

BASE_REPO="quay.io/rakuos/rakuos-hyprland"
BASE_TAG="${BASE_TAG:-latest}"
IMAGE="localhost/ryoku-on-rakuos:test"
ARCHIVE="ryoraku-os.image.tar"
REF_FILE="build_files/RYOKU_REF"

echo "==> 1/5 Pulling latest RakuOS base (${BASE_REPO}:${BASE_TAG})"
podman pull "${BASE_REPO}:${BASE_TAG}"

echo "==> 2/5 Checking latest Ryoku release"
current_ref=$(tr -d '[:space:]' <"${REF_FILE}")
latest_ref=$(curl -fsSL https://api.github.com/repos/Ryoku-dev/ryoku/releases/latest \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' || true)

if [ -n "${latest_ref}" ] && [ "${latest_ref}" != "${current_ref}" ]; then
    printf '%s\n' "${latest_ref}" >"${REF_FILE}"
    echo "    Ryoku source ref bumped: ${current_ref} -> ${latest_ref}"
    echo "    (commit this change if you want the build to be reproducible)"
else
    echo "    Ryoku source ref already current: ${current_ref}"
fi

echo "==> 3/5 Building the chunkah layer"
podman build --security-opt label=disable \
    --build-arg BASE_IMAGE_TAG="${BASE_TAG}" \
    -v "$(pwd)":/run/src \
    -t localhost/ryoku-on-rakuos-chunkah:temp \
    --target chunkah .

echo "==> 4/5 Building the final bootc image"
podman build --security-opt label=disable \
    --build-arg BASE_IMAGE_TAG="${BASE_TAG}" \
    -v "$(pwd)":/run/src \
    -t "${IMAGE}" \
    --target final .

echo "==> 5/5 Exporting portable OCI archive"
podman save --format oci-archive -o "${ARCHIVE}" "${IMAGE}"
checksum=$(sha256sum "${ARCHIVE}" | awk '{print $1}')

echo
echo "============================================================"
echo " RakuRyo OS rebuilt successfully"
echo "============================================================"
echo " Image:      ${IMAGE}"
echo " Archive:    $(pwd)/${ARCHIVE} ($(du -h "${ARCHIVE}" | cut -f1))"
echo " SHA256:     ${checksum}"
echo
echo " Next steps ON THE LAPTOP:"
echo "   1. Copy ${ARCHIVE} and laptop-install.sh to the laptop"
echo "   2. ./laptop-install.sh ${ARCHIVE}"
echo "   3. sudo reboot  -> choose 'Ryoku (Hyprland)'"
echo "   4. rum update   -> refresh your own overlay packages"
echo "============================================================"

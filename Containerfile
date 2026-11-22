# Ryoku on RakuOS — personal derived image.
#
# Based on the rakuos-hyprland Containerfile. The difference: we start FROM a
# finished Hyprland image and only add the Ryoku layer, then let chunkah
# repack the result into bootc layers exactly as upstream does.
#
# Build:
#   podman build --security-opt label=disable --build-arg BASE_IMAGE_TAG=latest \
#     -t localhost/ryoku-on-rakuos:test --target final .

ARG BASE_IMAGE_REPO="quay.io/rakuos/rakuos-hyprland"
ARG BASE_IMAGE_TAG="latest"
ARG CHUNKAH_CONFIG_STR

# Build scripts are mounted into RUN steps, not copied into the final image.
FROM scratch AS ctx
COPY build_files /

FROM ${BASE_IMAGE_REPO}:${BASE_IMAGE_TAG} AS builder
ARG BASE_IMAGE_TAG
ENV BASE_IMAGE_TAG=${BASE_IMAGE_TAG}

# Key, repo file and any static system files land before the build script runs.
COPY system_files /

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    set -e; \
    /ctx/ryoku.sh; \
    /ctx/assign-components.sh generated; \
    /ctx/reset-mtimes.sh

COPY system_files /

# Clean up live build state and tag our own files as a stable chunkah component.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,source=system_files,target=/run/ryoku-system-files,ro \
    /ctx/assign-components.sh files ryoku-on-rakuos-files /run/ryoku-system-files; \
    find /run -mindepth 1 -maxdepth 1 ! -path /run/src -exec rm -rf {} + 2>/dev/null || true; \
    find /tmp -mindepth 1 -delete 2>/dev/null || true; \
    find /boot -mindepth 1 -delete 2>/dev/null || true; \
    /ctx/reset-mtimes.sh

# chunkah v0.7.1, pinned to the same digest as RakuOS: another version plans
# layers differently and would force a full re-download of the next update.
FROM quay.io/coreos/chunkah@sha256:71e593421c5de7dcc7c8c5c50e98d3bac572055a76f399f61a491d123c20a523 AS chunkah
ARG CHUNKAH_CONFIG_STR
RUN --mount=from=builder,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
        KREL=$(basename "$(dirname "$(ls /chunkah/usr/lib/modules/*/vmlinuz | head -1)")") && \
        [ -n "$KREL" ] && \
        chunkah build --prune /sysroot/ --max-layers 256 --threads 4 --compressed \
          --label ostree.commit- --label ostree.final-diffid- \
          --label "org.rakuos.kernel.release=${KREL}" \
          > /run/src/out.ociarchive

# Two-stage build: the final stage reads the archive written by chunkah.
FROM oci-archive:out.ociarchive AS final
LABEL containers.bootc=1

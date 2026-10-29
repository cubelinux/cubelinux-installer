#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_REF="${CUBELINUX_IMAGE_REF:-}"
COMMIT_REF="${GITHUB_SHA:-local}"
INSTALLER_REF="localhost/cubelinux-installer:local"
PAYLOAD_ARCHIVE="$ROOT/output/cubelinux-payload.oci.tar"

cleanup() {
    rm -f "$PAYLOAD_ARCHIVE"
    if [[ "${CUBELINUX_CI_PRUNE:-}" == "1" ]]; then
        podman system prune --all --force --volumes >/dev/null 2>&1 || true
    else
        podman image rm --force "$INSTALLER_REF" "$IMAGE_REF" >/dev/null 2>&1 || true
    fi
}

if [[ -z "$IMAGE_REF" ]]; then
    echo "Set CUBELINUX_IMAGE_REF to the published cubelinux image reference." >&2
    exit 2
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script with sudo so Podman and image-builder use the same root storage." >&2
    exit 2
fi

trap cleanup EXIT

cd "$ROOT"
mkdir -p output
rm -f "$ROOT"/output/cubelinux-installer-*.iso \
    "$ROOT"/output/cubelinux-installer-*.iso.sha256 \
    "$ROOT"/output/cubelinux-installer-build.txt \
    "$PAYLOAD_ARCHIVE"

podman pull "$IMAGE_REF"
skopeo copy "containers-storage:$IMAGE_REF" "oci-archive:$PAYLOAD_ARCHIVE:payload"
podman build \
    --build-arg "CUBELINUX_IMAGE_REF=$IMAGE_REF" \
    --tag "$INSTALLER_REF" \
    --file Containerfile \
    .

image-builder build \
    --output-dir "$ROOT/output" \
    --output-name "cubelinux-installer-${COMMIT_REF}" \
    --bootc-ref "$INSTALLER_REF" \
    --bootc-default-fs ext4 \
    bootc-generic-iso

ISO_PATH="$ROOT/output/cubelinux-installer-${COMMIT_REF}.iso"
if [[ ! -f "$ISO_PATH" ]]; then
    echo "image-builder completed without producing $ISO_PATH" >&2
    exit 1
fi

sha256sum "$ISO_PATH" > "$ISO_PATH.sha256"
printf 'commit=%s\nimage=%s\n' \
    "$COMMIT_REF" "$IMAGE_REF" > "$ROOT/output/cubelinux-installer-build.txt"
printf 'Built %s\n' "$ISO_PATH"

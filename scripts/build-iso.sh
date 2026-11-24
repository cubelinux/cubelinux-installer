#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_REF="${CUBELINUX_IMAGE_REF:-}"
FEDORA_MIRROR_ROOT="${FEDORA_MIRROR_ROOT:-https://eu.edge.kernel.org/fedora}"
REFRESH_IMAGE="${CUBELINUX_REFRESH_IMAGE:-0}"
COMMIT_REF="${GITHUB_SHA:-local}"
INSTALLER_REF="localhost/cubelinux-installer:local"
PAYLOAD_ARCHIVE="$ROOT/output/cubelinux-payload.oci.tar"
RECOVERY_APP_DIR="$ROOT/output/recovery-app"
RECOVERY_EXTRACT_CONTAINER=
PAYLOAD_SIZE_BYTES=0

cleanup() {
    if [[ -n "$RECOVERY_EXTRACT_CONTAINER" ]]; then
        podman rm --force "$RECOVERY_EXTRACT_CONTAINER" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$RECOVERY_APP_DIR"
    rm -f "$PAYLOAD_ARCHIVE"
    if [[ "${CUBELINUX_CI_PRUNE:-}" == "1" ]]; then
        podman system prune --all --force --volumes >/dev/null 2>&1 || true
    else
        podman image rm --force "$INSTALLER_REF" >/dev/null 2>&1 || true
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

if [[ "$REFRESH_IMAGE" == "1" ]] || ! podman image exists "$IMAGE_REF"; then
    podman pull "$IMAGE_REF"
else
    printf 'Using cached image %s (set CUBELINUX_REFRESH_IMAGE=1 to pull it again)\n' "$IMAGE_REF"
fi
rm -rf -- "$RECOVERY_APP_DIR"
mkdir -p "$RECOVERY_APP_DIR"
RECOVERY_EXTRACT_CONTAINER="$(podman create "$IMAGE_REF")"
if ! podman cp "$RECOVERY_EXTRACT_CONTAINER:/usr/lib/cubelinux-recovery/." "$RECOVERY_APP_DIR/"; then
    echo "The selected cubelinux image does not include recovery. Build the updated system image first and set CUBELINUX_IMAGE_REF to that image." >&2
    exit 1
fi
podman rm "$RECOVERY_EXTRACT_CONTAINER" >/dev/null
RECOVERY_EXTRACT_CONTAINER=
for file in qml/Main.qml qml/InstallerError.qml recovery-ui; do
    if [[ ! -s "$RECOVERY_APP_DIR/$file" ]]; then
        echo "The selected cubelinux image is missing recovery component file: $file" >&2
        exit 1
    fi
done
if [[ ! -x "$RECOVERY_APP_DIR/recovery-ui" ]]; then
    echo 'The recovery UI in the selected cubelinux image is not executable.' >&2
    exit 1
fi
for helper in install-bootc cleanup-installed-fstab verify-recovery-bundle check-recovery-layout factory-reset install-recovery-boot; do
    if [[ ! -s "$RECOVERY_APP_DIR/runtime/$helper" ]]; then
        echo "The selected cubelinux image is missing recovery runtime helper: $helper" >&2
        exit 1
    fi
done
skopeo copy "containers-storage:$IMAGE_REF" \
    "oci-archive:$PAYLOAD_ARCHIVE:localhost/cubelinux-offline:payload"
PAYLOAD_SIZE_BYTES="$(stat -c '%s' "$PAYLOAD_ARCHIVE")"
if [[ "${CUBELINUX_CI_PRUNE:-}" == "1" ]]; then
    # CI has no persistent image cache, so free the source layers before the
    # installer build competes for runner storage.
    podman image rm --force "$IMAGE_REF" >/dev/null
else
    printf 'Keeping %s in rootful Podman storage for the next build\n' "$IMAGE_REF"
fi
df -h /var/tmp /var/lib/containers "$ROOT/output"
podman build \
    --build-arg "CUBELINUX_IMAGE_REF=$IMAGE_REF" \
    --build-arg "FEDORA_MIRROR_ROOT=$FEDORA_MIRROR_ROOT" \
    --tag "$INSTALLER_REF" \
    --file Containerfile \
    .
rm -f "$PAYLOAD_ARCHIVE"
image-builder build \
    --output-dir "$ROOT/output" \
    --output-name "cubelinux-installer-${COMMIT_REF}" \
    --bootc-ref "$INSTALLER_REF" \
    --bootc-default-fs ext4 \
    bootc-generic-iso

ISO_NAME="cubelinux-installer-${COMMIT_REF}.iso"
ISO_PATH="$ROOT/output/$ISO_NAME"
if [[ ! -f "$ISO_PATH" ]]; then
    echo "image-builder completed without producing $ISO_PATH" >&2
    exit 1
fi
ISO_SIZE_BYTES="$(stat -c '%s' "$ISO_PATH")"

(
    cd "$ROOT/output"
    sha256sum "$ISO_NAME" > "$ISO_NAME.sha256"
)
printf 'commit=%s\nimage=%s\n' \
    "$COMMIT_REF" "$IMAGE_REF" > "$ROOT/output/cubelinux-installer-build.txt"
printf 'iso_size_bytes=%s\noffline_payload_size_bytes=%s\n' \
    "$ISO_SIZE_BYTES" "$PAYLOAD_SIZE_BYTES" \
    >> "$ROOT/output/cubelinux-installer-build.txt"
printf 'Built %s\n' "$ISO_PATH"

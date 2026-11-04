#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_REF="localhost/cubelinux-anaconda-gtk-smoke:local"
BUILD_ID="${GITHUB_SHA:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || printf 'local')}"
OUTPUT_NAME="cubelinux-anaconda-gtk-smoke-${BUILD_ID}"
OUTPUT_DIR="$ROOT/output"

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo; image-builder needs root privileges." >&2
    exit 2
fi

for command in podman image-builder sha256sum; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command not found: $command" >&2
        exit 2
    fi
done

mkdir -p "$OUTPUT_DIR"
podman build --tag "$IMAGE_REF" --file "$ROOT/Containerfile" "$ROOT"

{
    printf 'Built at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Installer interface: Anaconda GTK (anaconda-gui)\n'
    printf 'Source revision: %s\n' "$(git -c safe.directory="$ROOT" -C "$ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"
    printf 'Source changes:\n'
    git -c safe.directory="$ROOT" -C "$ROOT" status --short 2>/dev/null || true
    printf 'Smoke image ID: '
    podman image inspect --format '{{.Id}}' "$IMAGE_REF" || true
    printf 'Fedora base image ID: '
    podman image inspect --format '{{.Id}}' quay.io/fedora/fedora-bootc:44 || true
    printf 'image-builder version: '
    image-builder --version || true
} > "$OUTPUT_DIR/${OUTPUT_NAME}.build-info.txt" 2>&1

image-builder build \
    --output-dir "$OUTPUT_DIR" \
    --output-name "$OUTPUT_NAME" \
    --bootc-ref "$IMAGE_REF" \
    --bootc-default-fs ext4 \
    bootc-generic-iso

ISO_PATH="$OUTPUT_DIR/${OUTPUT_NAME}.iso"
if [[ ! -f "$ISO_PATH" ]]; then
    echo "image-builder did not produce $ISO_PATH" >&2
    exit 1
fi

sha256sum "$ISO_PATH" > "$ISO_PATH.sha256"
printf 'Built smoke-test ISO: %s\n' "$ISO_PATH"

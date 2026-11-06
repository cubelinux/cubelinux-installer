#!/usr/bin/env python3
"""Install Cubelinux branding into the live Anaconda environment."""

from __future__ import annotations

import glob
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.request import Request, urlopen


LOGO_URL = (
    "https://pub-eb590fbfc3074776ad4199c13b93d722.r2.dev/"
    "logo/primary-on-transparent.svg"
)
LOGO_PATH = Path("/usr/share/cubelinux/branding/primary-on-transparent.svg")


def download_logo() -> None:
    request = Request(LOGO_URL, headers={"User-Agent": "cubelinux-installer-build"})
    with urlopen(request, timeout=30) as response:
        logo = response.read(5_000_001)

    if b"<svg" not in logo[:4096] or len(logo) > 5_000_000:
        sys.exit("The Cubelinux logo URL did not return a valid SVG")

    LOGO_PATH.parent.mkdir(parents=True, exist_ok=True)
    LOGO_PATH.write_bytes(logo)


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as image:
        header = image.read(24)

    if (
        len(header) < 24
        or header[:8] != b"\x89PNG\r\n\x1a\n"
        or header[12:16] != b"IHDR"
    ):
        sys.exit(f"Cannot read PNG dimensions from {path}")

    return struct.unpack(">II", header[16:24])


def render_logo(target: Path) -> None:
    width, height = png_dimensions(target)
    with tempfile.NamedTemporaryFile(
        prefix=f".{target.name}.", suffix=".png", dir=target.parent, delete=False
    ) as temporary:
        temporary_path = Path(temporary.name)

    try:
        subprocess.run(
            [
                "/usr/bin/rsvg-convert",
                "--format=png",
                f"--width={width}",
                f"--height={height}",
                f"--output={temporary_path}",
                str(LOGO_PATH),
            ],
            check=True,
        )
        temporary_path.replace(target)
    finally:
        temporary_path.unlink(missing_ok=True)


def install_logo_artwork() -> None:
    # Render into the existing image dimensions to preserve Anaconda's layout.
    image_patterns = (
        "/usr/share/anaconda/pixmaps/anaconda_header.png",
        "/usr/share/anaconda/pixmaps/sidebar-logo.png",
        "/usr/share/anaconda/boot/splash.png",
        "/usr/share/anaconda/boot/syslinux-splash.png",
        "/usr/share/anaconda/pixmaps/splash.png",
        "/etc/favicon.png",
        "/usr/share/icons/hicolor/*/apps/fedora-logo-icon.png",
        "/usr/share/pixmaps/fedora-logo.png",
        "/usr/share/pixmaps/fedora-logo-small.png",
        "/usr/share/pixmaps/fedora_logo_med.png",
    )

    targets = sorted(
        {
            Path(path)
            for pattern in image_patterns
            for path in glob.glob(pattern)
            if Path(path).is_file()
        }
    )
    required = {
        Path("/usr/share/anaconda/pixmaps/anaconda_header.png"),
        Path("/usr/share/anaconda/pixmaps/sidebar-logo.png"),
    }
    if not required.issubset(targets):
        missing = ", ".join(str(path) for path in sorted(required - set(targets)))
        sys.exit(f"Anaconda branding images are missing: {missing}")

    for target in targets:
        render_logo(target)

    # Replace the scalable Fedora distribution mark without changing
    # Anaconda's own application icon or its desktop/application identifier.
    for path in (Path("/usr/share/icons/hicolor/scalable/apps/fedora-logo-icon.svg"),):
        if path.is_file():
            path.write_bytes(LOGO_PATH.read_bytes())


def set_installer_product_name() -> None:
    # Anaconda's liveinst launcher derives product name and version from this
    # file. Keep os-release untouched for Fedora platform behavior.
    system_release = Path("/etc/system-release")
    system_release.unlink(missing_ok=True)
    system_release.write_text("cubelinux release 1.0\n", encoding="utf-8")


def main() -> None:
    download_logo()
    install_logo_artwork()
    set_installer_product_name()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Install Cubelinux branding into the live Anaconda environment."""

from __future__ import annotations

import glob
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.request import Request, urlopen
from xml.etree import ElementTree


LOGO_BASE_URL = "https://pub-eb590fbfc3074776ad4199c13b93d722.r2.dev/logo/"
PRIMARY_LOGO_URL = f"{LOGO_BASE_URL}primary-on-transparent.svg"
SIDEBAR_LOGO_URL = f"{LOGO_BASE_URL}mono-for-dark-bg.svg"
SIDEBAR_LOGO_PNG_PATH = Path("/usr/share/cubelinux/branding/sidebar-logo.png")


def download_logo(destination: Path, url: str) -> None:
    request = Request(url, headers={"User-Agent": "cubelinux-installer-build"})
    with urlopen(request, timeout=30) as response:
        logo = response.read(5_000_001)

    if b"<svg" not in logo[:4096] or len(logo) > 5_000_000:
        sys.exit(f"The Cubelinux logo URL did not return a valid SVG: {url}")

    destination.write_bytes(logo)


def resolve_svg_colors(svg_path: Path) -> None:
    """Replace SVG custom-property fills with explicit colors for librsvg."""
    svg = svg_path.read_text(encoding="utf-8")
    try:
        root = ElementTree.fromstring(svg)
    except ElementTree.ParseError as error:
        sys.exit(f"The Cubelinux logo is not valid SVG: {error}")

    colors = {}
    for element in root.iter():
        for declaration in element.attrib.get("style", "").split(";"):
            name, separator, value = declaration.partition(":")
            name = name.strip()
            if separator and name.startswith("--"):
                colors[name] = value.strip()

    variable_pattern = re.compile(r"var\(\s*(--[\w-]+)\s*(?:,\s*([^)]*))?\)")

    def replace_variable(match: re.Match[str]) -> str:
        name, fallback = match.groups()
        color = colors.get(name) or (fallback.strip() if fallback else None)
        if not color:
            sys.exit(f"The Cubelinux logo uses an undefined SVG color: {name}")
        return color

    resolved = variable_pattern.sub(replace_variable, svg)
    if "var(" in resolved:
        sys.exit("The Cubelinux logo contains an unresolved SVG color")
    svg_path.write_text(resolved, encoding="utf-8")


def convert_sidebar_logo(svg_path: Path) -> None:
    """Rasterize the approved dark-background logo as a high-resolution PNG."""
    SIDEBAR_LOGO_PNG_PATH.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "/usr/bin/rsvg-convert",
            "--format=png",
            "--width=1024",
            f"--output={SIDEBAR_LOGO_PNG_PATH}",
            str(svg_path),
        ],
        check=True,
    )


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


def render_logo(svg_path: Path, target: Path) -> None:
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
                str(svg_path),
            ],
            check=True,
        )
        temporary_path.replace(target)
    finally:
        temporary_path.unlink(missing_ok=True)


def install_logo_artwork(svg_path: Path) -> None:
    # Use a 1024px transparent PNG for the sidebar, scaled by GTK CSS to fit.
    # Other legacy raster slots retain their expected canvas sizes, with the
    # full-color vector's aspect ratio preserved inside those PNG canvases.
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

    sidebar_logo = Path("/usr/share/anaconda/pixmaps/sidebar-logo.png")
    for target in targets:
        if target == sidebar_logo:
            target.write_bytes(SIDEBAR_LOGO_PNG_PATH.read_bytes())
        else:
            render_logo(svg_path, target)

    # The icon theme prefers scalable artwork; remove the Fedora version so it
    # falls back to the Cubelinux PNG sizes rendered above.
    Path("/usr/share/icons/hicolor/scalable/apps/fedora-logo-icon.svg").unlink(
        missing_ok=True
    )


def set_installer_product_name() -> None:
    # Anaconda reads its installer title from /.buildstamp. An empty version
    # gives the requested "Cubelinux Installation" heading; IsFinal remains
    # false so Anaconda keeps its accurate pre-release/testing indicator.
    Path("/.buildstamp").write_text(
        "[Main]\nProduct=Cubelinux\nVersion=\nIsFinal=False\n",
        encoding="utf-8",
    )

    # Keep the live system release label branded while leaving os-release
    # untouched for Fedora platform behavior.
    system_release = Path("/etc/system-release")
    system_release.unlink(missing_ok=True)
    system_release.write_text("cubelinux release 1.0\n", encoding="utf-8")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="cubelinux-branding-") as temporary_dir:
        primary_svg_path = Path(temporary_dir) / "primary-logo.svg"
        sidebar_svg_path = Path(temporary_dir) / "sidebar-logo.svg"
        download_logo(primary_svg_path, PRIMARY_LOGO_URL)
        resolve_svg_colors(primary_svg_path)
        download_logo(sidebar_svg_path, SIDEBAR_LOGO_URL)
        resolve_svg_colors(sidebar_svg_path)
        convert_sidebar_logo(sidebar_svg_path)
        install_logo_artwork(primary_svg_path)
    set_installer_product_name()


if __name__ == "__main__":
    main()

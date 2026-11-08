# cubelinux-installer

[![Build and publish installer ISO](https://github.com/cubelinux/cubelinux-installer/actions/workflows/build-and-publish-iso.yml/badge.svg)](https://github.com/cubelinux/cubelinux-installer/actions/workflows/build-and-publish-iso.yml)

Build the bootable cubelinux installer ISO as a project separate from the
cubelinux operating-system image. The ISO uses Fedora Anaconda's GTK interface
with Cubelinux branding. It embeds the selected cubelinux bootc image, lets the
user choose one target disk, and uses Anaconda's automatic partitioning on it.
Manual partitioning is hidden. It does not create a user;
the installed system should start Plasma Setup on first boot.

## Current status

The Anaconda GTK interface was confirmed to start in a Fedora 44 test image.
The production installer image and ISO still need a full build and end-to-end
test in a disposable virtual machine before release. Verify disk selection, that
the embedded image installs without network access, that account creation is
skipped, and that Plasma Setup starts after reboot.

The live installer uses Fedora's stable Fedora 44 bootc base. DNF installs
required package dependencies from the pinned `eu.edge.kernel.org` Fedora
mirror for Fedora 44 x86_64, rather than selecting another server through
Fedora MirrorManager. Fedora currently lists this HTTPS mirror for Fedora 44.
Set `FEDORA_MIRROR_ROOT` when running the build script to override the mirror
root. The selected mirror must carry both the Fedora release and updates repos;
the build will fail if that fixed mirror is unavailable. DNF skips optional
weak dependencies to keep the ISO smaller. During the container build, the
installer downloads the Cubelinux primary SVG and rasterizes it into a
transparent, 1024-pixel-wide PNG.
The GTK stylesheet scales the sidebar logo to fit. The installer product label
and stylesheet use Cubelinux branding; Fedora OS identity metadata remains
intact for platform behavior. The host workflow installs the current Fedora 44
`image-builder` package for each run.

## Build prerequisites

Use a Fedora 44 x86_64 build host with rootful Podman and `image-builder`
installed.
The build needs root privileges for image-builder's loop devices and mounts.
The cubelinux image must be published in a registry accessible to the builder.

Build using the exact image reference that the ISO should install:

```sh
sudo CUBELINUX_IMAGE_REF=ghcr.io/cubelinux/cubelinux:main bash ./scripts/build-iso.sh
```

The script reuses this image from rootful Podman's local store on later builds.
To refresh a mutable tag such as `:main`, set `CUBELINUX_REFRESH_IMAGE=1` for
that build:

```sh
sudo CUBELINUX_IMAGE_REF=ghcr.io/cubelinux/cubelinux:main CUBELINUX_REFRESH_IMAGE=1 bash ./scripts/build-iso.sh
```

The resulting ISO is written under `output/`. Image Builder embeds the source
image from Podman storage in the ISO's container storage, so installation does
not need to download the OS image. The installer skips bootc's update-origin
fetch check during deployment; the same registry reference is retained as the
installed system's update origin for later use.

During installation, Anaconda mounts the selected Btrfs filesystem's top-level
subvolume and binds a temporary directory from it over the live installer's
`/var/tmp`. Keeping this scratch directory outside the target root subvolume
prevents bootc from removing it while it initializes the installation. The
target disk needs free space for the temporary import in addition to the
installed system. The scratch directory is removed after a successful install.
The current offline installer requires a Btrfs target filesystem for this
disk-backed scratch path.

After bootc installs the system, a Kickstart `%post` step removes only the
root (`/`) entry that Anaconda writes to the installed `/etc/fstab`. The running
bootc root is a composefs overlay, so `systemd-remount-fs` cannot apply that
Btrfs entry to `/`; leaving it in place causes a failed-unit warning at login.
The `/boot`, `/boot/efi`, and `/home` entries remain unchanged.

While bootc is quiet during deployment, Anaconda refreshes the status message
with elapsed time. The current `bootc install to-filesystem` interface does not
provide machine-readable byte or layer progress, so the numeric progress does
not advance during image import.

## Project layout

```text
cubelinux-installer/
|-- config/
|   |-- anaconda.conf           # Hide the GTK account spoke
|   |-- cubelinux.css           # Cubelinux Anaconda colors and logo placement
|   |-- interactive-defaults.ks # Bootc install, scratch setup, and fstab cleanup
|   `-- iso.yaml                # ISO boot menu and media label
|-- .github/workflows/
|   `-- build-and-publish-iso.yml # Build on main pushes and upload to SourceForge
|-- scripts/
|   |-- build-iso.sh             # Build installer image and ISO
|   |-- install-anaconda-branding.py # Fetch and apply the logo during the image build
|   |-- patch-anaconda-single-disk.py # Restrict GTK disk selection to one target
|   `-- patch-anaconda-bootc-status.py # Refresh status during quiet bootc deployment
|-- .gitignore
|-- Containerfile                # Anaconda GTK installer environment
`-- README.md
```

The ISO is a release artifact, separate from the bootc image release. The
GitHub Actions workflow builds on every push to `main` and uploads a separate
ISO, checksum, and source commit record to the SourceForge File Release
System. The ISO filename contains the full Git commit hash, so each upload is
retained as its own file and uses additional SourceForge storage. The build
prunes container images and caches when finished, removes the Fedora builder
image before upload, and deletes the local ISO after a successful upload.

Configure these repository secrets before enabling uploads:

- `SOURCEFORGE_USER`: your SourceForge account name with release upload rights
- `SOURCEFORGE_SSH_KEY`: the private SSH key registered with that account
- `SOURCEFORGE_SSH_KEY_PASSPHRASE`: the passphrase for that private key

Set the `SOURCEFORGE_PROJECT` repository variable to the SourceForge project
URL slug. It defaults to `vibolvireak`.

Optionally set the `CUBELINUX_IMAGE_REF` repository variable to choose a
different published bootc image. For a private GHCR package, also configure
`GHCR_USERNAME` and `GHCR_TOKEN` secrets with pull access. The default is
`ghcr.io/cubelinux/cubelinux:main`.

## Important behavior

- The ISO is destructive to the selected target disk; make that clear in the
  installer flow and release notes.
- The GTK storage selector must allow only one selected install disk, and manual
  partitioning options must remain hidden.
- The installer must not collect or create user account information.
- Anaconda's GTK account spoke is hidden; verify this in the built installer.
- The selected cubelinux payload is embedded as an OCI archive in the ISO and
  installed from that local archive, while its registry reference remains the
  update origin for the installed system.
- Do not publish an ISO until the installed system has been confirmed to boot
  into the existing Plasma Setup account flow.

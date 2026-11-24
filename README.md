# cubelinux-installer

The project name is always written **cubelinux**, in lowercase.

[![Build and publish installer ISO](https://github.com/cubelinux/cubelinux-installer/actions/workflows/build-and-publish-iso.yml/badge.svg)](https://github.com/cubelinux/cubelinux-installer/actions/workflows/build-and-publish-iso.yml)

Build the bootable cubelinux installer ISO separately from the operating-system
image. This branch replaces Anaconda with Calamares and embeds the selected
cubelinux bootc image for offline installation. Installation does not create a
user; the installed system should start Plasma Setup on first boot.

## Current status

The migration branch is Calamares-only: its package set and boot path no longer
include Anaconda. The Phase 1 installer was built and successfully installed
and booted by the maintainer. The Phase 2 recovery implementation is present:
the installer creates and provisions the recovery partition, while the
`cubelinux` system image supplies the reset UI, KDE Settings module, backend,
and OTA recovery updater. The complete recovery flow still needs ISO and VM
validation before it can be considered usable.

The recovery prototype requires x86-64 UEFI with Secure Boot disabled and a
GPT disk large enough for a 32 GiB recovery partition and a 40 GiB root.
Automated root encryption is temporarily disabled because factory reset does
not yet preserve LUKS. Do not use this prototype on a disk with data you need.
Choose **Erase disk** on the partition page. Stock Calamares may still display
alongside and replace choices; these are rejected before any partition jobs run
because they do not reliably create the recovery layout.

The live installer uses Fedora's stable Fedora 44 bootc base. DNF installs
required package dependencies from the pinned `eu.edge.kernel.org` Fedora
mirror for Fedora 44 x86_64, rather than selecting another server through
Fedora MirrorManager. Fedora currently lists this HTTPS mirror for Fedora 44.
Set `FEDORA_MIRROR_ROOT` when running the build script to override the mirror
root. The selected mirror must carry both the Fedora release and updates repos;
the build will fail if that fixed mirror is unavailable. DNF skips optional
weak dependencies to keep the ISO smaller. The host workflow installs the
current Fedora 44 `image-builder` package for each run.

The installer image includes `xorrisofs` and `isomd5sum` for ISO assembly and
media-check metadata. Image Builder uses the `--bootc-ref` container as its
build root by default, so installing these tools only on the Fedora host does
not make them available to the ISO build stages.

## Calamares migration

Calamares is the only installer in this branch. Its custom partition layout
reserves a 32 GiB ext4 `CUBE_RECOVERY` partition and assigns the remaining
space to the ext4 `CUBE_ROOT` partition. Before showing the installer, a size
check confirms that the live kernel, initramfs, and SquashFS image fit in the
recovery partition's two slots. During installation, a local job copies
those files and a checksum manifest to the recovery partition. The live
SquashFS contains the release-matched offline OCI payload.

The bootc deployment job imports the embedded OCI archive into Podman storage
and runs the payload's bootc installer in a network-disabled container. It
retains the configured registry reference as the installed system's update
origin. Recovery boot selection and the reset action are implemented but have
not yet been validated end to end.

The ISO must stay small while preserving the embedded offline payload. Weak
DNF dependencies are disabled, and the build record reports the final ISO and
payload sizes so they can be compared with the current release.

## Build prerequisites

Use a Fedora 44 x86_64 build host with rootful Podman and `image-builder`
installed. The build needs root privileges for image-builder's loop devices
and mounts.
The cubelinux image must be published in a registry accessible to the builder.
It must include the matching recovery component; build the updated system
image before building this installer.

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

The resulting ISO is written under `output/`. The build script embeds the
selected image as an OCI archive inside the installer image. Calamares imports
the archive into temporary Podman storage to run the image's bootc installer;
bootc reads the install source directly from the embedded archive, so the
installer temporarily bind-mounts its selected scratch directory at `/var/tmp`
on the live system and inside the bootc container while bootc runs. This gives
OSTree's image proxy space to extract the embedded OCI archive. The installation
does not depend on network access or Podman's host-side image lookup. The
installer skips bootc's update-origin fetch check during deployment; the same
registry reference is retained as the installed system's update origin for
later use.

The live ISO uses Dracut's writable OverlayFS layer for temporary Podman storage
when it has at least three times the embedded OCI archive size plus 1 GiB
available. For RAM-backed overlays, the check also limits this to current
`MemAvailable`. If live space is unavailable or too small, the helper uses a
temporary Podman image store and `TMPDIR` under a hidden directory on the
selected target filesystem. It removes the temporary storage after bootc
finalization. When the target filesystem is used, it needs enough free space
for both the imported payload and the installed system; ext4 remains the
default target filesystem.

After bootc installs the system, a Calamares job removes the root (`/`) entry
from the installed `/etc/fstab`. The running bootc root is a composefs overlay,
so `systemd-remount-fs` cannot apply the install-time filesystem entry to `/`;
leaving it in place causes a failed-unit warning at login. Calamares writes the
remaining filesystem entries from the selected disk layout.

The bootc installation job streams its output into the Calamares log. The
current `bootc install to-filesystem` interface does not provide
machine-readable byte or layer progress.

## Project layout

```text
cubelinux-installer/
|-- config/
|   |-- calamares/              # Calamares sequence, modules, and cubelinux branding
|   `-- iso.yaml                # ISO boot menu and media label
|-- .github/workflows/
|   `-- build-and-publish-iso.yml # Build on main pushes and upload to SourceForge
|-- scripts/
|   |-- build-iso.sh             # Build installer image and ISO
|   |-- launch-calamares         # Start the Calamares Wayland session
|   |-- stage-recovery           # Copy live boot assets onto the recovery partition
|   |-- validate-recovery-media  # Check recovery bundle size before installation
|-- .gitignore
|-- Containerfile                # Calamares live installer image
`-- README.md
```

The ISO is a release artifact, separate from the bootc image release. The
GitHub Actions workflow builds on every push to `main` and uploads a separate
ISO, checksum, and source commit record to the SourceForge File Release
System. The ISO filename contains the full Git commit hash, so each upload is
retained as its own file and uses additional SourceForge storage. The build
prunes container images and caches when finished, removes the Fedora builder
image before upload, and deletes the local ISO after a successful upload.
The build record includes the ISO size and embedded offline payload size in
bytes.

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
- Calamares hides manual partitioning, but its stock storage page still offers
  Replace and Alongside. For a fresh install, select the whole-disk erase
  option. If the product flow must expose only whole-disk erase, customize the
  partition page before release.
- The installer must not collect or create user account information.
- Calamares user creation is not part of the workflow; verify Plasma Setup
  handles first-boot account creation.
- The selected cubelinux payload is embedded as an OCI archive in the ISO and
  installed from that local archive, while its registry reference remains the
  update origin for the installed system.
- Do not publish an ISO until the installed system has been confirmed to boot
  into the existing Plasma Setup account flow.

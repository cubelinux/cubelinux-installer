# cubelinux-installer

[![Build and publish installer ISO](https://github.com/cubelinux/cubelinux-installer/actions/workflows/build-and-publish-iso.yml/badge.svg)](https://github.com/cubelinux/cubelinux-installer/actions/workflows/build-and-publish-iso.yml)

Build the bootable cubelinux installer ISO as a project separate from the
cubelinux operating-system image. The ISO uses Fedora Anaconda's GTK interface,
embeds the selected cubelinux bootc image, lets the user choose a target disk, and
uses Anaconda's automatic partitioning on that disk. It does not create a user;
the installed system should start Plasma Setup on first boot.

## Current status

The Anaconda GTK interface was confirmed to start in a Fedora 44 test image.
The production installer image and ISO still need a full build and end-to-end
test in a disposable virtual machine before release. Verify disk selection, that
the embedded image installs without network access, that account creation is
skipped, and that Plasma Setup starts after reboot.

The live installer uses Fedora's stable Fedora 44 bootc base. DNF installs
required package dependencies while skipping optional weak dependencies to keep
the ISO smaller. The host workflow installs the current Fedora 44
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

During installation, Anaconda binds a temporary directory on the selected
target filesystem over the live installer's `/var/tmp`. Bootc uses this path
while importing the embedded image, avoiding the small RAM-backed scratch area
in the live ISO. The target filesystem therefore needs free space for the
temporary import in addition to the installed system. The temporary directory
is removed after a successful install.

## Project layout

```text
cubelinux-installer/
|-- config/
|   |-- anaconda.conf           # Hide the GTK account spoke
|   |-- interactive-defaults.ks # Bootc install and disk-backed scratch setup
|   `-- iso.yaml                # ISO boot menu and media label
|-- .github/workflows/
|   `-- build-and-publish-iso.yml # Build on main pushes and upload to SourceForge
|-- scripts/
|   `-- build-iso.sh             # Build installer image and ISO
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
- The installer must not collect or create user account information.
- Anaconda's GTK account spoke is hidden; verify this in the built installer.
- The selected cubelinux payload is embedded in the ISO's container storage
  and installed from the local image, while its registry reference remains the
  update origin for the installed system.
- Do not publish an ISO until the installed system has been confirmed to boot
  into the existing Plasma Setup account flow.

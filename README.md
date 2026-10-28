# cubelinux-installer

Build the bootable cubelinux installer ISO as a project separate from the
cubelinux operating-system image. The ISO uses Fedora Anaconda Web UI, embeds
the selected cubelinux bootc image, lets the user choose a target disk, and
uses Anaconda's automatic partitioning on that disk. It does not create a user;
the installed system should start Plasma Setup on first boot.

## Current status

The build and upload workflow is in place. The installer image and ISO build
path are based on Fedora's current `image-builder` and `bootc-generic-iso` workflow.
The first ISO still needs to be built and exercised in a virtual machine before
it is suitable for release. In particular, verify the Anaconda Web UI disk
selection flow, that the embedded image installs without network access, that
no account is requested, and that Plasma Setup starts after reboot.

## Build prerequisites

Use a Fedora 44 x86_64 build host with Podman and `image-builder` installed.
The build needs root privileges for image-builder's loop devices and mounts.
The cubelinux image must be published in a registry accessible to the builder.

Build using the exact image reference that the ISO should install:

```sh
sudo CUBELINUX_IMAGE_REF=ghcr.io/cubelinux/cubelinux:main bash ./scripts/build-iso.sh
```

The resulting ISO is written under `output/`. The source image is embedded in
the ISO, so installation should not need to download the OS image. The same
reference is retained as the installed system's update origin.

## Project layout

```text
cubelinux-installer/
|-- assets/
|   `-- cubelinux-icon.png       # Installer branding asset
|-- config/
|   |-- anaconda.conf           # Hide account creation page
|   |-- branding.css            # Anaconda Web UI branding
|   `-- iso.yaml                 # ISO boot menu and media label
|-- .github/workflows/
|   `-- build-and-publish-iso.yml # Build on main pushes and upload to SourceForge
|-- scripts/
|   `-- build-iso.sh             # Build installer image and ISO
|-- .gitignore
|-- Containerfile                # Anaconda Web UI installer environment
`-- README.md
```

The ISO is a release artifact, separate from the bootc image release. The
GitHub Actions workflow builds on every push to `main` and uploads a separate
ISO, checksum, and source commit record to the SourceForge File Release
System. The ISO filename contains the full Git commit hash, so each upload is
retained as its own file and uses additional SourceForge storage.

Configure these repository secrets before enabling uploads:

- `SOURCEFORGE_USER`: your SourceForge account name with release upload rights
- `SOURCEFORGE_SSH_KEY`: the private SSH key registered with that account
- `SOURCEFORGE_SSH_KEY_PASSPHRASE`: the passphrase for that private key

Set the `SOURCEFORGE_PROJECT` repository variable to the SourceForge project
URL slug. It defaults to `cubelinux-installer`.

Optionally set the `CUBELINUX_IMAGE_REF` repository variable to choose a
different published bootc image. For a private GHCR package, also configure
`GHCR_USERNAME` and `GHCR_TOKEN` secrets with pull access. The default is
`ghcr.io/cubelinux/cubelinux:main`.

## Important behavior

- The ISO is destructive to the selected target disk; make that clear in the
  installer flow and release notes.
- The installer must not collect or create user account information.
- Anaconda's account page is hidden; verify this in the built Web UI.
- The selected cubelinux payload must match the exact `containers-storage:`
  reference used by the ISO build so the embedded payload is used offline.
- Do not publish an ISO until the installed system has been confirmed to boot
  into the existing Plasma Setup account flow.

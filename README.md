# Anaconda smoke-test ISO

This project builds a small Fedora-based live ISO whose only purpose is to
check that the live environment boots and Anaconda Web UI starts. It does not
pull, embed, or install a CubeLinux image. No install kickstart or target image
is configured.

This is a development smoke test, not a usable OS installer. When Anaconda
appears, confirm the UI is running and shut down the VM. Do not proceed with
any installation actions.

## Build

Build on a Fedora 44 x86_64 machine with Podman and `image-builder` installed.
The build needs root privileges for image-builder's mounts and loop devices.

```sh
sudo bash ./scripts/build-iso.sh
```

The ISO and its SHA-256 checksum are written to `output/`.

## Smoke check in a VM

Create a disposable VM with at least 4 GB RAM and a 30 GB virtual disk, attach
the ISO, and boot it. The expected result is the Anaconda graphical interface.
The disk is present only so Anaconda can enumerate virtual storage; shut down
after confirming the interface appears, without starting an installation.

The ISO has not yet been built or validated. Test it in QEMU/KVM first, then
VirtualBox, VMware, and Hyper-V.

## Contents

- `Containerfile`: Fedora live environment and Anaconda runtime.
- `config/iso.yaml`: live ISO boot menu, labeled as a smoke test.
- `config/anaconda.conf`: hides account creation, which is unrelated to this check.
- `scripts/build-iso.sh`: local build script; it does not publish artifacts.

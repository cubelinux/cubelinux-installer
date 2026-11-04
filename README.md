# Anaconda GTK smoke-test ISO

> [!WARNING]
> **Experimental artifact disclaimer:** this ISO is an unvalidated development smoke test intended only to verify boot and Anaconda GTK startup in a disposable virtual machine. It does not contain or install cubelinux, and it is not an installation medium. Do not initiate storage changes or installation actions. Use only in an environment where disk state can be discarded; behavior is not guaranteed and use is at your own risk.

This project builds a small Fedora-based live ISO whose only purpose is to
check that the live environment boots and Anaconda GTK starts. It does not
pull, embed, or install a cubelinux image. No install kickstart or target image
is configured.

This experiment stays on `anaconda-smoke`; the production `main` branch is
unchanged. The runtime explicitly installs `anaconda-core`, `anaconda-gui`, and
`anaconda-tui`, excludes `anaconda-webui`, and checks the package selection during
the build. The WebUI configuration and browser account setup are removed. GTK
still uses Anaconda's graphical session, so this change bypasses the browser
launcher but does not establish that the Hyper-V display issue is resolved.

This is a development smoke test, not a usable OS installer. When Anaconda
appears, confirm the UI is running and shut down the VM. Do not proceed with
any installation actions.

## Build

Build on a Fedora 44 x86_64 machine with Podman and `image-builder` installed.
The build needs root privileges for image-builder's mounts and loop devices.

```sh
sudo bash ./scripts/build-iso.sh
```

The ISO, SHA-256 checksum, and build information are written to `output/` with
the prefix `cubelinux-anaconda-gtk-smoke-`. Attach that new ISO to Hyper-V;
older WebUI smoke ISOs may still be in the output directory.

## Diagnose the Hyper-V startup failure

The first boot-menu entry now starts a shell. Anaconda stays stopped until its
logs have somewhere persistent to go. Attach a **separate, writable diagnostic
disk** to the disposable VM and mount its existing partition. Do not format or
mount the disk you intend to use as an installation target. For example, after
checking the device name with `lsblk -f`:

```sh
mkdir -p /mnt/diagnostics
mount /dev/sdb1 /mnt/diagnostics
cubelinux-smoke-debug /mnt/diagnostics
```

Replace `/dev/sdb1` with the actual diagnostic partition. The command refuses
to start if the directory is not a separate writable mount. It masks the normal
systemd shutdown targets for this boot, verifies those masks, starts Anaconda
once, and saves a live journal stream, snapshots, Anaconda logs, process list,
and package versions to a timestamped directory on the diagnostic disk. It also
requests Python thread dumps and a payload trace when their processes can be
verified. It runs for up to 30 minutes; press Ctrl+C to stop it early.
The mask cannot prevent a kernel panic or a Hyper-V reset. After a reboot,
mount the same disk again and inspect its `cubelinux-smoke-*` directory. The
`journal-follow.log`, `anaconda-units.txt`, `logs/anaconda-tb-all.log`, and
`strace-payload*` files are the first ones to examine. In `packages.txt`, expect
`anaconda-gui` to be installed and `anaconda-webui` to be reported as not installed.

## Smoke check in a VM

Create a disposable VM with at least 4 GB RAM and a 30 GB virtual disk, attach
the ISO. For the first GTK attempt, use the default diagnostic shell and capture
logs as described above. For a direct startup test, choose **Anaconda GTK smoke
test (no OS image)** from the boot menu; that entry does not enable the diagnostic
helper's shutdown guards. The expected result is the classic GTK language
selection screen followed by the installation summary, rather than a browser UI.
The disk is present only so Anaconda can enumerate virtual storage; shut down
after confirming the interface appears, without starting an installation.

Earlier WebUI ISOs built, but their graphical startup failed on Hyper-V.
The GTK variant still needs a full Fedora build and Hyper-V boot validation.
This branch is diagnostic and must not be used as an installer.

## Contents

- `Containerfile`: Fedora live environment and Anaconda runtime.
- `config/iso.yaml`: live ISO boot menu, labeled as a smoke test.
- `scripts/build-iso.sh`: local build script; it does not publish artifacts.
- `scripts/cubelinux-smoke-debug`: captures one guarded startup attempt to a
  separate diagnostic disk.

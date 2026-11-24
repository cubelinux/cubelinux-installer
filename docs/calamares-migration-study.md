# Calamares migration and recovery study

## Scope

This is the implementation plan for `research/calamares-migration`. Phase 1
replaces Anaconda with Calamares and removes the Anaconda-only files and
packages from this branch. Phase 2 adds recovery after Phase 1 is validated.
The work remains split into two independent phases:

- **Phase 1:** replace Anaconda with Calamares while preserving the existing
  install behavior and disk layout. Do not add a recovery partition in this
  phase.
- **Phase 2:** add an on-disk recovery environment with one action, factory
  reset. The reset installs a fresh cubelinux bootc image and preserves the
  recovery environment for future resets.

Account setup remains in Plasma Setup on first boot in both phases.

Two constraints apply to both phases:

- **Offline installation is required.** Keep the release-matched cubelinux OCI
  archive in the ISO and do not make installation or factory reset depend on a
  registry, package mirror, or network connection.
- **Keep the ISO small.** Disable weak dependencies, avoid packages and assets
  that the chosen installer flow does not use, and record the final ISO size
  alongside the embedded payload size. This migration branch uses Calamares
  only; it does not keep a parallel Anaconda installer.

## Current installer behavior

The previous installer image was based on Fedora 44 bootc and packaged as a
generic bootc ISO. Anaconda GTK supplied its live interface and storage
workflow, with account creation and manual partitioning hidden and a patch to
restrict disk selection to one target. Phase 1 replaces that runtime with a
Calamares-only image.

The cubelinux OCI image is embedded in the ISO as an OCI archive. The previous
Anaconda Kickstart integration deployed it with `bootc install to-filesystem`
and skipped the update-origin fetch check for offline installation. A post
step removed the installed `/` fstab entry, which is incompatible with the
bootc composefs overlay root. Calamares imports the embedded payload into
Podman storage and runs that image's bootc installer in a privileged container
with networking disabled. It keeps the published image reference as the
update origin. ISO and VM validation remain pending.

The embedded payload, offline behavior, ext4 target, update origin, first-boot
account setup, and non-recovery install layout are the behaviors to preserve.
The Anaconda UI and integration files are removed from Phase 1.

## Phase 1 implementation status

The Containerfile installs Calamares and its Wayland session, the boot menu
starts Calamares by default, and Anaconda RPMs, patches, branding, Kickstart
files, and systemd startup configuration have been removed from this branch.
Calamares settings now queue partitioning, mounting, the embedded bootc install,
fstab generation and cleanup, bootc finalization, and unmounting. The bootc
install and finalization jobs run inside the embedded payload container and
cannot access a network. Runtime validation in a built ISO and virtual machine
is still required.

## Recovery requirement

Use ChromeOS MiniOS as an architectural reference, not as a requirement to
copy its A/B system layout. ChromiumOS describes MiniOS as a small recovery OS
that can repartition a disk, wipe user data, and install a current stable
system. Its disk layout has dedicated MiniOS A/B partitions. cubelinux's
requested first version is smaller: one recovery environment and one visible
action, factory reset. [MiniOS overview](https://chromium.googlesource.com/chromiumos/platform2/+/HEAD/minios/),
[ChromiumOS disk format](https://chromium.googlesource.com/chromiumos/docs/+/HEAD/disk_format.md)

The recovery partition should contain a minimal bootable recovery system and
the release-matched cubelinux OCI payload, so recovery works without a
network. The recovery flow must reinstall the OS and clear all writable
system/user data while keeping the recovery environment and its boot path
available for another reset. That means the recovery partition and the
bootloader files needed to launch it are installer-owned partitions/data, not
part of the state being reset. The initial assumption is that recovery restores
the image payload shipped with that installer release; whether the payload
should later be updated independently is an open product decision.

The disk layout will need an EFI system partition, any boot partition required
by the chosen bootc layout, a recovery partition, and the bootc root/state
partition or partitions. The recovery boot entry must survive bootc updates
and root reinstallation. The reset helper must identify the intended system
partitions explicitly and must never treat the recovery partition as resettable
data.

## Feasibility

Calamares is packaged in Fedora 44, with Fedora listing version 3.3.14. The
package is described as a Qt 6 installer framework intended to replace
`liveinst`. Its partition view supports whole-disk installation and manual
partitioning, while its module system separates user-facing views from
installation jobs. [Fedora package](https://packages.fedoraproject.org/pkgs/calamares/calamares/),
[Calamares partition guide](https://calamares.io/docs/partitions/),
[Calamares modules](https://github.com/calamares/calamares/blob/calamares/src/modules/README.md)

Calamares does not provide a bootc installer module. Its `shellprocess` job
can run commands in the live environment and is the documented alternative to
the lower-level process module, which Calamares discourages. A helper script
is enough for a first prototype; a Python job module is preferable if it needs
structured partition data, error reporting, or progress updates.
[shellprocess configuration](https://github.com/calamares/calamares/blob/calamares/src/modules/shellprocess/shellprocess.conf)

`bootc install to-filesystem` is explicitly designed for an external installer
to create and mount the filesystem layout, then hand the mounted root to bootc.
It accepts the root path and mount specifications, and the bootc docs describe
Anaconda as one consumer of this workflow. This makes Calamares partitioning
plus a bootc job a natural match. The bootc install step must own bootloader
and deployment setup; Calamares's generic bootloader job should not also
install a second loader. [bootc to-filesystem manual](https://bootc.dev/bootc/man/bootc-install-to-filesystem.8.html),
[bootc installation guide](https://bootc.dev/bootc/bootc-installation.7.html)

## Phase 1: replace Anaconda with Calamares

Keep Phase 1 limited to the installer replacement. Preserve the embedded OCI
payload, update-origin reference, offline install behavior, ext4 target,
first-boot account setup, and current non-recovery disk layout.

1. **Calamares boot spike:** install Calamares and the required Qt graphical
   session packages; boot the generic ISO and confirm the installer window
   launches. Code is in place; ISO validation remains pending.
2. **Storage flow:** verify that the Calamares profile creates the ext4 target
   layout, presents the intended disk and erase choices, and hides manual
   partitioning. The stock partition module still offers Replace and Alongside
   when Manual is disabled, so review that behavior against cubelinux's
   single-target flow. [partition.conf](https://github.com/calamares/calamares/blob/calamares/src/modules/partition/partition.conf)
3. **Bootc handoff:** import the embedded OCI payload into local Podman storage
   and run the payload's own `bootc install to-filesystem` in a privileged,
   network-disabled container. Retain the registry reference as update origin,
   skip the network fetch check, and pass the mounted root and boot
   specifications. Do not add recovery partitions or boot entries in this
   phase. [bootc installation guide](https://bootc.dev/bootc/bootc-installation.7.html),
   [bootc to-filesystem manual](https://bootc.dev/bootc/man/bootc-install-to-filesystem.8.html)
4. **First-boot compatibility:** omit Calamares user creation, remove the
   composefs root entry from the generated fstab, and verify Plasma Setup starts
   after installation.
5. **VM acceptance:** verify install from the embedded payload with networking
   disabled, ext4, bootloader setup, update origin, and first boot. Check UEFI
   and any BIOS mode cubelinux intends to support.
6. **Size and release cleanup:** recheck the Calamares dependency set and
   remove unneeded modules, packages, and assets while retaining the embedded
   offline payload. Record and compare the ISO size with the current release.
   Update release documentation and workflow.

Phase 1 is complete when a Calamares ISO installs and boots cubelinux with the
existing behavior. Recovery is explicitly out of scope for this phase.

## Phase 2: add the factory-reset recovery partition

Start Phase 2 only after Phase 1 is stable. The recovery UI offers one action:
factory reset. The local, release-matched payload makes reset available
without networking. Reset clears all mutable OS and user data, installs a
fresh cubelinux image, and leaves recovery bootable for the next reset.

The current Phase 2 design and its small implementation tasks are documented
in [recovery-partition-design.md](recovery-partition-design.md).

1. **Partition and payload staging:** the installer now configures the
   `CUBE_RECOVERY` and `CUBE_ROOT` ext4 partitions and copies the release's live
   kernel, initramfs, SquashFS image, and checksum manifest to recovery. Bundle
   capacity and partition layout still need VM validation.
2. **Recovery boot path:** an EFI entry selects the ISO-provisioned recovery
   boot image and an independently updated A/B runtime overlay. Verify they
   survive bootc updates and root reinstalls.
3. **One-action reset flow:** the current helper checks payload and partition IDs
   before formatting; reinstall only OS and writable data partitions; retain
   recovery; reboot into first-boot account setup. Use
   `bootc install to-filesystem`, which accepts a filesystem prepared and
   mounted by the recovery environment. Do not use `bootc install to-disk
   --wipe`, because it would erase recovery while the reset is running.
4. **Recovery acceptance:** test Erase, Replace, and Alongside layouts, normal
   boot, recovery boot when the installed root is unavailable, an offline full
   reset, and a second reset using the same recovery partition. Verify user
   data is gone and recovery still boots. The installer and recovery entry use
   Fedora's signed shim/GRUB chain with Secure Boot enabled. Encrypted root
   installations are not supported by the current prototype.
5. **Recovery updates:** the installed system stages a second recovery slot
   from the booted image digest. Validate slot activation and interruption
   handling with actual release images.

Do not use plain `to-disk --wipe` for factory reset unless the recovery
partition and its boot path are deliberately recreated and verified. If
whole-disk reset cannot safely run from recovery, prefer the
`to-filesystem` path that reformats only system partitions and preserves the
recovery partition.

## Main feasibility risks

- **Live graphical session:** Anaconda previously provided its own live
  installer runtime. Calamares is a Qt application and needs a working
  graphical session, launcher, and autologin arrangement in the ISO. This is
  likely the first technical spike.
- **Phase 1 partition-to-bootc handoff:** The Calamares mount layout and device IDs
  must be translated into `bootc install to-filesystem` arguments correctly.
  The payload image must load and run locally in Podman with host devices and
  target mounts visible while networking stays disabled. Validate ext4 feature
  flags against the actual cubelinux bootc backend and boot requirements.
- **Phase 2 direct disk install:** The `to-disk` option depends on testing
  embedded OCI import, offline fetch-check behavior, generated fstab, and
  recovery partition recreation. A reset must not erase the environment
  currently doing the work.
- **Erase-only UI:** Calamares's stock partition settings cannot hide Replace
  and Alongside. If `to-disk` is unsuitable, a small maintained partition
  module patch is needed to meet the one-action-only requirement.
- **Bootloader ownership:** Confirm that the bootc invocation installs the
  expected GRUB/EFI files for UEFI and any supported BIOS mode. Calamares's
  generic bootloader job stays disabled to avoid installing a second loader.
- **Progress and long-running jobs:** The previous Anaconda integration showed
  elapsed time because bootc does not provide machine-readable progress.
  Calamares needs useful status and failure output during long installs.
- **Safety and supported layouts:** Test one disk, multiple visible disks,
  UEFI, BIOS if still supported, and reboot into first-boot setup. Confirm the
  initial-install flow cannot silently format a non-selected disk, and reset
  cannot erase recovery or leave an extra writable data partition untouched.

## Task boundary

Keep Phase 1 and Phase 2 in separate implementation tasks and reviews. Phase 1
must not add recovery partitioning. Phase 2 starts from the completed Calamares
installer and adds recovery storage, boot, and reset behavior without changing
the Phase 1 installer contract.

## Research sources

- [Fedora Calamares package](https://packages.fedoraproject.org/pkgs/calamares/calamares/)
- [Calamares user guide](https://calamares.io/docs/users-guide/)
- [Calamares partition guide](https://calamares.io/docs/partitions/)
- [Calamares module documentation](https://github.com/calamares/calamares/blob/calamares/src/modules/README.md)
- [Calamares shellprocess configuration](https://github.com/calamares/calamares/blob/calamares/src/modules/shellprocess/shellprocess.conf)
- [bootc `to-filesystem` manual](https://bootc.dev/bootc/man/bootc-install-to-filesystem.8.html)
- [bootc installation guide](https://bootc.dev/bootc/bootc-installation.7.html)
- [bootc install mount manual](https://bootc.dev/bootc/man/bootc-install-mount.8.html)
- [ChromiumOS MiniOS recovery environment](https://chromium.googlesource.com/chromiumos/platform2/+/HEAD/minios/)
- [ChromiumOS disk format and MiniOS partitions](https://chromium.googlesource.com/chromiumos/docs/+/HEAD/disk_format.md)
- [systemd-repart partition definitions](https://www.freedesktop.org/software/systemd/man/latest/repart.d.html)

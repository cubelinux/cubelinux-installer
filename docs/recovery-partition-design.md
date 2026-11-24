# cubelinux recovery partition design

## Goal

Provide one offline recovery action: factory reset. It reinstalls the
release-matched cubelinux image, clears the installed system and user state,
and leaves the recovery environment available for another reset.

This is a recovery feature, not a promise that a modified or damaged disk can
be repaired. The recovery files must remain separate from the filesystem that
the reset reformats.

## Implemented first layout

Use GPT with three partitions for a standard UEFI installation:

```text
| EFI System | cubelinux Recovery (ext4) | cubelinux Root (ext4, remaining space) |
| 600 MiB    | 32 GiB                      | rest of disk                           |
```

Use short, stable labels such as `CUBE_RECOVERY` and `CUBE_ROOT`. Keep the
recovery filesystem unmounted by Calamares' normal target mount step. The
existing EFI System Partition and the recovery partition are preserved during
factory reset. The root partition contains the OS and all mutable system and
user data in the current layout, so formatting it resets the machine's state.

The recovery partition is 32 GiB. The installer limits each bundle to
14 GiB and reserves space for a second slot, ext4 reserve and working space.
The staging job checks available space again before copying the first slot.

Calamares' custom `partitionLayout` provisions this layout for Erase disk.
Erase is selected by default. Stock Calamares may still display Replace or
Alongside when existing operating systems are detected; the installer rejects
those choices before any partition jobs run because they do not reliably
create the required recovery layout.

## Recovery contents and boot

The implementation reuses the release-matched live installer system
rather than building a second OS image. During installation, copy these ISO
assets to the recovery partition:

- the live kernel and initramfs;
- `LiveOS/squashfs.img`, which contains the offline installer and OCI payload;
- a checksum manifest for the copied boot files and squashfs image.

The recovery kernel mounts the recovery partition read-only using Dracut's
live-image support. The recovery system image runs with a temporary writable
overlay. Recovery mode launches the Qt/QML factory-reset wizard, which requires
confirmation before invoking the reset helper. The boot arguments and mount
behavior still need validation from a built ISO in a VM.

The installer creates a separate UEFI entry pointing to Fedora's signed shim
on the EFI System Partition and copies the matching signed Fedora GRUB beside
it. GRUB loads its per-entry configuration from the recovery EFI directory,
then loads `active.cfg` from `CUBE_RECOVERY` to select one of two self-contained
slots. The installer, KDE Settings action, reset flow, and OTA updater validate
the recorded EFI, disk, root, and recovery partition IDs and keep the copied
Fedora loader synchronized with `EFI/fedora`. The boot path still needs Secure
Boot VM validation.

The live image is larger than a purpose-built recovery OS, but this approach
reuses the existing offline payload and installer runtime. It also gives the
first prototype a known-good kernel, initramfs, and bootable userspace. A
smaller dedicated recovery image can follow after the reset flow works.

## Factory-reset flow

1. Boot the recovery environment without relying on the installed root.
2. Verify the recovery filesystem, checksum manifest, and local OCI payload
   before formatting anything.
3. Find exactly one `CUBE_ROOT` partition on the same GPT disk as
   `CUBE_RECOVERY`. Refuse the reset if either partition is missing, ambiguous,
   mounted, or on a different disk.
4. Unmount the target, create a fresh ext4 filesystem on the root partition,
   and mount it as the bootc target. Never format the EFI or recovery
   partitions.
5. Run the existing offline `install-bootc` flow using the local payload and
   `bootc install to-filesystem`. Run fstab cleanup and bootc finalization.
6. Restore or verify the persistent recovery boot entry, then reboot into
   cubelinux's first-boot setup.

The root partition's GPT PARTUUID is the stable target identity across
formatting. The staging job records the disk GUID and root, recovery and EFI PARTUUIDs
in a checksummed layout manifest. Reset must verify those identities and GPT
partition labels, and fail closed if the expected layout is not present. Do
not use `bootc install to-disk --wipe` for reset because it would erase the
recovery partition along with the OS.

The current bootc install helper already keeps temporary Podman storage on the
target filesystem when live scratch is insufficient, then removes it during
finalization. This permits reset to run from the recovery filesystem while
using the fresh root filesystem for temporary storage.

## KDE Settings entry

Provide a **Reset System** module in KDE System Settings with a **Factory
Reset** section and a **Restart to Factory Reset** action. Explain that the user can start a factory
reset after reboot; restarting alone must not erase data. Show recovery as
unavailable when no usable recovery installation or boot entry is present.

The module invokes a privileged helper that selects the matching recovery
entry for the next boot only and restarts the machine. Factory reset
confirmation remains in the recovery environment. The entry is also added to
the firmware boot menu. Both paths need VM validation.

## Recovery updates

The installed system has a timer that checks the booted bootc image identity,
downloads that exact registry digest, rebuilds the recovery live image in the
inactive slot, verifies the result and atomically switches `active.cfg`. It
keeps the previously active slot during the operation. The updater uses
temporary space on the system disk and needs network access while downloading;
factory reset itself uses the staged offline image. This implementation has
not yet been validated against a built ISO or an interrupted update. The
prototype updates the reset payload, UI and helper scripts; it currently
retains the recovery environment's original kernel, initramfs and base
packages. It checks that the updated UI can load against that environment
before switching slots.

## Implementation status and VM validation

The code is in place for installer partitioning and recovery staging, a
dedicated UEFI boot entry, the Qt/QML confirmation and completion screens, the
root-only reset backend, a KDE **Reset System** module, and a two-slot updater
that pulls the booted image by digest and switches slots after verification.
The recovery UI and helpers are shared from the `cubelinux` component; the
installer owns disk layout and initial provisioning.

The remaining work is runtime validation with the ISO and a VM. Check:

1. Normal UEFI boot, installer preflight, and the Erase disk partition layout.
2. Recovery slot contents and UEFI entry after installation.
3. Recovery boot with the installed root unavailable, with the recovery
   partition mounted read-only.
4. Offline factory reset, first-boot setup, and a second reset using the same
   recovery partition.
5. KDE Settings status and privileged restart into recovery.
6. Recovery update from a newer registry image, including interruption before
   and after slot activation.

The installer ISO creates the recovery partition. Existing installations
without one require reinstalling; system updates do not create or resize disk
partitions. Updates only maintain recovery on installations that already have it.

## Limits for the first version

- The first layout targets the current single-root UEFI installation and
  requires enough space for the 32 GiB recovery partition plus at least 40 GiB
  for the root partition.
- The installer temporarily hides Calamares root encryption because reset does
  not yet preserve LUKS. The reset helper also refuses an encrypted root. The
  recovery partition remains unencrypted so it can boot.
- Only Erase disk is supported. Replace and Alongside may remain visible in
  stock Calamares, but the installer rejects them before disk jobs run.
- Recovery initially uses the payload shipped with that installer release.
  The update service and the two-slot layout need validation with actual
  release bundles.
- GRUB and the Fedora kernel are launched through Fedora's signed shim/GRUB
  chain. The external initramfs and mutable ext4 recovery payload are checked
  for accidental damage but are not a verified-boot security boundary.
- Secure Boot permits both normal installation and recovery boot without
  enrolling a CubeLinux signing key, provided the machine trusts the Fedora
  shim already used by the installer.

## References

- [Calamares partition module configuration](https://github.com/calamares/calamares/blob/calamares/src/modules/partition/partition.conf)
- [Calamares partition layout implementation](https://github.com/calamares/calamares/blob/calamares/src/modules/partition/core/PartitionLayout.cpp)
- [Calamares Alongside and Replace partition actions](https://github.com/calamares/calamares/blob/calamares/src/modules/partition/core/PartitionActions.cpp)
- [bootc `to-filesystem` manual](https://bootc.dev/bootc/man/bootc-install-to-filesystem.8.html)
- [Dracut kernel command line](https://github.com/dracut-ng/dracut/blob/main/man/dracut.cmdline.7.adoc)

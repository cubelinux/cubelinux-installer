# cubelinux recovery partition design

## Goal

Provide one offline recovery action: factory reset. It reinstalls the
release-matched cubelinux image, clears the installed system and user state,
and leaves the recovery environment available for another reset.

This is a recovery feature, not a promise that a modified or damaged disk can
be repaired. The recovery files must remain separate from the filesystem that
the reset reformats.

## Proposed first layout

Use GPT with three partitions for a standard UEFI installation:

```text
| EFI System | cubelinux Recovery (ext4) | cubelinux Root (ext4, remaining space) |
| 600 MiB    | 16 GiB                      | rest of disk                           |
```

Use short, stable labels such as `CUBE_RECOVERY` and `CUBE_ROOT`. Keep the
recovery filesystem unmounted by Calamares' normal target mount step. The
existing EFI System Partition and the recovery partition are preserved during
factory reset. The root partition contains the OS and all mutable system and
user data in the current layout, so formatting it resets the machine's state.

The initial recovery partition size is 16 GiB. Before showing Calamares, the
installer checks that the kernel, initramfs, and live squashfs fit under 14
GiB, leaving space for ext4's reserved blocks and at least 1 GiB of working
space. The staging job checks the actual available space again before copying.

Calamares' custom `partitionLayout` is applied when Erase, Replace, or
Alongside creates a new cubelinux layout. This can provision the recovery
partition for each automated choice, provided the selected disk or free-space
region is large enough. That is separate from bootc's ability to install onto
the newly mounted root filesystem.

## Recovery contents and boot

For the first prototype, reuse the release-matched live installer system
rather than building a second OS image. During installation, copy these ISO
assets to the recovery partition:

- the live kernel and initramfs;
- `LiveOS/squashfs.img`, which contains the offline installer and OCI payload;
- a checksum manifest for the copied boot files and squashfs image.

The recovery kernel should mount the recovery partition read-only using
Dracut's live-image support. The recovery system image also runs read-only;
temporary writes must use a separate writable overlay or target-disk scratch.
Its startup path should launch a Qt/QML factory-reset wizard and require
confirmation before touching the installed system. The exact boot arguments
and writable-space requirements remain to be validated.

The recovery boot entry must live outside the root filesystem being reset.
The first boot-path spike should establish a GRUB entry that loads the recovery
kernel and live image from `CUBE_RECOVERY`, and verify that the entry survives
normal bootc updates and a root reinstall. The exact GRUB integration is still
an implementation question; do not assume an entry stored only under `/boot`
will survive formatting the root partition.

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
formatting. The staging job records the disk GUID and root/recovery PARTUUIDs
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

The module should ask a privileged service to select the recovery boot entry
for the next boot only and restart the machine. The service must validate the
entry and report failures to the UI. Factory reset confirmation remains in
the recovery environment. The boot mechanism and its one-time selection need
to be established before this action can be implemented reliably. Recovery
must also remain accessible from the boot menu if the installed OS cannot boot.

## Small implementation tasks

1. **Layout spike:** add the labeled ext4 recovery partition to the
   Calamares whole-disk layout, measure the recovery bundle, and validate the
   resulting partition table in a VM.
2. **Boot spike:** populate the partition from the live ISO, boot it from the
   installed system's startup menu, and verify the entry after a bootc update
   and root reinstall.
3. **Reset action:** add the confirmation UI and fail-closed reset helper;
   format only `CUBE_ROOT` and reinstall the local payload.
4. **Acceptance:** test normal boot, recovery boot with root unavailable,
   offline reset, first-boot setup, and a second reset from the same recovery
   partition.
5. **Settings integration:** add the Reset System module and a privileged,
   one-time recovery boot selection after the boot path is established.
6. **OTA integration:** stage and verify a new recovery bundle during normal
   system updates, and retain a bootable previous version until activation.
   Measure bundle sizes and choose a partition capacity that supports this.

The installer ISO creates the recovery partition. Existing installations
without one require reinstalling; system updates do not create or resize disk
partitions. Updates only maintain recovery on installations that already have it.

## Limits for the first version

- The first layout targets the current single-root UEFI installation and
  requires enough space for the 16 GiB recovery partition plus at least 40 GiB
  for the root partition.
- Calamares currently offers root encryption. Recovery must either unlock and
  reformat an existing LUKS root safely or disable that option for
  recovery-capable installs; the recovery partition itself stays unencrypted
  so it remains bootable.
- Erase, Replace, and Alongside recovery layouts need VM validation; the
  selected target or Alongside free-space region must fit both partitions.
- Recovery initially uses the payload shipped with that installer release.
  Updating it alongside system OTA updates remains to be implemented; the
  current 16 GiB proposal has not been shown to fit two bundles.
- Recovery integrity checks detect accidental damage. A mutable ext4
  recovery partition is not a verified-boot security boundary.

## References

- [Calamares partition module configuration](https://github.com/calamares/calamares/blob/calamares/src/modules/partition/partition.conf)
- [Calamares partition layout implementation](https://github.com/calamares/calamares/blob/calamares/src/modules/partition/core/PartitionLayout.cpp)
- [Calamares Alongside and Replace partition actions](https://github.com/calamares/calamares/blob/calamares/src/modules/partition/core/PartitionActions.cpp)
- [bootc `to-filesystem` manual](https://bootc.dev/bootc/man/bootc-install-to-filesystem.8.html)
- [Dracut kernel command line](https://github.com/dracut-ng/dracut/blob/main/man/dracut.cmdline.7.adoc)

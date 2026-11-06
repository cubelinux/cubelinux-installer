bootc --source-imgref=oci-archive:/usr/share/cubelinux/payload.oci.tar:payload --target-imgref=__CUBELINUX_IMAGE_REF__

%pre-install --erroronfail --log=/tmp/cubelinux-scratch-pre-install.log
set -eu

target_root=/mnt/sysroot
physical_root=/mnt/sysimage
scratch_mount=/run/cubelinux-installer-btrfs-top
scratch_dir="$scratch_mount/.cubelinux-installer-scratch"

if ! mountpoint -q "$target_root" || ! mountpoint -q "$physical_root"; then
    echo "Anaconda target roots are not mounted at $target_root and $physical_root" >&2
    exit 1
fi

root_fstype=$(findmnt -n -o FSTYPE --target "$physical_root")
if [ "$root_fstype" != btrfs ]; then
    echo "The installer needs a Btrfs target filesystem for disk-backed image import scratch space" >&2
    exit 1
fi

root_source=$(findmnt -n -o SOURCE --target "$physical_root")
root_device=${root_source%%\[*}
if [ -z "$root_device" ] || [ ! -b "$root_device" ]; then
    echo "Could not resolve the Btrfs target device from $root_source" >&2
    exit 1
fi

if mountpoint -q "$scratch_mount"; then
    echo "Installer scratch mount is already active at $scratch_mount" >&2
    exit 1
fi

# Keep import scratch beside the target root subvolume; bootc initializes that
# subvolume and would otherwise unlink a scratch directory created inside it.
mkdir -p "$scratch_mount" /var/tmp
mount -t btrfs -o subvolid=5 "$root_device" "$scratch_mount"
rm -rf "$scratch_dir"
mkdir -p "$scratch_dir"
chmod 1777 "$scratch_dir"
mount --bind "$scratch_dir" /var/tmp
mountpoint -q /var/tmp
df -h /var/tmp
findmnt --target /var/tmp
%end

%post --nochroot --erroronfail --log=/tmp/cubelinux-scratch-post-install.log
set -eu
scratch_mount=/run/cubelinux-installer-btrfs-top
scratch_dir="$scratch_mount/.cubelinux-installer-scratch"
if mountpoint -q /var/tmp; then
    umount /var/tmp
fi
if mountpoint -q "$scratch_mount"; then
    rm -rf "$scratch_dir"
    umount "$scratch_mount"
fi
rmdir "$scratch_mount" 2>/dev/null || true
%end

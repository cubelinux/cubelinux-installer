bootc --source-imgref=oci-archive:/usr/share/cubelinux/payload.oci.tar:payload --target-imgref=__CUBELINUX_IMAGE_REF__

%pre-install --erroronfail --log=/tmp/cubelinux-scratch-pre-install.log
set -eu

target_root=/mnt/sysroot
physical_root=/mnt/sysimage
scratch_dir="$physical_root/.cubelinux-installer-scratch"

if ! mountpoint -q "$target_root" || ! mountpoint -q "$physical_root"; then
    echo "Anaconda target roots are not mounted at $target_root and $physical_root" >&2
    exit 1
fi

mkdir -p "$scratch_dir"
chmod 1777 "$scratch_dir"
mount --bind "$scratch_dir" /var/tmp
df -h /var/tmp
%end

%post --nochroot --erroronfail --log=/tmp/cubelinux-scratch-post-install.log
set -eu
mountpoint -q /var/tmp
umount /var/tmp
rm -rf /mnt/sysimage/.cubelinux-installer-scratch
%end

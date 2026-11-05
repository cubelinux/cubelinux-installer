bootc --source-imgref=oci-archive:/usr/share/cubelinux/payload.oci.tar:payload --target-imgref=__CUBELINUX_IMAGE_REF__

%pre-install --erroronfail --log=/tmp/cubelinux-scratch-pre-install.log
set -eu

target_root=/mnt/sysroot
scratch_dir="$target_root/.cubelinux-installer-scratch"

if ! mountpoint -q "$target_root"; then
    echo "Anaconda target root is not mounted at $target_root" >&2
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
rm -rf /mnt/sysroot/.cubelinux-installer-scratch
%end

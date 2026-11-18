bootc --source-imgref=oci-archive:/usr/share/cubelinux/payload.oci.tar:payload --target-imgref=__CUBELINUX_IMAGE_REF__

%post --erroronfail --log=/tmp/cubelinux-fstab-post-install.log
set -eu

fstab=/etc/fstab
temporary_fstab=$(mktemp /etc/.fstab.cubelinux.XXXXXX)
trap 'rm -f "$temporary_fstab"' EXIT

# bootc/composefs mounts / as an overlay. Keep Anaconda's real disk mounts,
# but do not ask systemd to remount that overlay using the install-time root entry.
awk 'NF < 2 || $1 ~ /^#/ || $2 != "/" { print }' "$fstab" > "$temporary_fstab"

if cmp -s "$fstab" "$temporary_fstab"; then
    exit 0
fi

chmod --reference="$fstab" "$temporary_fstab"
chown --reference="$fstab" "$temporary_fstab"
mv -f "$temporary_fstab" "$fstab"
trap - EXIT
if command -v restorecon >/dev/null 2>&1; then
    restorecon "$fstab"
fi

if awk 'NF >= 2 && $1 !~ /^#/ && $2 == "/" { found = 1 } END { exit !found }' "$fstab"; then
    echo "The composefs root entry remains in $fstab" >&2
    exit 1
fi

echo "Removed the composefs root entry from $fstab"
%end

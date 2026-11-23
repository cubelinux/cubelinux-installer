ARG FEDORA_BOOTC_IMAGE=quay.io/fedora/fedora-bootc:44
FROM ${FEDORA_BOOTC_IMAGE}

ARG CUBELINUX_IMAGE_REF
ARG FEDORA_MIRROR_ROOT=https://eu.edge.kernel.org/fedora
# Keep the live installer dependency set lean by excluding optional weak
# dependencies.
RUN test -n "${CUBELINUX_IMAGE_REF}" && \
    dnf -y \
        --disablerepo='*' \
        --enablerepo=fedora \
        --enablerepo=updates \
        --setopt=fedora.baseurl=${FEDORA_MIRROR_ROOT}/releases/44/Everything/x86_64/os/ \
        --setopt=fedora.metalink= \
        --setopt=fedora.mirrorlist= \
        --setopt=updates.baseurl=${FEDORA_MIRROR_ROOT}/updates/44/Everything/x86_64/ \
        --setopt=updates.metalink= \
        --setopt=updates.mirrorlist= \
        --setopt=install_weak_deps=False \
        --setopt=tsflags=nodocs \
        install \
        calamares \
        qt6-qtwayland \
        gnome-kiosk \
        dbus-daemon \
        dracut-live \
        dracut-config-generic \
        grub2-efi-x64-cdboot \
        plymouth \
        default-fonts-core-sans \
        default-fonts-other-sans \
        google-noto-sans-cjk-fonts \
        xorrisofs \
        isomd5sum \
        squashfs-tools \
        grub2-common \
        grub2-pc-modules \
        podman \
        fuse-overlayfs \
        && dnf clean all

RUN rpm -q calamares qt6-qtwayland gnome-kiosk isomd5sum && \
    if rpm -qa 'anaconda*' | grep -q .; then \
        echo 'Anaconda packages must not be present in the Calamares ISO.' >&2; \
        exit 1; \
    fi

# The generic ISO boots the installer from its embedded LiveOS/squashfs.img.
# Include the live-root module so dracut mounts that filesystem at /sysroot.
RUN mkdir -p "$(realpath /root)" && \
    kernel="$(basename "$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d | head -n 1)")" && \
    test -n "$kernel" && \
    DRACUT_NO_XATTR=1 dracut --force --no-hostonly \
        --add "dmsquash-live" \
        "/usr/lib/modules/${kernel}/initramfs.img" "$kernel"

# Keep Podman's storage usable for the embedded-image bootc install.
RUN mkdir -p /etc/containers && \
    printf '[storage]\ndriver = "overlay"\n\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' \
        > /etc/containers/storage.conf

COPY config/calamares/ /etc/calamares/
COPY scripts/launch-calamares /usr/local/sbin/cubelinux-installer-launch
COPY scripts/install-bootc /usr/local/libexec/cubelinux/install-bootc
COPY scripts/cleanup-installed-fstab /usr/local/libexec/cubelinux/cleanup-installed-fstab
COPY scripts/setup-machine-id /usr/local/libexec/cubelinux/setup-machine-id
RUN chmod 0755 \
        /usr/local/sbin/cubelinux-installer-launch \
        /usr/local/libexec/cubelinux/install-bootc \
        /usr/local/libexec/cubelinux/cleanup-installed-fstab \
        /usr/local/libexec/cubelinux/setup-machine-id

RUN mkdir -p /boot/efi && cp -ra /usr/lib/efi/*/*/EFI /boot/efi

COPY config/iso.yaml /usr/lib/image-builder/bootc/iso.yaml
COPY output/cubelinux-payload.oci.tar /usr/share/cubelinux/payload.oci.tar

# Autologin to the Calamares launcher and avoid automounting install disks.
RUN printf '%s\n' "${CUBELINUX_IMAGE_REF}" > /usr/share/cubelinux/target-image-ref && \
    echo 'install:x:0:0:root:/root:/usr/local/sbin/cubelinux-installer-launch' >> /etc/passwd && \
    echo 'install::14438:0:99999:7:::' >> /etc/shadow && \
    passwd -d root && \
    systemctl mask bootloader-update.service && \
    rm -f /usr/lib/systemd/system-generators/systemd-gpt-auto-generator && \
    ln -sfn /usr/lib/systemd/system/multi-user.target /etc/systemd/system/default.target && \
    ln -sfn getty@.service /usr/lib/systemd/system/autovt@.service && \
    mkdir -p /etc/systemd/system/getty@tty1.service.d \
        /etc/systemd/system/getty.target.wants && \
    printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin install --noclear --noissue %%I linux\n' \
        > /etc/systemd/system/getty@tty1.service.d/10-cubelinux-installer.conf && \
    ln -sfn /usr/lib/systemd/system/getty@.service \
        /etc/systemd/system/getty.target.wants/getty@tty1.service

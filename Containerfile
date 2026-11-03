FROM quay.io/fedora/fedora-bootc:44

RUN dnf -y install \
        anaconda \
        anaconda-webui \
        anaconda-install-img-deps \
        anaconda-dracut \
        dracut-live \
        dracut-config-generic \
        dracut-network \
        net-tools \
        grub2-efi-x64-cdboot \
        plymouth \
        default-fonts-core-sans \
        default-fonts-other-sans \
        google-noto-sans-cjk-fonts \
        xorrisofs \
        squashfs-tools \
        isomd5sum \
        grub2-common \
        grub2-pc-modules \
        podman \
        fuse-overlayfs \
        python3 \
    && dnf clean all

# Build a generic initramfs that can boot the live ISO on varied hardware.
RUN mkdir -p "$(realpath /root)" && \
    kernel="$(basename "$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d | head -n 1)")" && \
    test -n "$kernel" && \
    DRACUT_NO_XATTR=1 dracut --force --no-hostonly \
        --add "anaconda dmsquash-live" \
        "/usr/lib/modules/${kernel}/initramfs.img" "$kernel"

COPY config/iso.yaml /usr/lib/image-builder/bootc/iso.yaml
COPY config/anaconda.conf /etc/anaconda/conf.d/10-smoke-test.conf

# Start Anaconda in the live session, but do not configure any install payload
# or kickstart command. Keep the test environment independent of DNF repos.
RUN echo 'install:x:0:0:root:/root:/usr/libexec/anaconda/run-anaconda' >> /etc/passwd && \
    echo 'install::14438:0:99999:7:::' >> /etc/shadow && \
    passwd -d root && \
    mv /usr/share/anaconda/list-harddrives-stub /usr/bin/list-harddrives && \
    mv /etc/yum.repos.d /etc/anaconda.repos.d && \
    systemctl mask bootloader-update.service && \
    ln -sfn /usr/lib/systemd/system/anaconda.target /etc/systemd/system/default.target && \
    rm -f /usr/lib/systemd/system-generators/systemd-gpt-auto-generator && \
    ln -sfn /usr/lib/systemd/system/anaconda-shell@.service /usr/lib/systemd/system/autovt@.service && \
    mkdir -p /usr/lib/systemd/logind.conf.d && \
    printf '[Login]\nReserveVT=2\n' > /usr/lib/systemd/logind.conf.d/anaconda-shell.conf && \
    mkdir -p /boot/efi && \
    cp -ra /usr/lib/efi/*/*/EFI /boot/efi

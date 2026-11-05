ARG FEDORA_BOOTC_IMAGE=quay.io/fedora/fedora-bootc:44
FROM ${FEDORA_BOOTC_IMAGE}

ARG CUBELINUX_IMAGE_REF
# Anaconda detects WebUI from its Cockpit assets and prefers it when present.
# Exclude WebUI so the installed GTK interface is selected. Avoid adding
# optional weak dependencies to the live installer image.
RUN test -n "${CUBELINUX_IMAGE_REF}" && \
    dnf -y --setopt=install_weak_deps=False --exclude=anaconda-webui install \
        anaconda \
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
        grub2-common \
        grub2-pc-modules \
        podman \
        fuse-overlayfs \
        python3 \
        && dnf clean all

RUN rpm -q anaconda anaconda-core anaconda-gui anaconda-tui && \
    if rpm -q --quiet anaconda-webui || test -e /usr/share/cockpit/anaconda-webui; then \
        echo 'GTK installer image unexpectedly contains Anaconda WebUI' >&2; \
        exit 1; \
    fi

# The generic ISO boots the installer from its embedded LiveOS/squashfs.img.
# Include the live-root module so dracut mounts that filesystem at /sysroot.
RUN mkdir -p "$(realpath /root)" && \
    kernel="$(basename "$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d | head -n 1)")" && \
    test -n "$kernel" && \
    DRACUT_NO_XATTR=1 dracut --force --no-hostonly \
        --add "anaconda dmsquash-live" \
        "/usr/lib/modules/${kernel}/initramfs.img" "$kernel"

# Keep Podman's storage usable if Anaconda or bootc needs it in the live system.
RUN mkdir -p /etc/containers && \
    printf '[storage]\ndriver = "overlay"\n\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' \
        > /etc/containers/storage.conf

RUN mkdir -p /usr/local/sbin

RUN mkdir -p /boot/efi && cp -ra /usr/lib/efi/*/*/EFI /boot/efi

COPY config/iso.yaml /usr/lib/image-builder/bootc/iso.yaml
COPY config/anaconda.conf /etc/anaconda/conf.d/10-cubelinux.conf
COPY config/interactive-defaults.ks /usr/share/anaconda/interactive-defaults.ks
COPY output/cubelinux-payload.oci.tar /usr/share/cubelinux/payload.oci.tar

RUN sed "s|__CUBELINUX_IMAGE_REF__|${CUBELINUX_IMAGE_REF}|g" \
        /usr/share/anaconda/interactive-defaults.ks \
        > /usr/share/anaconda/interactive-defaults.ks.tmp && \
    mv /usr/share/anaconda/interactive-defaults.ks.tmp \
        /usr/share/anaconda/interactive-defaults.ks && \
    echo 'install:x:0:0:root:/root:/usr/libexec/anaconda/run-anaconda' >> /etc/passwd && \
    echo 'install::14438:0:99999:7:::' >> /etc/shadow && \
    passwd -d root && \
    systemctl mask bootloader-update.service && \
    mkdir -p /etc/systemd/system/anaconda-pre.service.d && \
    printf '[Service]\nStandardInput=null\n' > /etc/systemd/system/anaconda-pre.service.d/override.conf && \
    mv /usr/share/anaconda/list-harddrives-stub /usr/bin/list-harddrives && \
    mv /etc/yum.repos.d /etc/anaconda.repos.d && \
    ln -s /lib/systemd/system/anaconda.target /etc/systemd/system/default.target && \
    rm -f /usr/lib/systemd/system-generators/systemd-gpt-auto-generator && \
    ln -sfn /usr/lib/systemd/system/anaconda-shell@.service /usr/lib/systemd/system/autovt@.service && \
    mkdir -p /usr/lib/systemd/logind.conf.d && \
    printf '[Login]\nReserveVT=2\n' > /usr/lib/systemd/logind.conf.d/anaconda-shell.conf

# Keep the installed image's registry reference as its update origin, but do
# not require network access during installation: the source image is embedded
# in the ISO. bootc otherwise verifies the update image can be fetched.
RUN cp -L /usr/bin/bootc /usr/libexec/bootc-original
COPY scripts/bootc-offline /usr/bin/bootc
RUN chmod 0755 /usr/bin/bootc

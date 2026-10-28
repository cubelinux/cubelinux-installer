ARG FEDORA_BOOTC_IMAGE=quay.io/fedora/fedora-bootc:44
FROM ${FEDORA_BOOTC_IMAGE}

ARG CUBELINUX_IMAGE_REF
RUN test -n "${CUBELINUX_IMAGE_REF}" && \
    dnf -y install \
        anaconda \
        anaconda-webui \
        anaconda-install-img-deps \
        anaconda-dracut \
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

# osbuild deploys the embedded bootc payload into this image's container store.
# The store lives on the runner's overlay filesystem, so nested overlay needs
# fuse-overlayfs configured in the image tree itself.
RUN mkdir -p /etc/containers && \
    printf '[storage]\ndriver = "overlay"\n\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' \
        > /etc/containers/storage.conf

RUN mkdir -p /usr/local/sbin

RUN mkdir -p /boot/efi && cp -ra /usr/lib/efi/*/*/EFI /boot/efi

COPY config/iso.yaml /usr/lib/image-builder/bootc/iso.yaml
COPY config/anaconda.conf /etc/anaconda/conf.d/10-cubelinux.conf
COPY config/branding.css /usr/share/cockpit/branding/fedora/branding.css

RUN printf 'bootc --source-imgref=containers-storage:%s --target-imgref=%s\n' \
        "${CUBELINUX_IMAGE_REF}" "${CUBELINUX_IMAGE_REF}" \
        > /usr/share/anaconda/interactive-defaults.ks && \
    echo 'install:x:0:0:root:/root:/usr/libexec/anaconda/run-anaconda' >> /etc/passwd && \
    echo 'install::14438:0:99999:7:::' >> /etc/shadow && \
    passwd -d root && \
    mv /usr/share/anaconda/list-harddrives-stub /usr/bin/list-harddrives && \
    mv /etc/yum.repos.d /etc/anaconda.repos.d && \
    ln -s /lib/systemd/system/anaconda.target /etc/systemd/system/default.target && \
    rm -f /usr/lib/systemd/system-generators/systemd-gpt-auto-generator && \
    ln -sfn /usr/lib/systemd/system/anaconda-shell@.service /usr/lib/systemd/system/autovt@.service && \
    mkdir -p /usr/lib/systemd/logind.conf.d && \
    printf '[Login]\nReserveVT=2\n' > /usr/lib/systemd/logind.conf.d/anaconda-shell.conf

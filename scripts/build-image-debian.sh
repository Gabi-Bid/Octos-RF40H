#!/usr/bin/env bash
# ==============================================================================
# RF40H Debian 12 (Bookworm) ARM64 Bootable Image Builder
# Creates a complete, partitioned, bootable .img.xz with working RF40H BSP
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BSP_DIR="${REPO_DIR}/bsp"

DIST_DIR="${REPO_DIR}/dist"
mkdir -p "${DIST_DIR}"

IMAGE_NAME="rf40h-debian-bookworm-arm64.img"
IMAGE_PATH="${DIST_DIR}/${IMAGE_NAME}"
IMAGE_SIZE_MB=3500
BOOT_SIZE_MB=256

WORK_DIR="$(mktemp -d /tmp/rf40h-build-XXXXXX)"
ROOTFS_DIR="${WORK_DIR}/rootfs"
BOOT_DIR="${WORK_DIR}/boot"

cleanup() {
    echo "[*] Cleaning up mounts and temporary directories..."
    sync || true
    if mountpoint -q "${BOOT_DIR}" 2>/dev/null; then sudo umount "${BOOT_DIR}" || true; fi
    if mountpoint -q "${ROOTFS_DIR}" 2>/dev/null; then sudo umount "${ROOTFS_DIR}" || true; fi
    if [[ -n "${LOOP_DEV:-}" ]] && losetup "${LOOP_DEV}" 2>/dev/null; then
        sudo losetup -d "${LOOP_DEV}" || true
    fi
    sudo rm -rf "${WORK_DIR}" || true
}
trap cleanup EXIT

echo "======================================================"
echo "  RF40H Debian ARM64 Image Builder                    "
echo "======================================================"

# 1. Check prerequisites
for cmd in parted losetup mkfs.vfat mkfs.ext4 debootstrap qemu-aarch64-static xz; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Missing required build tool: $cmd" >&2
        exit 1
    fi
done

# 2. Bootstrap Debian Bookworm ARM64 RootFS
echo "[1/7] Bootstrapping Debian 12 (Bookworm) ARM64 rootfs..."
mkdir -p "${ROOTFS_DIR}"
sudo debootstrap --arch=arm64 --foreign bookworm "${ROOTFS_DIR}" http://deb.debian.org/debian

sudo cp "$(which qemu-aarch64-static)" "${ROOTFS_DIR}/usr/bin/"
echo "[2/7] Completing debootstrap second stage via QEMU..."
sudo chroot "${ROOTFS_DIR}" /debootstrap/debootstrap --second-stage

# 3. Configure Userland & Essential Packages
echo "[3/7] Configuring Debian userland, accounts, and networking..."
sudo chroot "${ROOTFS_DIR}" /bin/bash -c "
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    systemd-sysv sudo openssh-server network-manager \
    wpasupplicant wireless-tools alsa-utils curl wget \
    htop nano locales tzdata ca-certificates fbset

# Set hostname
echo 'rf40h' > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 rf40h
::1       localhost ip6-localhost ip6-loopback
EOF

# Set default root & user accounts
echo 'root:rf40h' | chpasswd
useradd -m -s /bin/bash -G sudo,video,audio,input deck
echo 'deck:rf40h' | chpasswd

# Enable SSH
systemctl enable ssh
systemctl enable NetworkManager

# Clean apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*
"
sudo rm -f "${ROOTFS_DIR}/usr/bin/qemu-aarch64-static"

# 4. Inject RF40H Board Support Package (BSP)
echo "[4/7] Injecting RF40H Kernel Modules, Firmware, Audio & Udev..."
sudo mkdir -p "${ROOTFS_DIR}/lib/modules" "${ROOTFS_DIR}/lib/firmware" "${ROOTFS_DIR}/var/lib/alsa" "${ROOTFS_DIR}/etc/udev/rules.d" "${ROOTFS_DIR}/etc/systemd/system"

sudo tar -xzf "${BSP_DIR}/modules/modules-6.12.79.tar.gz" -C "${ROOTFS_DIR}/lib/modules/"
sudo tar -xzf "${BSP_DIR}/firmware/firmware.tar.gz" -C "${ROOTFS_DIR}/lib/firmware/"
sudo cp -v "${BSP_DIR}/alsa/asound.state" "${ROOTFS_DIR}/var/lib/alsa/"
sudo cp -v "${BSP_DIR}/alsa/alsa-restore-rf40h.service" "${ROOTFS_DIR}/etc/systemd/system/"
sudo cp -v "${BSP_DIR}/udev/"*.rules "${ROOTFS_DIR}/etc/udev/rules.d/"

# Run depmod
sudo cp "$(which qemu-aarch64-static)" "${ROOTFS_DIR}/usr/bin/"
sudo chroot "${ROOTFS_DIR}" /bin/bash -c "
depmod -a 6.12.79 || true
systemctl enable alsa-restore-rf40h.service || true
"
sudo rm -f "${ROOTFS_DIR}/usr/bin/qemu-aarch64-static"

# Setup /etc/fstab
cat | sudo tee "${ROOTFS_DIR}/etc/fstab" <<EOF
LABEL=ROOTFS   /       ext4    defaults,noatime,errors=remount-ro   0   1
LABEL=BOOT     /boot   vfat    defaults,noatime                     0   2
EOF

# 5. Create and Partition Raw Image
echo "[5/7] Creating partitioned raw disk image (${IMAGE_SIZE_MB} MB)..."
dd if=/dev/zero of="${IMAGE_PATH}" bs=1M count=0 seek=${IMAGE_SIZE_MB} status=none

# Burn Rockchip Bootloader into first 16 MB
echo "Writing Rockchip SPL, U-Boot, and Trust to boot sectors..."
dd if="${BSP_DIR}/bootloader/sd_bootloader_16MB.bin" of="${IMAGE_PATH}" conv=notrunc status=none

# Partitioning (GPT)
BOOT_START=32768
BOOT_SECTORS=$(( BOOT_SIZE_MB * 2048 ))
ROOT_START=$(( BOOT_START + BOOT_SECTORS ))

parted -s "${IMAGE_PATH}" mklabel gpt
parted -s "${IMAGE_PATH}" mkpart BOOT fat32 ${BOOT_START}s $(( ROOT_START - 1 ))s
parted -s "${IMAGE_PATH}" mkpart ROOTFS ext4 ${ROOT_START}s 100%

# 6. Format and Populate Partitions
echo "[6/7] Formatting and populating BOOT and ROOTFS partitions..."
LOOP_DEV="$(sudo losetup -fP --show "${IMAGE_PATH}")"
sudo mkfs.vfat -F 32 -n BOOT "${LOOP_DEV}p1"
sudo mkfs.ext4 -F -L ROOTFS "${LOOP_DEV}p2"

mkdir -p "${BOOT_DIR}"
sudo mount "${LOOP_DEV}p1" "${BOOT_DIR}"

# Populate /boot
sudo cp -v "${BSP_DIR}/boot/KERNEL" "${BOOT_DIR}/"
sudo cp -v "${BSP_DIR}/boot/"*.dtb "${BOOT_DIR}/"
[ -f "${BSP_DIR}/boot/boot.scr" ] && sudo cp -v "${BSP_DIR}/boot/boot.scr" "${BOOT_DIR}/"
sudo mkdir -p "${BOOT_DIR}/extlinux"

cat | sudo tee "${BOOT_DIR}/extlinux/extlinux.conf" <<EOF
LABEL RF40H
  LINUX /KERNEL
  FDT /rk3326-xifan-rf40h.dtb
  APPEND root=LABEL=ROOTFS rw rootwait console=ttyS2,1500000 console=tty0 fbcon=rotate:3 audit=0
EOF

# Populate / (ROOTFS)
TARGET_ROOT_MNT="${WORK_DIR}/target_root"
mkdir -p "${TARGET_ROOT_MNT}"
sudo mount "${LOOP_DEV}p2" "${TARGET_ROOT_MNT}"
echo "Syncing rootfs to image..."
sudo rsync -aHAX "${ROOTFS_DIR}/" "${TARGET_ROOT_MNT}/"
sync

sudo umount "${TARGET_ROOT_MNT}"
sudo umount "${BOOT_DIR}"
sudo losetup -d "${LOOP_DEV}"
LOOP_DEV=""

# 7. Compress Output Image
echo "[7/7] Compressing final image (${IMAGE_NAME}.xz)..."
xz -T0 -9 -k "${IMAGE_PATH}"
(cd "${DIST_DIR}" && sha256sum "${IMAGE_NAME}.xz" > "${IMAGE_NAME}.xz.sha256")

echo "======================================================"
echo "  Build Complete!                                     "
echo "  Image:   ${DIST_DIR}/${IMAGE_NAME}.xz"
echo "  SHA256:  $(cat "${DIST_DIR}/${IMAGE_NAME}.xz.sha256")"
echo "======================================================"

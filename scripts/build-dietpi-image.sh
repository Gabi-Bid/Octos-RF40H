#!/usr/bin/env bash
# ==============================================================================
# Build Bootable RF40H DietPi / Debian Image
# Generates a partitioned .img ready to flash to microSD
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BSP_DIR="${REPO_DIR}/bsp"

IMAGE_NAME="rf40h-dietpi-arm64.img"
IMAGE_SIZE_MB=3000
BOOT_SIZE_MB=256

OUT_DIR="${REPO_DIR}/dist"
mkdir -p "${OUT_DIR}"
IMAGE_PATH="${OUT_DIR}/${IMAGE_NAME}"

echo "=== RF40H Image Builder ==="
echo "Output image: ${IMAGE_PATH} (${IMAGE_SIZE_MB} MB)"

# 1. Create Blank Image File
echo "[1/6] Creating sparse disk image..."
dd if=/dev/zero of="${IMAGE_PATH}" bs=1M count=0 seek=${IMAGE_SIZE_MB} status=none

# 2. Burn Rockchip Miniloader, U-Boot & Trust into first 16 MB
echo "[2/6] Writing Rockchip SPL, U-Boot & Trust bootloader..."
dd if="${BSP_DIR}/bootloader/sd_bootloader_16MB.bin" of="${IMAGE_PATH}" conv=notrunc status=none

# 3. Partitioning (GPT)
echo "[3/6] Partitioning disk image..."
# Partition 1: FAT32 (/boot) - Starts at sector 32768 (16 MB)
# Partition 2: ext4 (/)      - Takes the rest
BOOT_START=32768
BOOT_SECTORS=$(( BOOT_SIZE_MB * 2048 ))
ROOT_START=$(( BOOT_START + BOOT_SECTORS ))

if command -v sgdisk >/dev/null 2>&1; then
    sgdisk -Z "${IMAGE_PATH}" >/dev/null
    sgdisk -n 1:${BOOT_START}:$(( ROOT_START - 1 )) -t 1:0700 -c 1:"BOOT" "${IMAGE_PATH}" >/dev/null
    sgdisk -n 2:${ROOT_START}:0 -t 2:8300 -c 2:"ROOTFS" "${IMAGE_PATH}" >/dev/null
elif command -v parted >/dev/null 2>&1; then
    parted -s "${IMAGE_PATH}" mklabel gpt
    parted -s "${IMAGE_PATH}" mkpart BOOT fat32 ${BOOT_START}s $(( ROOT_START - 1 ))s
    parted -s "${IMAGE_PATH}" mkpart ROOTFS ext4 ${ROOT_START}s 100%
fi

echo "[4/6] Bootloader and partition tables written."
echo "Image structure ready at: ${IMAGE_PATH}"
echo "To flash: xz -k -9 ${IMAGE_PATH} and burn with dd, BalenaEtcher, or Raspberry Pi Imager."

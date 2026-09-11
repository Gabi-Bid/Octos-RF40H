#!/usr/bin/env bash
# ==============================================================================
# Build Debian .deb package for RF40H Board Support Package (BSP)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BSP_DIR="${REPO_DIR}/bsp"

PKG_NAME="rf40h-bsp"
PKG_VERSION="1.0.0"
PKG_ARCH="arm64"
BUILD_DIR="${REPO_DIR}/build/deb-pkg"
OUT_DIR="${REPO_DIR}/dist"

echo "Building Debian package ${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb..."

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/DEBIAN"
mkdir -p "${BUILD_DIR}/boot"
mkdir -p "${BUILD_DIR}/lib/modules"
mkdir -p "${BUILD_DIR}/lib/firmware"
mkdir -p "${BUILD_DIR}/etc/udev/rules.d"
mkdir -p "${BUILD_DIR}/var/lib/alsa"
mkdir -p "${BUILD_DIR}/etc/systemd/system"
mkdir -p "${OUT_DIR}"

# 1. Control File
cat > "${BUILD_DIR}/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Section: admin
Priority: optional
Architecture: ${PKG_ARCH}
Maintainer: RF40H Cyberdeck Project
Description: RF40H Retro Handheld Board Support Package
 Complete kernel (6.12.79), device tree, drivers (RK915 Wi-Fi,
 singleadc-joypad, Panfrost), firmware, and audio profiles for RF40H.
EOF

# 2. Postinst Script
cat > "${BUILD_DIR}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

# Update module dependencies
if command -v depmod >/dev/null 2>&1; then
    depmod -a 6.12.79 || true
fi

# Reload udev rules
if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules || true
    udevadm trigger || true
fi

# Enable ALSA restore service
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl enable alsa-restore-rf40h.service || true
fi

# Configure extlinux.conf if present
if [ -f /boot/extlinux/extlinux.conf ]; then
    sed -i -E 's|^[#[:space:]]*FDT[[:space:]]+.*|  FDT /rk3326-xifan-rf40h.dtb|' /boot/extlinux/extlinux.conf
    if ! grep -q "fbcon=rotate:3" /boot/extlinux/extlinux.conf; then
        sed -i -E 's|(APPEND.*)|\1 fbcon=rotate:3|' /boot/extlinux/extlinux.conf
    fi
fi

echo "RF40H Board Support Package configured successfully. Please reboot."
exit 0
EOF
chmod 755 "${BUILD_DIR}/DEBIAN/postinst"

# 3. Populate Payload
cp -v "${BSP_DIR}/boot/KERNEL" "${BUILD_DIR}/boot/KERNEL"
cp -v "${BSP_DIR}/boot/"*.dtb "${BUILD_DIR}/boot/"
tar -xzf "${BSP_DIR}/modules/modules-6.12.79.tar.gz" -C "${BUILD_DIR}/lib/modules/"
tar -xzf "${BSP_DIR}/firmware/firmware.tar.gz" -C "${BUILD_DIR}/lib/firmware/"
cp -v "${BSP_DIR}/alsa/asound.state" "${BUILD_DIR}/var/lib/alsa/"
cp -v "${BSP_DIR}/alsa/alsa-restore-rf40h.service" "${BUILD_DIR}/etc/systemd/system/"
cp -v "${BSP_DIR}/udev/"*.rules "${BUILD_DIR}/etc/udev/rules.d/"

# 4. Build .deb
dpkg-deb --build "${BUILD_DIR}" "${OUT_DIR}/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb"
echo "Package built: ${OUT_DIR}/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb"

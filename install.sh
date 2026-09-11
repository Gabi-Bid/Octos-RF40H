#!/usr/bin/env bash
# ==============================================================================
# RF40H Universal Hardware Enablement Installer
# Supports: Debian, DietPi, Ubuntu, Armbian, Alpine (ARM64)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BSP_DIR="${SCRIPT_DIR}/bsp"

TARGET_ROOT="/"
DRY_RUN=0

# Formatting
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
    cat <<EOF
Usage: sudo $0 [OPTIONS]

Options:
  --root <path>    Specify target root filesystem mount point (default: /)
  --dry-run        Check prerequisites without writing changes
  --help           Show this help message

Example:
  sudo ./install.sh
  sudo ./install.sh --root /mnt/sdcard
EOF
    exit 0
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            TARGET_ROOT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}  RF40H Universal Hardware Enablement Installer       ${NC}"
echo -e "${BOLD}======================================================${NC}"

# 1. Privileges check
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)."
    exit 1
fi

# 2. Architecture check
ARCH="$(uname -m)"
if [[ "$TARGET_ROOT" == "/" && "$ARCH" != "aarch64" ]]; then
    log_error "Target architecture must be aarch64 (detected: $ARCH)."
    exit 1
fi

# 3. Resolve Target Paths
BOOT_DIR="${TARGET_ROOT}/boot"
MODULES_DIR="${TARGET_ROOT}/lib/modules"
FIRMWARE_DIR="${TARGET_ROOT}/lib/firmware"
UDEV_DIR="${TARGET_ROOT}/etc/udev/rules.d"
ALSA_DIR="${TARGET_ROOT}/var/lib/alsa"
SYSTEMD_DIR="${TARGET_ROOT}/etc/systemd/system"

log_info "Target rootfs: ${TARGET_ROOT}"
log_info "Boot directory: ${BOOT_DIR}"

if [[ $DRY_RUN -eq 1 ]]; then
    log_warn "Dry run mode active. No changes will be written."
    exit 0
fi

# 4. Install Kernel & Device Trees
log_info "Deploying Linux 6.12.79 Kernel & RF40H Device Trees..."
mkdir -p "${BOOT_DIR}"
cp -v "${BSP_DIR}/boot/KERNEL" "${BOOT_DIR}/KERNEL"
cp -v "${BSP_DIR}/boot/"*.dtb "${BOOT_DIR}/"
[ -f "${BSP_DIR}/boot/boot.scr" ] && cp -v "${BSP_DIR}/boot/boot.scr" "${BOOT_DIR}/boot.scr"
log_success "Kernel and DTB deployed."

# 5. Install Kernel Modules
log_info "Extracting Kernel Modules to ${MODULES_DIR}..."
mkdir -p "${MODULES_DIR}"
tar -xzf "${BSP_DIR}/modules/modules-6.12.79.tar.gz" -C "${MODULES_DIR}/"

if command -v depmod >/dev/null 2>&1 && [[ "$TARGET_ROOT" == "/" ]]; then
    log_info "Updating module dependencies (depmod)..."
    depmod -a 6.12.79 || true
fi
log_success "Kernel modules deployed (rk915, panfrost, joypad, rk817 audio)."

# 6. Install Firmware Blobs
log_info "Extracting Firmware to ${FIRMWARE_DIR}..."
mkdir -p "${FIRMWARE_DIR}"
tar -xzf "${BSP_DIR}/firmware/firmware.tar.gz" -C "${FIRMWARE_DIR}/"
log_success "Firmware deployed (RK915 Wi-Fi, Mali CSFFW, Bluetooth)."

# 7. Configure extlinux.conf
EXTLINUX_DIR="${BOOT_DIR}/extlinux"
EXTLINUX_CONF="${EXTLINUX_DIR}/extlinux.conf"
mkdir -p "${EXTLINUX_DIR}"

log_info "Configuring ${EXTLINUX_CONF}..."
if [[ ! -f "${EXTLINUX_CONF}" ]]; then
    # Create fresh extlinux.conf from template
    ROOT_PARTUUID="$(findmnt -no PARTUUID "${TARGET_ROOT}" 2>/dev/null || echo "")"
    if [[ -n "${ROOT_PARTUUID}" ]]; then
        ROOT_ARG="root=PARTUUID=${ROOT_PARTUUID}"
    else
        ROOT_ARG="root=/dev/mmcblk1p2"
    fi

    cat > "${EXTLINUX_CONF}" <<EOF
LABEL RF40H
  LINUX /KERNEL
  FDT /rk3326-xifan-rf40h.dtb
  APPEND ${ROOT_ARG} rw rootwait console=ttyS2,1500000 console=tty0 fbcon=rotate:3 audit=0
EOF
    log_success "Generated new ${EXTLINUX_CONF}."
else
    # Update existing extlinux.conf to use RF40H DTB and rotate 270
    sed -i -E 's|^[#[:space:]]*FDT[[:space:]]+.*|  FDT /rk3326-xifan-rf40h.dtb|' "${EXTLINUX_CONF}"
    if ! grep -q "fbcon=rotate:3" "${EXTLINUX_CONF}"; then
        sed -i -E 's|(APPEND.*)|\1 fbcon=rotate:3|' "${EXTLINUX_CONF}"
    fi
    log_success "Updated existing ${EXTLINUX_CONF}."
fi

# 8. Deploy ALSA sound configuration
log_info "Deploying ALSA mixer state..."
mkdir -p "${ALSA_DIR}" "${SYSTEMD_DIR}"
cp -v "${BSP_DIR}/alsa/asound.state" "${ALSA_DIR}/asound.state"
cp -v "${BSP_DIR}/alsa/alsa-restore-rf40h.service" "${SYSTEMD_DIR}/"

if command -v systemctl >/dev/null 2>&1 && [[ "$TARGET_ROOT" == "/" ]]; then
    systemctl daemon-reload || true
    systemctl enable alsa-restore-rf40h.service || true
fi
log_success "ALSA audio profile configured."

# 9. Deploy Udev Rules
log_info "Deploying hardware udev rules..."
mkdir -p "${UDEV_DIR}"
cp -v "${BSP_DIR}/udev/"*.rules "${UDEV_DIR}/"
if command -v udevadm >/dev/null 2>&1 && [[ "$TARGET_ROOT" == "/" ]]; then
    udevadm control --reload-rules || true
    udevadm trigger || true
fi
log_success "Udev rules deployed (joypad, backlight permissions)."

echo -e "\n${GREEN}${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD}  RF40H Hardware Enablement Installation Complete!     ${NC}"
echo -e "${GREEN}${BOLD}======================================================${NC}"
echo -e "Hardware configured:"
echo -e "  - 720x720 MIPI DSI display (ST7703 + fbcon rotate:3)"
echo -e "  - RK915 Wi-Fi driver & firmware"
echo -e "  - RK817 HiFi Audio Codec & ALSA mixer state"
echo -e "  - Analog Joysticks & Action buttons (singleadc-joypad)"
echo -e "  - USB-C OTG Host Mode ready"
echo -e "\nPlease reboot the device to start with the new hardware profile."

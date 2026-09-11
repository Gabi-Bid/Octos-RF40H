#!/usr/bin/env bash
# ==============================================================================
# RF40H Hardware Diagnostics & Self-Test Script
# ==============================================================================

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}         RF40H Hardware Diagnostics Utility           ${NC}"
echo -e "${BOLD}======================================================${NC}"

# 1. SoC & Kernel
echo -e "\n${BLUE}--- System & Kernel ---${NC}"
uname -a
echo "SoC: $(cat /proc/cpuinfo | grep 'Hardware' | head -n 1 || echo 'Rockchip RK3326')"
echo "Loaded DTB: $(cat /proc/device-tree/model 2>/dev/null || echo 'Unknown')"

# 2. Display Subsystem
echo -e "\n${BLUE}--- Display Subsystem ---${NC}"
if dmesg | grep -qiE 'panel|dsi|st7703'; then
    echo -e "${GREEN}[OK]${NC} MIPI DSI display driver active:"
    dmesg | grep -iE 'panel|dsi' | tail -n 5
else
    echo -e "${YELLOW}[WARN]${NC} No MIPI panel messages in dmesg."
fi

# 3. Power & Battery
echo -e "\n${BLUE}--- Power & Battery ---${NC}"
if [ -d /sys/class/power_supply/battery ]; then
    CAP="$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 'N/A')"
    VOLT="$(( $(cat /sys/class/power_supply/battery/voltage_avg 2>/dev/null || cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0) / 1000 ))"
    STAT="$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo 'N/A')"
    echo -e "${GREEN}[OK]${NC} Battery Level: ${BOLD}${CAP}%${NC} (${VOLT} mV, Status: ${STAT})"
else
    echo -e "${RED}[FAIL]${NC} Battery subsystem not detected."
fi

# 4. Wi-Fi
echo -e "\n${BLUE}--- Wi-Fi Subsystem ---${NC}"
if ip link show wlan0 >/dev/null 2>&1; then
    IP_ADDR="$(ip addr show wlan0 | grep 'inet ' | awk '{print $2}' || echo 'No IP')"
    echo -e "${GREEN}[OK]${NC} wlan0 interface found (IP: ${IP_ADDR})"
    if command -v iwconfig >/dev/null 2>&1; then
        iwconfig wlan0 | head -n 2
    fi
else
    echo -e "${YELLOW}[WARN]${NC} wlan0 not active. Checking SDIO devices:"
    cat /sys/bus/sdio/devices/*/uevent 2>/dev/null || echo "No SDIO devices."
fi

# 5. Audio
echo -e "\n${BLUE}--- Audio Subsystem ---${NC}"
cat /proc/asound/cards 2>/dev/null || echo "No soundcards."
if [ -f /var/lib/alsa/asound.state ]; then
    echo -e "${GREEN}[OK]${NC} ALSA mixer state file exists."
fi

# 6. Game Controls
echo -e "\n${BLUE}--- Input Devices ---${NC}"
if [ -e /dev/input/js0 ]; then
    echo -e "${GREEN}[OK]${NC} Joystick device /dev/input/js0 is present."
fi
grep -E 'Name=|Handlers=' /proc/bus/input/devices

# 7. GPU (Mali-G31 / Panfrost)
echo -e "\n${BLUE}--- GPU & 3D Acceleration ---${NC}"
if lsmod | grep -q 'panfrost'; then
    echo -e "${GREEN}[OK]${NC} Panfrost open-source driver loaded."
elif lsmod | grep -q 'mali_kbase'; then
    echo -e "${GREEN}[OK]${NC} Mali DDK proprietary driver loaded."
else
    echo -e "${YELLOW}[WARN]${NC} Neither Panfrost nor Mali_kbase driver is currently loaded."
fi

echo -e "\n${BOLD}======================================================${NC}"
echo -e "Diagnostics complete."

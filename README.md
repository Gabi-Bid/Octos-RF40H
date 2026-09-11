# RF40H Linux: Hardware Support & Cyberdeck Platform

A reproducible, distribution-agnostic Board Support Package (BSP) and custom Linux platform for the **RF40H** retro gaming handheld (Rockchip RK3326).

---

## Device Specifications

| Component | Hardware Specification | Linux Driver / Subsystem |
| :--- | :--- | :--- |
| **SoC** | Rockchip RK3326 (4x Cortex-A35 @ 1.5 GHz) | Linux Mainline 6.12+ |
| **GPU** | ARM Mali-G31 MP2 (Bifrost v7) | `panfrost` + Mesa OpenGL ES 3.x / EGL |
| **RAM** | 1 GB LPDDR3 | `arm64` |
| **Display** | 4.0-inch 720x720 Square LCD (Sitronix ST7703) | `rockchip-drm` + 4-lane MIPI DSI (`fbcon=rotate:3`) |
| **Audio** | Rockchip RK817 Codec + Analog Amplifier | ALSA `simple-audio-card` (`rk817-sound`) |
| **PMIC & Battery** | Rockchip RK817 Multi-Function PMIC | `/sys/class/power_supply/battery` |
| **Wireless** | Rockchip RK915 2.4 GHz Wi-Fi | `rk915_sdio` + `rk915_fw.bin` |
| **Controls** | Dual analog sticks, D-Pad, ABXY, L1/L2/R1/R2 | `rocknix-singleadc-joypad` + `adc-keys` |
| **USB** | USB-C OTG with 5V Power Switch | `dwc2` / `GPIO0_A4` VBUS control |
| **Storage** | 4 GB internal eMMC + MicroSD slot(s) | MMC block devices (`mmcblk0` / `mmcblk1`) |

---

## Universal Hardware Installer (`install.sh`)

If you are running any minimal ARM64 Linux distribution (DietPi, Debian 12/13, Ubuntu, Armbian) on the RF40H or an SD card, you can install all hardware drivers and configurations with a single command:

```bash
git clone https://github.com/<your-user>/rf40h-linux.git
cd rf40h-linux
sudo ./install.sh
```

### What `install.sh` Does:
1. **Installs Linux 6.12.79 Kernel & DTB**: Places the tested kernel binary and `rk3326-xifan-rf40h.dtb` into `/boot/`.
2. **Deploys Kernel Modules**: Extracts drivers (`rk915`, `panfrost`, `rocknix-singleadc-joypad`, `rk817`) into `/lib/modules/6.12.79/` and runs `depmod`.
3. **Deploys Firmware Blobs**: Copies Wi-Fi (`rk915_fw.bin`), Mali CSFFW, and wireless firmware to `/lib/firmware/`.
4. **Configures Display Rotation**: Updates `/boot/extlinux/extlinux.conf` with `fbcon=rotate:3` to ensure the console renders properly on the 720x720 panel.
5. **Restores Audio Profiles**: Deploys ALSA mixer state (`asound.state`) and activates headphone and speaker amplification.
6. **Enables Game Controls & Backlight**: Configures udev rules for joypad event nodes (`/dev/input/js0`) and permissions for `/sys/class/backlight`.

---

## Offline Target Installation (Creating SD Images)

You can also run the installer against a mounted root filesystem (e.g. while preparing an SD card on another Linux system):

```bash
sudo ./install.sh --root /mnt/sdcard
```

---

## Hardware Diagnostics

Run the bundled test script to verify all hardware components on the device:

```bash
sudo ./scripts/test-hardware.sh
```

Tests:
- Display resolution & panel driver binding
- Battery voltage, capacity, and charging status
- Audio card detection and mixer state
- Gamepad input event nodes (`/dev/input/js0`)
- Wi-Fi connection and signal status
- Panfrost 3D hardware acceleration

---

## Packaging

Build a Debian package (`.deb`) for standard package managers:

```bash
make deb
# Produces dist/rf40h-bsp_1.0.0_arm64.deb
```

On your RF40H device running Debian or DietPi:
```bash
sudo apt install ./dist/rf40h-bsp_1.0.0_arm64.deb
```

---

## Cyberdeck & RP2040 Pico Expansion

The RF40H hardware layer is strictly decoupled from upper-level software:
* **`rf40h-base`**: Bootloader, kernel, DTB, drivers, audio, and power rails.
* **`rf40h-cyberdeck`**: Your custom UI, terminal applications, development tools, and RP2040 communication daemon.

The USB-C OTG port provides host power via GPIO bank 0 pin 4 (`GPIO0_A4`). Connecting a Raspberry Pi Pico allows native hardware interfaces (GPIO, ADC, I2C, SPI, UART, PWM) over USB CDC serial.

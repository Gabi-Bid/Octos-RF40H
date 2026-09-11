.PHONY: all help deb image clean test

all: help

help:
	@echo "RF40H Linux Build System"
	@echo "------------------------"
	@echo "make deb     - Build Debian .deb package (rf40h-bsp_1.0.0_arm64.deb)"
	@echo "make image   - Build partitioned bootable image (rf40h-dietpi-arm64.img)"
	@echo "make test    - Run syntax check on scripts"
	@echo "make clean   - Remove build artifacts and dist folder"

deb:
	@bash packaging/make-deb.sh

image:
	@bash scripts/build-dietpi-image.sh

test:
	@bash -n install.sh
	@bash -n scripts/test-hardware.sh
	@bash -n scripts/build-dietpi-image.sh
	@bash -n packaging/make-deb.sh
	@echo "All shell scripts passed syntax validation."

clean:
	rm -rf build dist

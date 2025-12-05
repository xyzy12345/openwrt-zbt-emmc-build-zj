# SPDX-License-Identifier: GPL-2.0-only
#
# Device definition for ZBT-Z8102AX-V2 eMMC version
# This file adds support for Zbtlink ZBT-Z8102AX-V2 with eMMC storage
# It should be appended to the main filogic.mk in OpenWrt build

define Device/zbtlink_zbt-z8102ax-v2-emmc
  DEVICE_VENDOR := Zbtlink
  DEVICE_MODEL := ZBT-Z8102AX-V2
  DEVICE_VARIANT := (eMMC)
  DEVICE_DTS := mt7981b-zbt-z8102ax-emmc
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 kmod-usb-net-qmi-wwan kmod-usb-serial-option e2fsprogs f2fsck mkf2fs
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += zbtlink_zbt-z8102ax-v2-emmc

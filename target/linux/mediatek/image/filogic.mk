DTS_DIR := $(DTS_DIR)/mediatek
DEVICE_VARS += SUPPORTED_TELTONIKA_DEVICES
DEVICE_VARS += SUPPORTED_TELTONIKA_HW_MODS

define Image/Prepare
	# For UBI we want only one extra block
	rm -f $(KDIR)/ubi_mark
	echo -ne '\xde\xad\xc0\xde' > $(KDIR)/ubi_mark
endef

define Build/fit-with-netgear-top-level-rootfs-node
	$(call Build/fit-its,$(1))
	$(TOPDIR)/scripts/gen_netgear_rootfs_node.sh $(KERNEL_BUILD_DIR)/root.squashfs > $@.rootfs
	awk '/configurations/ { system("cat $@.rootfs") } 1' $@.its > $@.its.tmp
	@mv -f $@.its.tmp $@.its
	@rm -f $@.rootfs
	$(call Build/fit-image,$(1))
endef

define Build/mt7981-bl2
	cat $(STAGING_DIR_IMAGE)/mt7981-$1-bl2.img >> $@
endef

define Build/mt7981-bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7981_$1-u-boot.fip >> $@
endef

define Build/mt7986-bl2
	cat $(STAGING_DIR_IMAGE)/mt7986-$1-bl2.img >> $@
endef

define Build/mt7986-bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7986_$1-u-boot.fip >> $@
endef

define Build/mt7987-bl2
	cat $(STAGING_DIR_IMAGE)/mt7987-$1-bl2.img >> $@
endef

define Build/mt7987-bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7987_$1-u-boot.fip >> $@
endef

define Build/mt7988-bl2
	cat $(STAGING_DIR_IMAGE)/mt7988-$1-bl2.img >> $@
endef

define Build/mt7988-bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7988_$1-u-boot.fip >> $@
endef

define Build/simplefit
	cp $@ $@.tmp 2>/dev/null || true
	ptgen -g -o $@.tmp -a 1 -l 1024 \
	-t 0x2e -N FIT		-p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@17k
	cat $@.tmp >> $@
	rm $@.tmp
endef

define Build/mt798x-gpt
	cp $@ $@.tmp 2>/dev/null || true
	ptgen -g -o $@.tmp -a 1 -l 1024 \
		$(if $(findstring sdmmc,$1), \
			-H \
			-t 0x83	-N bl2		-r	-p 4079k@17k \
		) \
			-t 0x83	-N ubootenv	-r	-p 512k@4M \
			-t 0x83	-N factory	-r	-p 2M@4608k \
			-t 0xef	-N fip		-r	-p 4M@6656k \
				-N recovery	-r	-p 32M@12M \
		$(if $(findstring sdmmc,$1), \
				-N install	-r	-p 20M@44M \
			-t 0x2e -N production		-p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@64M \
		) \
		$(if $(findstring emmc,$1), \
			-t 0x2e -N production		-p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@64M \
		)
	cat $@.tmp >> $@
	rm $@.tmp
endef

# Variation of the normal partition table to account
# for factory and mfgdata partition
#
# Keep fip partition at standard offset to keep consistency
# with uboot commands
define Build/mt7988-mozart-gpt
	cp $@ $@.tmp 2>/dev/null || true
	ptgen -g -o $@.tmp -a 1 -l 1024 \
			-t 0x83	-N ubootenv	-r	-p 512k@4M \
			-t 0xef	-N fip		  -r	-p 4M@6656k \
			-t 0x83	-N factory	-r	-p 8M@25M \
			-t 0x2e	-N mfgdata	-r	-p 8M@33M \
			-t 0xef -N recovery	-r	-p 32M@41M \
			-t 0x2e -N production		-p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@73M
	cat $@.tmp >> $@
	rm $@.tmp
endef

define Build/append-openwrt-one-eeprom
	dd if=$(STAGING_DIR_IMAGE)/mt7981_eeprom_mt7976_dbdc.bin >> $@
endef

define Build/mstc-header
  $(eval version=$(word 1,$(1)))
  $(eval magic=$(word 2,$(1)))
  gzip -c $@ | tail -c8 > $@.crclen
  ( \
    printf "$(magic)"; \
    tail -c+5 $@.crclen; head -c4 $@.crclen; \
    dd if=/dev/zero bs=4 count=2; \
    printf "$(version)" | dd bs=56 count=1 conv=sync 2>/dev/null; \
    dd if=/dev/zero bs=$$((0x20000 - 0x84)) count=1 conv=sync 2>/dev/null | \
      tr "\0" "\377"; \
    cat $@; \
  ) > $@.new
  mv $@.new $@
endef

define Build/zyxel-nwa-fit-filogic
	$(TOPDIR)/scripts/mkits-zyxel-fit-filogic.sh \
		$@.its $@ "80 e1 81 e1 ff ff ff ff ff ff"
	PATH=$(LINUX_DIR)/scripts/dtc:$(PATH) mkimage -f $@.its $@.new
	@mv $@.new $@
endef

define Build/cetron-header
	$(eval magic=$(word 1,$(1)))
	$(eval model=$(word 2,$(1)))
	( \
		dd if=/dev/zero bs=856 count=1 2>/dev/null; \
		printf "$(model)," | dd bs=128 count=1 conv=sync 2>/dev/null; \
		md5sum $@ | cut -f1 -d" " | dd bs=32 count=1 2>/dev/null; \
		printf "$(magic)" | dd bs=4 count=1 conv=sync 2>/dev/null; \
		cat $@; \
	) > $@.tmp
	fw_crc=$$(gzip -c $@.tmp | tail -c 8 | od -An -N4 -tx4 --endian little | tr -d ' \n'); \
	printf "$$(echo $$fw_crc | sed 's/../\\x&/g')" | cat - $@.tmp > $@
	rm $@.tmp
endef

define Build/sysupgrade-emmc
	$(call Build/mt798x-gpt,emmc)
	$(call Build/pad-to,64M)
	$(call Build/append-kernel)
	$(call Build/append-rootfs)
	$(call Build/check-size)
endef

define Device/zbtlink_z8102ax-emmc
  DEVICE_VENDOR := ZBT
  DEVICE_MODEL := Z8102AX
  DEVICE_VARIANT := (eMMC)
  DEVICE_DTS := mt7981b-zbt-z8102ax-emmc
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES := zbtlink,z8102ax-emmc
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware \
    kmod-usb3 kmod-usb2 kmod-mmc-mtk kmod-fs-ext4 \
    kmod-mtk-ppe kmod-hwmon-pwmfan \
    e2fsprogs fdisk lsblk blkid
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-emmc | append-metadata
  UBOOTENV_IN_UBI := 1
  KERNEL_IN_UBI := 1
endef
TARGET_DEVICES += zbtlink_z8102ax-emmc

# ZBT Z8102AX eMMC 分区布局说明

## 设备信息

- **设备型号**: ZBT Z8102AX (eMMC)
- **eMMC 容量**: 116.48 GiB (125074145280 bytes)
- **扇区大小**: 512 bytes
- **分区表类型**: GPT
- **SoC**: MediaTek MT7981B

## 实际分区布局

基于用户设备的 fdisk 输出：

```
Device            Start       End   Sectors  Size Type
/dev/mmcblk0p1        0        33        34   17K Linux filesystem
/dev/mmcblk0p2     8192      9215      1024  512K Linux filesystem
/dev/mmcblk0p3     9216     13311      4096    2M Linux filesystem
/dev/mmcblk0p4    13312     17407      4096    2M Linux filesystem
/dev/mmcblk0p5    17408     82943     65536   32M Linux filesystem
/dev/mmcblk0p6    82944  14680064  14597121    7G Linux filesystem
/dev/mmcblk0p7 14680065 234881024 220200960  105G Linux filesystem
```

## 分区功能说明

| 分区 | 起始扇区 | 大小 | 用途 | DTS 标签 |
|------|----------|------|------|----------|
| mmcblk0p1 | 0 | 17K | GPT 分区表头/预加载器 | preloader |
| mmcblk0p2 | 8192 | 512K | ARM Trusted Firmware | ATF |
| mmcblk0p3 | 9216 | 2M | U-Boot 环境变量 | u-boot-env |
| mmcblk0p4 | 13312 | 2M | 工厂数据/校准数据 | factory |
| mmcblk0p5 | 17408 | 32M | FIP (固件接口包) | fip |
| mmcblk0p6 | 82944 | 7G | 系统分区 (squashfs) | ubi |
| mmcblk0p7 | 14680065 | 105G | 用户数据分区 (ext4) | opt |

## DTS 文件中的分区定义

文件: `target/linux/mediatek/dts/mt7981b-zbt-z8102ax-emmc.dts`

DTS 文件在第 224-282 行定义了完整的分区表，使用 `fixed-partitions` 兼容模式。这意味着：

1. **分区布局在设备树中硬编码**
2. **内核启动时会读取 DTS 中的分区信息**
3. **不需要在运行时生成或修改 GPT 分区表**

关键配置：
```dts
&mmc0 {
    ...
    partitions {
        compatible = "fixed-partitions";
        #address-cells = <2>;
        #size-cells = <2>;
        
        partition@0 { label = "preloader"; ... }
        partition@1 { label = "ATF"; ... }
        partition@2 { label = "u-boot-env"; ... }
        partition@3 { label = "factory"; ... }
        partition@4 { label = "fip"; ... }
        partition@5 { label = "ubi"; ... }
        partition@6 { label = "opt"; ... }
    };
};
```

## 为什么不使用 mt798x-gpt

OpenWrt 的 `mt798x-gpt emmc` 函数生成的标准分区布局：

```
ptgen -g -o $@.tmp -a 1 -l 1024 \
    -t 0x83 -N ubootenv -r -p 512k@4M \      # @ 8192
    -t 0x83 -N factory  -r -p 2M@4608k \     # @ 9216
    -t 0xef -N fip      -r -p 4M@6656k \     # @ 13312
        -N recovery -r -p 32M@12M \          # @ 24576 ← 此设备没有
    -t 0x2e -N production  -p XXM@64M        # @ 131072
```

### 不兼容的原因

1. **缺少 recovery 分区**: 标准布局在 12M (扇区 24576) 有 32M recovery 分区，但此设备没有
2. **kernel/fip 位置不同**: 此设备的 fip 在扇区 17408 (8.5M)，而不是标准的 24576 (12M)
3. **rootfs 起始位置不同**: 此设备 rootfs 从扇区 82944 开始，而标准布局从 131072 (64M) 开始
4. **大容量数据分区**: 此设备有 105GB 的 opt 分区，这不是标准布局的一部分

### 正确的方法

**使用 DTS 中定义的分区表** - 无需生成 GPT：

1. DTS 文件已包含完整的分区定义
2. 内核会在启动时从 DTS 读取分区信息
3. 只需要生成以下 artifacts：
   - `emmc-preloader.bin` - BL2 预加载器
   - `emmc-bl31-uboot.fip` - BL31 + U-Boot FIP 包

## OpenWrt 设备定义

在 `target/linux/mediatek/image/filogic.mk` 中：

```makefile
define Device/zbtlink_z8102ax-emmc
  DEVICE_VENDOR := ZBT
  DEVICE_MODEL := Z8102AX (eMMC)
  DEVICE_DTS := mt7981b-zbt-z8102ax-emmc
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES := zbtlink,z8102ax-emmc
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware \
    kmod-usb3 kmod-usb2 kmod-mmc-mtk kmod-fs-ext4 \
    kmod-mtk-ppe kmod-hwmon-pwmfan e2fsprogs f2fsck mkf2fs
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  # 不包含 emmc-gpt.bin，因为 DTS 中已定义分区
  ARTIFACTS := emmc-preloader.bin emmc-bl31-uboot.fip
  ARTIFACT/emmc-preloader.bin := mt7981-bl2 emmc-ddr4
  ARTIFACT/emmc-bl31-uboot.fip := mt7981-bl31-uboot zbtlink_z8102ax-emmc
endef
TARGET_DEVICES += zbtlink_z8102ax-emmc
```

## 刷机说明

### 需要的文件

1. `openwrt-mediatek-filogic-zbtlink_z8102ax-emmc-squashfs-sysupgrade.bin` - 系统镜像
2. `mt7981-zbtlink_z8102ax-emmc-emmc-preloader.bin` - 预加载器
3. `mt7981_zbtlink_z8102ax-emmc-u-boot.fip` - U-Boot + BL31

### 刷机步骤

**方法 1: sysupgrade (推荐，用于升级现有 OpenWrt)**

```bash
sysupgrade -v openwrt-mediatek-filogic-zbtlink_z8102ax-emmc-squashfs-sysupgrade.bin
```

**方法 2: 完整刷机 (需要使用 USB 烧录工具)**

1. 使用 MTK 烧录工具将 preloader 写入 eMMC
2. 写入 FIP (BL31 + U-Boot)
3. 从 U-Boot 启动并使用 tftp/http 刷入 sysupgrade 镜像

## 参考设备

此设备的分区布局类似于以下 OpenWrt 设备：

- **glinet_gl-x3000** / **glinet_gl-xe3000**: 使用 DTS 定义的 eMMC 分区
- **huasifei_wh3000**: MT7981B + eMMC，使用 sysupgrade-tar
- **unielec_u7981-01-emmc**: 类似的 MT7981B eMMC 设备

这些设备都不使用 `mt798x-gpt` 生成 GPT，而是依赖 DTS 中的分区定义。

## 总结

1. ✅ **使用 DTS 中定义的分区表** - 无需 mt798x-gpt
2. ✅ **使用 sysupgrade-tar 格式** - OpenWrt eMMC 设备标准格式
3. ✅ **生成必需的 artifacts** - preloader 和 bl31-uboot.fip
4. ❌ **不生成 emmc-gpt.bin** - 分区表已在 DTS 中定义

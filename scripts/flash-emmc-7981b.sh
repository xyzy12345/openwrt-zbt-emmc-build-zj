#!/bin/bash
# ZBT-Z8102AX-eMMC 刷机脚本 (MT7981B专用)
# 适用于 eMMC uboot 启动的设备

set -e

echo "=== ZBT-Z8102AX-eMMC (MT7981B) 刷机脚本 ==="
echo "芯片: MT7981B"
echo "存储: eMMC"
echo "uboot: eMMC版本"
echo "=========================================="

# 检查固件文件
FIRMWARE=""
if [ -f openwrt-mediatek-filogic-zbtlink_z8102ax-emmc-squashfs-sysupgrade.bin ]; then
    FIRMWARE="openwrt-mediatek-filogic-zbtlink_z8102ax-emmc-squashfs-sysupgrade.bin"
elif [ -f *zbtlink_z8102ax-emmc*.bin ]; then
    FIRMWARE=$(ls *zbtlink_z8102ax-emmc*.bin | head -1)
else
    echo "错误: 未找到固件文件！"
    echo "请将固件放在当前目录并重试。"
    exit 1
fi

echo "找到固件: $FIRMWARE"
echo ""

# 安全确认
read -p "此操作将擦除 eMMC 上的所有数据！是否继续？[y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "操作已取消。"
    exit 0
fi

echo ""
echo "开始刷机过程..."
echo "=========================================="

# 1. 解压固件
echo "步骤1: 解压固件..."
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# 检查固件类型
if file ../$FIRMWARE | grep -q "sysupgrade"; then
    echo "检测到 sysupgrade 格式固件"
    tar -xzf ../$FIRMWARE
    if [ -d sysupgrade-zbtlink_z8102ax-emmc ]; then
        cd sysupgrade-zbtlink_z8102ax-emmc
    fi
else
    echo "检测到镜像文件格式"
    cp ../$FIRMWARE .
fi

# 2. 检查内核和rootfs
if [ ! -f kernel ] && [ ! -f root ]; then
    echo "错误: 固件格式不正确，缺少 kernel 或 root 文件"
    exit 1
fi

echo "固件解压完成。"

# 3. 分区 eMMC (GPT格式)
echo "步骤2: 分区 eMMC..."
EMMC_DEVICE="/dev/mmcblk0"

# 卸载所有分区
umount ${EMMC_DEVICE}* 2>/dev/null || true

# 创建GPT分区表
parted -s $EMMC_DEVICE mklabel gpt

# 创建分区（根据uboot要求）
# p1: boot (64M)
# p2: rootfs (512M)
# p3: overlay (剩余空间)
parted -s $EMMC_DEVICE mkpart boot fat32 1MiB 65MiB
parted -s $EMMC_DEVICE set 1 boot on
parted -s $EMMC_DEVICE mkpart rootfs ext4 65MiB 577MiB
parted -s $EMMC_DEVICE mkpart overlay ext4 577MiB 100%

# 4. 格式化分区
echo "步骤3: 格式化分区..."
mkfs.fat -F 32 -n BOOT ${EMMC_DEVICE}p1
mkfs.ext4 -F -L rootfs ${EMMC_DEVICE}p2
mkfs.ext4 -F -L overlay ${EMMC_DEVICE}p3

# 5. 安装系统
echo "步骤4: 安装系统..."

# 安装内核到boot分区
mount ${EMMC_DEVICE}p1 /mnt
if [ -f kernel ]; then
    cp kernel /mnt/
    echo "内核安装完成。"
fi

# 创建extlinux配置
mkdir -p /mnt/extlinux
cat > /mnt/extlinux/extlinux.conf << EOF
LABEL OpenWrt
    KERNEL /kernel
    FDTDIR /boot
    APPEND console=ttyS0,115200 root=/dev/mmcblk0p2 rootwait rw
EOF
umount /mnt

# 安装rootfs
if [ -f root ]; then
    echo "写入rootfs镜像..."
    dd if=root of=${EMMC_DEVICE}p2 bs=1M
    mount ${EMMC_DEVICE}p2 /mnt
else
    echo "错误: 未找到rootfs文件"
    exit 1
fi

# 6. 创建基本配置文件
echo "步骤5: 创建配置文件..."

# fstab
cat > /mnt/etc/fstab << EOF
/dev/mmcblk0p2 / ext4 rw,noatime 0 1
/dev/mmcblk0p3 /overlay ext4 rw,noatime 0 2
tmpfs /tmp tmpfs rw,nosuid,nodev 0 0
EOF

# 网络配置
cat > /mnt/etc/config/network << EOF
config interface 'loopback'
    option device 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config globals 'globals'
    option ula_prefix 'fd00:1234:5678::/48'

config device
    option name 'br-lan'
    option type 'bridge'
    list ports 'lan1'
    list ports 'lan2'
    list ports 'lan3'
    list ports 'lan4'

config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '192.168.1.1'
    option netmask '255.255.255.0'
    option ip6assign '60'

config interface 'wan'
    option device 'eth0'
    option proto 'dhcp'

config interface 'wan6'
    option device 'eth0'
    option proto 'dhcpv6'
EOF

# 无线配置
cat > /mnt/etc/config/wireless << EOF
config wifi-device 'radio0'
    option type 'mac80211'
    option path '1e140000.pcie'
    option channel '36'
    option band '5g'
    option htmode 'HE80'
    option disabled '0'

config wifi-iface 'default_radio0'
    option device 'radio0'
    option network 'lan'
    option mode 'ap'
    option ssid 'OpenWrt-5G'
    option encryption 'none'

config wifi-device 'radio1'
    option type 'mac80211'
    option path '1e140000.pcie'
    option channel 'auto'
    option band '2g'
    option htmode 'HT40'
    option disabled '0'

config wifi-iface 'default_radio1'
    option device 'radio1'
    option network 'lan'
    option mode 'ap'
    option ssid 'OpenWrt-2G'
    option encryption 'none'
EOF

# 7. 清理
echo "步骤6: 清理..."
umount /mnt
cd /
rm -rf $TEMP_DIR

echo ""
echo "=========================================="
echo "刷机完成！"
echo ""
echo "设备重启后将从 eMMC 启动 OpenWrt。"
echo ""
echo "首次启动后："
echo "1. 连接网线到 LAN 口"
echo "2. 访问 http://192.168.1.1"
echo "3. 用户名: root，密码: (无)"
echo "4. 建议立即修改 root 密码"
echo "=========================================="

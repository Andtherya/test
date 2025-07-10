#!/bin/sh
set -e

# ========== 脚本配置 ==========

DISK="/dev/sda"          # 安装磁盘，注意确认，所有数据会被清除！
HOSTNAME="alpine-pc"     # 主机名
TIMEZONE="Asia/Shanghai" # 时区
ROOT_PASS="123456"       # root 密码，安装完成后可以手动改

# ========== 1. 分区 ==========

echo "开始磁盘分区（清空 $DISK）..."
sgdisk --zap-all $DISK

sgdisk -n 1:0:0 -t 1:8300 $DISK   # 新建主分区，类型 Linux filesystem

# 格式化
mkfs.ext4 ${DISK}1

# 挂载
mount ${DISK}1 /mnt

# ========== 2. 安装 Alpine 基础系统 ==========

setup-alpine -f <<EOF
$HOSTNAME
auto
$TIMEZONE
$ROOT_PASS
$DISK
y
y
y
EOF

# ========== 3. 修改 apk 源为阿里云（速度快） ==========

cat > /etc/apk/repositories <<EOL
http://mirrors.aliyun.com/alpine/v3.18/main
http://mirrors.aliyun.com/alpine/v3.18/community
EOL

apk update

# ========== 4. 安装图形环境和浏览器 ==========

apk add --no-cache \
  xorg-server \
  xf86-video-vesa \
  mesa-dri-intel \
  openbox \
  lightdm \
  lightdm-gtk-greeter \
  chromium

# ========== 5. 配置 LightDM 开机自启 ==========

rc-update add lightdm

# ========== 6. 配置 Openbox 自动启动 Chromium ==========

mkdir -p /root/.config/openbox

cat > /root/.config/openbox/autostart <<EOF
chromium --no-sandbox --enable-features=VaapiVideoDecoder --use-gl=desktop &
EOF

# ========== 7. 卸载临时包、清理缓存（可选） ==========

apk cache clean

echo "安装完成！请重启系统。"


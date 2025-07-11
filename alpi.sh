#!/bin/sh

set -e

USER=alpineuser
# 使用清华镜像
MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/alpine/latest-stable/main"

# 设置 apk 镜像源
echo "$MIRROR_URL" > /etc/apk/repositories
echo "${MIRROR_URL/alpine/alpine/latest-stable/community}" >> /etc/apk/repositories

apk update

# 添加用户并设置免密码 sudo
adduser -D "$USER"
addgroup "$USER" wheel
echo "$USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 设置自动登录该用户
sed -i "s|^tty1.*|tty1::respawn:/bin/login -f $USER tty1 </dev/tty1 >/dev/tty1 2>&1|" /etc/inittab

# 安装图形界面和浏览器
apk add xorg-server xf86-video-vesa xf86-input-libinput \
        openbox chromium dbus elogind polkit \
        xf86-video-intel mesa-dri-gallium mesa-egl ttf-dejavu ttf-noto

# 启用 dbus 和 elogind
rc-update add dbus
rc-update add elogind
rc-service dbus start
rc-service elogind start

# 安装 fcitx5 + Rime 拼音输入法
apk add fcitx5 fcitx5-rime fcitx5-configtool fcitx5-gtk fcitx5-qt5

# 用户目录配置
su - "$USER" -c 'mkdir -p ~/.config/openbox ~/.config/autostart'
cat <<EOF > /home/$USER/.xinitrc
#!/bin/sh
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS="@im=fcitx"
fcitx5 &
exec openbox-session
EOF

chmod +x /home/$USER/.xinitrc
chown -R "$USER:$USER" /home/$USER/.config /home/$USER/.xinitrc

# 自动进入图形界面
echo "exec startx" > /home/$USER/.profile
chown "$USER:$USER" /home/$USER/.profile

echo "✅ [国内优化版] 配置完成，重启后将自动登录用户 $USER 并进入图形界面。"

#!/bin/sh
set -e

# ========= 配置项 =========
USERNAME=alpineuser  # 新建用户名称
AUTOLOGIN_TTY=tty1   # autologin 用的终端
BROWSER_EXEC="chromium --no-sandbox --enable-features=VaapiVideoDecoder --use-gl=desktop"

echo "[1/6] 创建新用户：$USERNAME"

# 添加用户组和用户（免密码）
adduser -D -G users -s /bin/sh $USERNAME
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# ========= 设置 LightDM 自动登录该用户 =========
echo "[2/6] 配置 LightDM 自动登录"

mkdir -p /etc/lightdm
cat > /etc/lightdm/lightdm.conf <<EOF
[Seat:*]
autologin-user=$USERNAME
autologin-session=openbox
EOF

# ========= 配置 openbox 自动启动 chromium =========
echo "[3/6] 配置 Openbox 自动启动 Chromium 浏览器"

USER_HOME="/home/$USERNAME"
mkdir -p $USER_HOME/.config/openbox

cat > $USER_HOME/.config/openbox/autostart <<EOF
#!/bin/sh
$BROWSER_EXEC &
EOF

chown -R $USERNAME:users $USER_HOME/.config

# ========= 安装 fcitx5 中文输入法（拼音） =========
echo "[4/6] 安装中文输入法 fcitx5 + 拼音"

apk add --no-cache \
  fcitx5 fcitx5-chinese-addons fcitx5-configtool fcitx5-gtk \
  fcitx5-pinyin glibc-locales

# ========= 设置用户环境变量启动输入法 =========
echo "[5/6] 配置环境变量以启用 fcitx5"

cat >> $USER_HOME/.profile <<'EOF'

# Fcitx5 config
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export DefaultIMModule=fcitx
fcitx5 &
EOF

chown $USERNAME:users $USER_HOME/.profile

# ========= 完成 =========
echo "[6/6] 配置完成！请重启系统后自动登录桌面，浏览器会自动启动，可用中文拼音输入法。"

#!/bin/bash
set -e

echo "=== Firefox + noVNC 免ROOT版 ==="

VNC_PASSWORD="${VNC_PASSWORD:-password}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1024x768}"

mkdir -p ~/apps ~/bin

# 1. Firefox
echo "[*] 下载 Firefox..."
if [ ! -f ~/apps/firefox/firefox ]; then
    cd ~/apps
    curl -L "https://download.mozilla.org/?product=firefox-latest&os=linux64&lang=zh-CN" -o firefox.tar.xz
    tar -xJf firefox.tar.xz && rm firefox.tar.xz
fi

# 2. noVNC
echo "[*] 下载 noVNC..."
if [ ! -d ~/apps/noVNC ]; then
    cd ~/apps
    git clone --depth 1 https://github.com/novnc/noVNC.git
    git clone --depth 1 https://github.com/novnc/websockify.git noVNC/utils/websockify
fi

# 3. TigerVNC 便携版 (从 SourceForge)
echo "[*] 下载 TigerVNC..."
if [ ! -d ~/apps/tigervnc ]; then
    cd ~/apps
    curl -L "https://sourceforge.net/projects/tigervnc/files/stable/1.16.0/tigervnc-1.16.0.x86_64.tar.gz/download" -o tigervnc.tar.gz
    tar -xzf tigervnc.tar.gz
    mv tigervnc-1.16.0.x86_64 tigervnc
    rm tigervnc.tar.gz
fi

# 4. cloudflared
echo "[*] 下载 cloudflared..."
if [ ! -f ~/bin/cloudflared ]; then
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o ~/bin/cloudflared
    chmod +x ~/bin/cloudflared
fi

# 5. 启动脚本
cat > ~/start-firefox.sh << 'START'
#!/bin/bash
RESOLUTION="${VNC_RESOLUTION:-1024x768}"
PASSWORD="${VNC_PASSWORD:-password}"
NOVNC_PORT=6080

# 清理
pkill -f "Xvnc" 2>/dev/null || true
pkill -f "firefox" 2>/dev/null || true
pkill -f "novnc_proxy" 2>/dev/null || true
pkill -f "cloudflared.*tunnel" 2>/dev/null || true
sleep 1

# VNC 密码
mkdir -p ~/.vnc
echo "$PASSWORD" | ~/apps/tigervnc/usr/bin/vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# 启动 Xvnc
echo "[*] 启动 VNC..."
~/apps/tigervnc/usr/bin/Xvnc :99 -geometry $RESOLUTION -depth 24 -rfbport 5900 -PasswordFile ~/.vnc/passwd -SecurityTypes VncAuth &
sleep 2
export DISPLAY=:99

# 启动 Firefox
echo "[*] 启动 Firefox..."
~/apps/firefox/firefox --no-remote &
sleep 2

# noVNC
echo "[*] 启动 noVNC..."
cd ~/apps/noVNC
nohup ./utils/novnc_proxy --vnc localhost:5900 --listen $NOVNC_PORT > /tmp/novnc.log 2>&1 &
sleep 2

# Cloudflare
echo "[*] 启动隧道..."
nohup ~/bin/cloudflared tunnel --url http://localhost:$NOVNC_PORT > /tmp/cloudflared.log 2>&1 &
sleep 5

TUNNEL_URL=$(grep -o 'https://[^[:space:]]*\.trycloudflare\.com' /tmp/cloudflared.log | head -1)

echo ""
echo "=========================================="
echo "  Firefox 已启动 (免ROOT)"
echo "=========================================="
echo "本地: http://localhost:$NOVNC_PORT/vnc.html"
[ -n "$TUNNEL_URL" ] && echo "公网: ${TUNNEL_URL}/vnc.html"
echo "密码: $PASSWORD"
echo "=========================================="
START
chmod +x ~/start-firefox.sh

cat > ~/stop-firefox.sh << 'STOP'
#!/bin/bash
pkill -f "Xvnc" 2>/dev/null
pkill -f "firefox" 2>/dev/null
pkill -f "novnc_proxy" 2>/dev/null
pkill -f "cloudflared.*tunnel" 2>/dev/null
echo "[*] 已停止"
STOP
chmod +x ~/stop-firefox.sh

echo ""
echo "=== 安装完成 (免ROOT) ==="
echo "启动: ~/start-firefox.sh"
echo "停止: ~/stop-firefox.sh"

#!/bin/bash
set -e

echo "=== Firefox + noVNC 免ROOT版 ==="

# 工作目录
WORKDIR=~/firefox-vnc
mkdir -p $WORKDIR/apps $WORKDIR/bin
cd $WORKDIR

VNC_PASSWORD="${VNC_PASSWORD:-password}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1024x768}"

# 1. Firefox
echo "[*] 下载 Firefox..."
if [ ! -f $WORKDIR/apps/firefox/firefox ]; then
    cd $WORKDIR/apps
    curl -L "https://download.mozilla.org/?product=firefox-latest&os=linux64&lang=zh-CN" -o firefox.tar.xz
    tar -xJf firefox.tar.xz && rm firefox.tar.xz
fi

# 2. noVNC
echo "[*] 下载 noVNC..."
if [ ! -d $WORKDIR/apps/noVNC ]; then
    cd $WORKDIR/apps
    git clone --depth 1 https://github.com/novnc/noVNC.git
    git clone --depth 1 https://github.com/novnc/websockify.git noVNC/utils/websockify
fi

# 3. TigerVNC
echo "[*] 下载 TigerVNC..."
if [ ! -d $WORKDIR/apps/tigervnc ]; then
    cd $WORKDIR/apps
    curl -L "https://sourceforge.net/projects/tigervnc/files/stable/1.16.0/tigervnc-1.16.0.x86_64.tar.gz/download" -o tigervnc.tar.gz
    tar -xzf tigervnc.tar.gz
    mv tigervnc-1.16.0.x86_64 tigervnc
    rm tigervnc.tar.gz
fi

# 4. cloudflared
echo "[*] 下载 cloudflared..."
if [ ! -f $WORKDIR/bin/cloudflared ]; then
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o $WORKDIR/bin/cloudflared
    chmod +x $WORKDIR/bin/cloudflared
fi

# 5. 启动脚本
echo "[*] 创建脚本..."
cat > $WORKDIR/start.sh << 'START'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLUTION="${VNC_RESOLUTION:-1024x768}"
PASSWORD="${VNC_PASSWORD:-password}"
NOVNC_PORT=6080

pkill -f "Xvnc" 2>/dev/null || true
pkill -f "firefox" 2>/dev/null || true
pkill -f "novnc_proxy" 2>/dev/null || true
pkill -f "cloudflared.*tunnel" 2>/dev/null || true
sleep 1

mkdir -p ~/.vnc
echo "$PASSWORD" | $DIR/apps/tigervnc/usr/bin/vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

echo "[*] 启动 VNC..."
$DIR/apps/tigervnc/usr/bin/Xvnc :99 -geometry $RESOLUTION -depth 24 -rfbport 5900 -PasswordFile ~/.vnc/passwd -SecurityTypes VncAuth &
sleep 2
export DISPLAY=:99

echo "[*] 启动 Firefox..."
$DIR/apps/firefox/firefox --no-remote &
sleep 2

echo "[*] 启动 noVNC..."
cd $DIR/apps/noVNC
nohup ./utils/novnc_proxy --vnc localhost:5900 --listen $NOVNC_PORT > /tmp/novnc.log 2>&1 &
sleep 2

echo "[*] 启动隧道..."
nohup $DIR/bin/cloudflared tunnel --url http://localhost:$NOVNC_PORT > /tmp/cloudflared.log 2>&1 &
sleep 5

TUNNEL_URL=$(grep -o "https://[^[:space:]]*\.trycloudflare\.com" /tmp/cloudflared.log | head -1)

echo ""
echo "=========================================="
echo "  Firefox 已启动 (免ROOT)"
echo "=========================================="
echo "本地: http://localhost:$NOVNC_PORT/vnc.html"
[ -n "$TUNNEL_URL" ] && echo "公网: ${TUNNEL_URL}/vnc.html"
echo "密码: $PASSWORD"
echo "=========================================="
START

cat > $WORKDIR/stop.sh << 'STOP'
#!/bin/bash
pkill -f "Xvnc" 2>/dev/null
pkill -f "firefox" 2>/dev/null
pkill -f "novnc_proxy" 2>/dev/null
pkill -f "cloudflared.*tunnel" 2>/dev/null
echo "[*] 已停止"
STOP

cat > $WORKDIR/uninstall.sh << 'UNINSTALL'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
$DIR/stop.sh 2>/dev/null
rm -rf $DIR
rm -rf ~/.vnc
echo "[*] 已卸载"
UNINSTALL

chmod +x $WORKDIR/*.sh

echo ""
echo "=== 安装完成 (免ROOT) ==="
echo "目录: $WORKDIR"
echo ""
echo "启动: $WORKDIR/start.sh"
echo "停止: $WORKDIR/stop.sh"
echo "卸载: $WORKDIR/uninstall.sh"

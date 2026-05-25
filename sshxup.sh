#!/bin/bash

pkill sshx

mkdir -p "./tmp"
cd ./tmp

# 检测系统架构
ARCH=$(uname -m)

case "$ARCH" in
    x86_64)
        URL="https://gitlab.com/rtwera-group/rtwera-project/-/raw/main/sshxgo-linux-amd64"
        ;;
    aarch64)
        URL="https://gitlab.com/rtwera-group/rtwera-project/-/raw/main/sshxgo-linux-arm64"
        ;;
    *)
        echo "不支持的架构: $ARCH"
        exit 1
        ;;
esac

echo "检测到架构: $ARCH"
echo "下载中..."

# 自动选择下载工具
if command -v curl &>/dev/null; then
    curl -fSL "$URL" -o sshx || { echo "下载失败"; exit 1; }
elif command -v wget &>/dev/null; then
    wget -q "$URL" -O sshx || { echo "下载失败"; exit 1; }
else
    echo "错误: 未找到 curl 或 wget"
    exit 1
fi

# 赋予执行权限
chmod +x ./sshx

echo "启动 sshx..."
# 运行
nohup ./sshx > output.log 2>/dev/null &
sleep 2
cat output.log
rm -rf "$(pwd)"

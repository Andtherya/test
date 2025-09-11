#!/bin/bash

UUID="${UUID:-5861ed67-f4ae-4e02-868e-9cea7d2d5a9e}"
DOMAIN="${DOMAIN:-www.visa.com.sg}"
PORT="${CFPORT:-3000}"
NAME="${NAME:-Vls}"


pkill web

mkdir -p "./tmp"

cd ./tmp


# 检查并删除 config.json
if [ -f "config.json" ]; then
  rm -f "./config.json"
  echo "已删除 ./config.json"
fi


# 下载 ryx => web
if [ -f "web" ]; then
    echo "文件 web 已存在，跳过下载。"
else
    echo "下载 ryx 为 web..."
    curl -Lo web https://github.com/fascmer/test/releases/download/test/ryx
fi

# 赋予执行权限
chmod +x web

# 生成 Xray 配置文件 config.json
cat > config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "email": "idx-xhttp",
            "flow": "",
            "id": "$UUID"
          }
        ]
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "host": "",
          "mode": "auto",
          "path": "/"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    },
    {
      "protocol": "socks",
      "tag": "proxy-8086",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 8086
          }
        ]
      }
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": [
          "domain:googlevideo.com"
        ],
        "outboundTag": "proxy-8086"
      }
    ]
  }
}
EOF

# 后台启动 web（xr-ay）
if [ -f "./web" ]; then
  nohup ./web -c ./config.json >/dev/null 2>&1 &
  sleep 2
  ps | grep "web" | grep -v 'grep'
  echo "web 已启动。"
  echo "--------------------------------------------------"
else
  echo "启动失败：web 可执行文件不存在"
  exit 1
fi



# 获取 ISP 信息
metaInfo=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
ISP=$(echo "$metaInfo" | tr -d '\n')


# 构建 VMESS JSON 并转 base64

echo "-----------------------------------------------------------------------"

echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&alpn=h2&fp=chrome&type=xhttp&path=%2F&mode=auto#idx-xhttp#${NAME}-${ISP}"

echo "----------------------------------------------------------------------------"




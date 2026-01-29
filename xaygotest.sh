#!/bin/bash

export UUID="${UUID:-5861ed67-f4ae-4e02-868e-9cea7d2d5a9e}"
export ARGO_DOMAIN="${ARGO_DOMAIN:-}"
export ARGO_AUTH="${ARGO_AUTH:-}"
export ARGO_PORT="${ARGO_PORT:-35568}"
export CFIP="${CFIP:-www.visa.com.sg}"
export CFPORT="${CFPORT:-443}"
export NAME="${NAME:-Vls}"
export VLPORT="${VLPORT:-3001}"

pkill bot
pkill web

mkdir -p "./tmp"

cd ./tmp

ARCH=$(uname -m)

if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
    echo "Error: curl 或 wget 都不可用，无法下载文件。"
    exit 1
fi

if [ "$ARCH" == "arm" ] || [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
    if command -v curl &> /dev/null; then
        curl -s -Lo web https://github.com/Andtherya/test/releases/download/xray/xray-arm
        curl -s -Lo bot https://github.com/Andtherya/test/releases/download/tjt/cloudflared-arm64
    elif command -v wget &> /dev/null; then
        wget -q -O web https://github.com/Andtherya/test/releases/download/xray/xray-arm
        wget -q -O bot https://github.com/Andtherya/test/releases/download/tjt/cloudflared-arm64
    fi
elif [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "x86" ]; then
    if command -v curl &> /dev/null; then
        curl -s -Lo web https://github.com/Andtherya/test/releases/download/xray/xray-amd
        curl -s -Lo bot https://github.com/Andtherya/test/releases/download/tjt/cloudflared-amd64
    elif command -v wget &> /dev/null; then
        wget -q -O web https://github.com/Andtherya/test/releases/download/xray/xray-amd
        wget -q -O bot https://github.com/Andtherya/test/releases/download/tjt/cloudflared-amd64
    fi
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi


wait

chmod +x bot web

# 生成 Xray 配置文件 config.json
cat > config.json <<EOF
{
  "log": {
    "access": "/dev/null",
    "error": "/dev/null",
    "loglevel": "none"
  },
  "inbounds": [
    {
      "port": $ARGO_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          { "dest": $VLPORT },
          { "path": "/vless-argo", "dest": $((VLPORT + 1)) },
          { "path": "/vmess-argo", "dest": $((VLPORT + 2)) },
          { "path": "/trojan-argo", "dest": $((VLPORT + 3)) }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
    },
    {
      "port": $VLPORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    },
    {
      "port": $((VLPORT + 1)),
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID", "level": 0 }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vless-argo"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
    {
      "port": $((VLPORT + 2)),
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          { "id": "$UUID", "alterId": 0 }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess-argo"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
    {
      "port": $((VLPORT + 3)),
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {
        "clients": [
          { "password": "$UUID" }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/trojan-argo"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    }
  ],
  "dns": {
    "servers": [
      "https+local://8.8.8.8/dns-query"
    ]
  },
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
sleep 1
if [ -e "web" ]; then
    nohup ./web run -c config.json >/dev/null 2>&1 &
    sleep 2
    echo -e "\e[1;32mweb is running\e[0m"
fi

if [ -e "bot" ]; then
    if [[ $ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
        args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
    elif [[ $ARGO_AUTH =~ TunnelSecret ]]; then
        args="tunnel --edge-ip-version auto --config tunnel.yml run"
    else
        args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info --url http://localhost:$ARGO_PORT"
    fi
    
    nohup ./bot $args >/dev/null 2>&1 &
    sleep 2
    echo -e "\e[1;32mbot is running\e[0m" 
fi

get_argodomain() {
if [[ -n $ARGO_AUTH ]]; then
    sleep 0
    echo "$ARGO_DOMAIN"
else
    local retry=0
    local max_retries=8
    local argodomain=""
    
    while [[ $retry -lt $max_retries ]]; do
        ((retry++))
        argodomain=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' boot.log)
        echo -e "\e[1;32mtring...\n\e[0m" 
        if [[ -n $argodomain ]]; then
            break
        fi
        
        sleep 1
    done
    
    sleep 0
    echo "$argodomain"
fi
}
argodomain=$(get_argodomain)

# 获取 ISP 信息
JSON="$(curl -s https://ipinfo.io/json)"
COUNTRY="$(echo "$JSON" | sed -n 's/.*"country":[[:space:]]*"\([^"]*\)".*/\1/p')"
ORG="$(echo "$JSON" | sed -n 's/.*"org":[[:space:]]*"AS[0-9]*[[:space:]]*\([^"]*\)".*/\1/p')"
ISP="${COUNTRY}-${ORG}"

# 构建 VMESS JSON 并转 base64
VMESS_JSON=$(cat <<EOF
{
  "v": "2",
  "ps": "${NAME}-${ISP}",
  "add": "${CFIP}",
  "port": "${CFPORT}",
  "id": "${UUID}",
  "aid": "0",
  "scy": "none",
  "net": "ws",
  "type": "none",
  "host": "${argoDomain}",
  "path": "/vmess-argo?ed=2560",
  "tls": "tls",
  "sni": "${argoDomain}",
  "alpn": "",
  "fp":"firefox"
}
EOF
)

VMESS_BASE64=$(echo -n "$VMESS_JSON" | base64 -w 0)

# 构建 vless / vmess / trojan 连接内容
subTxt=$(cat <<EOF
vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${argoDomain}&fp=firefox&type=ws&host=${argoDomain}&path=%2Fvless-argo%3Fed%3D2560#${NAME}-${ISP}

vmess://${VMESS_BASE64}

trojan://${UUID}@${CFIP}:${CFPORT}?security=tls&sni=${argoDomain}&fp=firefox&type=ws&host=${argoDomain}&path=%2Ftrojan-argo%3Fed%3D2560#${NAME}-${ISP}
EOF
)

echo "$subTxt" | base64 -w 0 > "./sub.txt"
echo "./sub.txt saved successfully"
echo "$subTxt" | base64 -w 0
echo -e "\n\n"
rm -rf $(pwd)

#!/bin/sh

# -----------------------
# 环境变量配置（可由外部传入，否则使用默认值）
# -----------------------
UUID="${UUID:-5861ed67-f4ae-4e02-868e-9cea7d2d5a9e}"
ARGO_DOMAIN="${ARGO_DOMAIN:-}"
ARGO_AUTH="${ARGO_AUTH:-}"
ARGO_PORT="${ARGO_PORT:-35568}"
CFIP="${CFIP:-www.visa.com.sg}"
CFPORT="${CFPORT:-443}"
NAME="${NAME:-Vls}"
FILE_PATH="./tmp"
BOOT_LOG="${FILE_PATH}/boot.log"

pkill -f "./tmp/web" >/dev/null 2>&1
pkill -f "./tmp/bot" >/dev/null 2>&1

# 创建或确认 tmp 目录存在
if [ ! -d "$FILE_PATH" ]; then
    echo "创建 tmp 目录..."
    mkdir -p "$FILE_PATH"
else
    echo "tmp 目录已存在，跳过创建。"
fi

# 进入 tmp 目录
cd "$FILE_PATH" || { echo "进入 tmp 目录失败，退出。"; exit 1; }

# 下载 cox => bot
if [ -f "bot" ]; then
    echo "文件 bot 已存在，跳过下载。"
else
    echo "下载 cox 为 bot..."
    curl -Lo bot https://github.com/Kuthduse/glaxy/releases/download/test/cox
fi

# 下载 ryx => web
if [ -f "web" ]; then
    echo "文件 web 已存在，跳过下载。"
else
    echo "下载 ryx 为 web..."
    curl -Lo web https://github.com/Kuthduse/glaxy/releases/download/test/ryx
fi

# 赋予执行权限
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
          { "dest": 3001 },
          { "path": "/vless-argo", "dest": 3002 },
          { "path": "/vmess-argo", "dest": 3003 },
          { "path": "/trojan-argo", "dest": 3004 }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
    },
    {
      "port": 3001,
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
      "port": 3002,
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
      "port": 3003,
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
      "port": 3004,
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

echo "下载与配置完成，文件位于 $(pwd)"

# 后台启动 web（xr-ay）
if [ -f "./web" ]; then
  nohup ./web -c ./config.json >/dev/null 2>&1 &
  sleep 1
  echo "web 已启动（xr-ay 正在后台运行）"
else
  echo "启动失败：web 可执行文件不存在"
  exit 1
fi

# 判断 bot 是否存在
if [ -f "./bot" ]; then
  echo "准备启动 bot (cloudflared)..."

  # 判断 ARGO_AUTH 是否是合法的 token（长度 120~250 且字符匹配）
  if echo "$ARGO_AUTH" | grep -qE '^[A-Za-z0-9=]{120,250}$'; then
    ARGS="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
  else
    # 使用本地端口方式连接（fallback 模式）
    ARGS="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile ./boot.log --loglevel info --url http://localhost:${ARGO_PORT}"
  fi

  # 后台运行 bot
  nohup ./bot $ARGS >/dev/null 2>&1 &
  echo "bot 已启动"

  # 等待 2 秒稳定
  sleep 2
else
  echo "跳过：bot 文件不存在"
fi

# 额外等待 5 秒
sleep 5

# 判断：是否同时存在 ARGO_AUTH 和 ARGO_DOMAIN
if [ -n "$ARGO_AUTH" ] && [ -n "$ARGO_DOMAIN" ]; then
  argoDomain="$ARGO_DOMAIN"
  echo "使用提供的 ARGO_DOMAIN: $argoDomain"
else
  echo "未提供 ARGO_DOMAIN，从 boot.log 中提取..."
  if [ -f "$BOOT_LOG" ]; then
    argoDomain=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare.com' ./tmp/boot.log | head -n 1)
    if [ -n "$argoDomain" ]; then
      echo "提取到 Argo 域名: $argoDomain"
    else
      echo "未从 boot.log 提取到 Argo 域名"
    fi
  else
    echo "boot.log 文件不存在，无法提取 Argo 域名"
  fi
fi

# 获取 ISP 信息
metaInfo=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
ISP=$(echo "$metaInfo" | tr -d '\n')

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
  "alpn": ""
}
EOF
)

VMESS_BASE64=$(echo -n "$VMESS_JSON" | base64)

# 构建 vless / vmess / trojan 连接内容
subTxt=$(cat <<EOF
vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${argoDomain}&type=ws&host=${argoDomain}&path=%2Fvless-argo%3Fed%3D2560#${NAME}-${ISP}

vmess://${VMESS_BASE64}

trojan://${UUID}@${CFIP}:${CFPORT}?security=tls&sni=${argoDomain}&type=ws&host=${argoDomain}&path=%2Ftrojan-argo%3Fed%3D2560#${NAME}-${ISP}
EOF
)

echo "vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${argoDomain}&type=ws&host=${argoDomain}&path=%2Fvless-argo%3Fed%3D2560#${NAME}-${ISP}"
echo "vmess://${VMESS_BASE64}"
echo "trojan://${UUID}@${CFIP}:${CFPORT}?security=tls&sni=${argoDomain}&type=ws&host=${argoDomain}&path=%2Ftrojan-argo%3Fed%3D2560#${NAME}-${ISP}"
# 编码 subTxt 并写入 sub.txt
echo "$subTxt" | base64 > "${FILE_PATH}/sub.txt"
echo "${FILE_PATH}/sub.txt saved successfully"

# 输出 base64 结果（可用于 curl 返回）
echo "$subTxt" | base64

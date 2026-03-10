#!/bin/bash

export UUID="${UUID:-5861ed67-f4ae-4e02-868e-9cea7d2d5a9e}"
export ARGO_DOMAIN="${ARGO_DOMAIN:-}"
export ARGO_AUTH="${ARGO_AUTH:-}"
export ARGO_PORT="${ARGO_PORT:-35568}"
export CFIP="${CFIP:-www.visa.com.sg}"
export CFPORT="${CFPORT:-443}"
export NAME="${NAME:-Vls}"
export VLPORT="${VLPORT:-3001}"

# WARP 开关 (true/false)
export WARP_ENABLED="${WARP_ENABLED:-false}"

# WARP 配置
export WARP_PRIVATE_KEY="${WARP_PRIVATE_KEY:-gBoo/TGTHTgO4gafTvOiaDyRujLRHYcKKFc3RUrgmHk=}"
export WARP_PUBLIC_KEY="${WARP_PUBLIC_KEY:-bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=}"
export WARP_ADDRESS_V4="${WARP_ADDRESS_V4:-172.16.0.2}"
export WARP_ADDRESS_V6="${WARP_ADDRESS_V6:-2606:4700:110:8b25:edd6:d647:6fd3:9cc3}"
export WARP_RESERVED="${WARP_RESERVED:-[149,13,8]}"
export WARP_ENDPOINT="${WARP_ENDPOINT:-engage.cloudflareclient.com:2408}"

# 前置代理配置
export SOCKS_PRO="${SOCKS_PRO:-}"
export Xray_link="${Xray_link:-}"

pkill bot
pkill web
rm -rf tmp

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
        curl -s -Lo bot https://github.com/Andtherya/test/releases/download/test/argo-linux-arm64
    elif command -v wget &> /dev/null; then
        wget -q -O web https://github.com/Andtherya/test/releases/download/xray/xray-arm
        wget -q -O bot https://github.com/Andtherya/test/releases/download/test/argo-linux-arm64
    fi
elif [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "x86" ]; then
    if command -v curl &> /dev/null; then
        curl -s -Lo web https://github.com/Andtherya/test/releases/download/xray/xray-amd
        curl -s -Lo bot https://github.com/Andtherya/test/releases/download/test/argo-linux-amd64
    elif command -v wget &> /dev/null; then
        wget -q -O web https://github.com/Andtherya/test/releases/download/xray/xray-amd
        wget -q -O bot https://github.com/Andtherya/test/releases/download/test/argo-linux-amd64
    fi
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

wait

chmod +x bot web

# ============================================================
# 确定 cloudflared 前置代理参数
# 优先级: SOCKS_PRO > Xray_link > 无代理(直连)
# ============================================================
EDGE_PROXY_ARGS=""

if [ -n "$SOCKS_PRO" ]; then
    # 直接使用外部 SOCKS5 代理
    EDGE_PROXY_ARGS="--edge-proxy-url ${SOCKS_PRO}"
    echo -e "\e[1;33m[Proxy] Using external SOCKS5: ${SOCKS_PRO}\e[0m"

elif [ -n "$Xray_link" ]; then
    # 解析 Xray_link 并生成本地 SOCKS 代理配置
    EDGE_PROXY_ARGS="--edge-proxy-url socks5://127.0.0.1:20808"
    echo -e "\e[1;33m[Proxy] Using Xray local SOCKS5 on port 20808\e[0m"

    # 解析代理链接，生成 xray outbound 配置
    PROTO="$(echo "$Xray_link" | sed -n 's|^\([a-z]*\)://.*|\1|p')"

    # 辅助函数：根据 security 生成 streamSettings JSON
    # 参数: $1=network $2=security $3=sni $4=fp $5=path $6=host
    build_stream_settings() {
        local _net="${1:-ws}" _sec="${2}" _sni="${3}" _fp="${4:-firefox}" _path="${5}" _host="${6:-$3}"
        if [ "$_sec" = "tls" ]; then
            cat <<SEOF
    "network": "${_net}",
    "security": "tls",
    "tlsSettings": {
      "serverName": "${_sni}",
      "fingerprint": "${_fp}",
      "allowInsecure": false
    },
    "wsSettings": {"path": "${_path}", "headers": {"Host": "${_host}"}}
SEOF
        else
            cat <<SEOF
    "network": "${_net}",
    "security": "none",
    "wsSettings": {"path": "${_path}", "headers": {"Host": "${_host}"}}
SEOF
        fi
    }

    generate_proxy_outbound() {
        case "$PROTO" in
        vless)
            local userinfo="$(echo "$Xray_link" | sed 's|^vless://||' | sed 's|#.*||')"
            local uuid="$(echo "$userinfo" | sed 's|@.*||')"
            local hostport="$(echo "$userinfo" | sed 's|^[^@]*@||' | sed 's|?.*||')"
            local addr="$(echo "$hostport" | sed 's|:.*||')"
            local port="$(echo "$hostport" | sed 's|^[^:]*:||')"
            local params="$(echo "$userinfo" | sed -n 's|.*?\(.*\)|\1|p')"

            local sni="$(echo "$params" | tr '&' '\n' | sed -n 's|^sni=||p')"
            local host="$(echo "$params" | tr '&' '\n' | sed -n 's|^host=||p')"
            local path="$(echo "$params" | tr '&' '\n' | sed -n 's|^path=||p' | sed 's|%2F|/|g; s|%3F|?|g; s|%3D|=|g; s|%26|\&|g')"
            local fp="$(echo "$params" | tr '&' '\n' | sed -n 's|^fp=||p')"
            local net_type="$(echo "$params" | tr '&' '\n' | sed -n 's|^type=||p')"
            local security="$(echo "$params" | tr '&' '\n' | sed -n 's|^security=||p')"
            local encryption="$(echo "$params" | tr '&' '\n' | sed -n 's|^encryption=||p')"

            local stream_body="$(build_stream_settings "${net_type}" "${security}" "${sni}" "${fp}" "${path}" "${host}")"

            cat <<XEOF
{
  "protocol": "vless",
  "settings": {
    "vnext": [{
      "address": "${addr}",
      "port": ${port},
      "users": [{"id": "${uuid}", "encryption": "${encryption:-none}"}]
    }]
  },
  "streamSettings": {
${stream_body}
  },
  "tag": "proxy-out"
}
XEOF
            ;;

        vmess)
            local b64="$(echo "$Xray_link" | sed 's|^vmess://||' | sed 's|#.*||')"
            local json="$(echo "$b64" | base64 -d 2>/dev/null)"

            local addr="$(echo "$json" | sed -n 's|.*"add"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p')"
            local port="$(echo "$json" | sed -n 's|.*"port"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9]*\)"\{0,1\}.*|\1|p')"
            local uuid="$(echo "$json" | sed -n 's|.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p')"
            local aid="$(echo "$json" | sed -n 's|.*"aid"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9]*\)"\{0,1\}.*|\1|p')"
            local net="$(echo "$json" | sed -n 's|.*"net"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p')"
            local host="$(echo "$json" | sed -n 's|.*"host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p')"
            local path="$(echo "$json" | sed -n 's|.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p')"
            local tls="$(echo "$json" | sed -n 's|.*"tls"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p')"
            local sni="$(echo "$json" | sed -n 's|.*"sni"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p')"
            local fp="$(echo "$json" | sed -n 's|.*"fp"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p')"
            local scy="$(echo "$json" | sed -n 's|.*"scy"[[:space:]]*:[[:space:]]*"\([^"]*\)".*|\1|p')"

            local security="none"
            [ "$tls" = "tls" ] && security="tls"

            local stream_body="$(build_stream_settings "${net}" "${security}" "${sni}" "${fp}" "${path}" "${host}")"

            cat <<XEOF
{
  "protocol": "vmess",
  "settings": {
    "vnext": [{
      "address": "${addr}",
      "port": ${port},
      "users": [{"id": "${uuid}", "alterId": ${aid:-0}, "security": "${scy:-auto}"}]
    }]
  },
  "streamSettings": {
${stream_body}
  },
  "tag": "proxy-out"
}
XEOF
            ;;

        trojan)
            local userinfo="$(echo "$Xray_link" | sed 's|^trojan://||' | sed 's|#.*||')"
            local password="$(echo "$userinfo" | sed 's|@.*||')"
            local hostport="$(echo "$userinfo" | sed 's|^[^@]*@||' | sed 's|?.*||')"
            local addr="$(echo "$hostport" | sed 's|:.*||')"
            local port="$(echo "$hostport" | sed 's|^[^:]*:||')"
            local params="$(echo "$userinfo" | sed -n 's|.*?\(.*\)|\1|p')"

            local sni="$(echo "$params" | tr '&' '\n' | sed -n 's|^sni=||p')"
            local host="$(echo "$params" | tr '&' '\n' | sed -n 's|^host=||p')"
            local path="$(echo "$params" | tr '&' '\n' | sed -n 's|^path=||p' | sed 's|%2F|/|g; s|%3F|?|g; s|%3D|=|g; s|%26|\&|g')"
            local fp="$(echo "$params" | tr '&' '\n' | sed -n 's|^fp=||p')"
            local net_type="$(echo "$params" | tr '&' '\n' | sed -n 's|^type=||p')"
            local security="$(echo "$params" | tr '&' '\n' | sed -n 's|^security=||p')"

            local stream_body="$(build_stream_settings "${net_type}" "${security}" "${sni}" "${fp}" "${path}" "${host}")"

            cat <<XEOF
{
  "protocol": "trojan",
  "settings": {
    "servers": [{"address": "${addr}", "port": ${port}, "password": "${password}"}]
  },
  "streamSettings": {
${stream_body}
  },
  "tag": "proxy-out"
}
XEOF
            ;;
        *)
            echo -e "\e[1;31m[Proxy] Unsupported Xray_link protocol: $PROTO\e[0m"
            EDGE_PROXY_ARGS=""
            return 1
            ;;
        esac
    }

    PROXY_OUTBOUND=$(generate_proxy_outbound)

    if [ $? -eq 0 ] && [ -n "$PROXY_OUTBOUND" ]; then
        # 生成前置代理专用 xray 配置 (仅 socks inbound + proxy outbound)
        cat > proxy_config.json <<PEOF
{
  "log": { "access": "/dev/null", "error": "/dev/null", "loglevel": "none" },
  "inbounds": [{
    "port": 20808,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": { "auth": "noauth", "udp": false }
  }],
  "outbounds": [
    ${PROXY_OUTBOUND},
    { "protocol": "freedom", "tag": "direct" }
  ]
}
PEOF
        # 启动前置代理 xray 实例
        nohup ./web run -c proxy_config.json >/dev/null 2>&1 &
        sleep 2
        echo -e "\e[1;32m[Proxy] Xray local SOCKS5 proxy started on port 20808\e[0m"
    else
        EDGE_PROXY_ARGS=""
        echo -e "\e[1;31m[Proxy] Failed to parse Xray_link, falling back to direct\e[0m"
    fi
else
    echo -e "\e[1;33m[Proxy] No proxy configured, using direct connection\e[0m"
fi

# ============================================================
# 根据 WARP_ENABLED 生成不同的 outbounds 配置
# ============================================================
if [ "$WARP_ENABLED" == "true" ]; then
    OUTBOUNDS_CONFIG='[
    {
      "protocol": "wireguard",
      "settings": {
        "secretKey": "'"$WARP_PRIVATE_KEY"'",
        "address": [
          "'"$WARP_ADDRESS_V4"'/32",
          "'"$WARP_ADDRESS_V6"'/128"
        ],
        "peers": [
          {
            "publicKey": "'"$WARP_PUBLIC_KEY"'",
            "allowedIPs": ["0.0.0.0/0", "::/0"],
            "endpoint": "'"$WARP_ENDPOINT"'"
          }
        ],
        "reserved": '"$WARP_RESERVED"',
        "mtu": 1280
      },
      "tag": "warp"
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]'
else
    OUTBOUNDS_CONFIG='[
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]'
fi

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
  "outbounds": $OUTBOUNDS_CONFIG
}
EOF
sleep 1
if [ -e "web" ]; then
    nohup ./web run -c config.json >/dev/null 2>&1 &
    sleep 2
    if [ "$WARP_ENABLED" == "true" ]; then
        echo -e "\e[1;32mweb is running (with WARP outbound)\e[0m"
    else
        echo -e "\e[1;32mweb is running (direct outbound)\e[0m"
    fi
fi

if [ -e "bot" ]; then
    if [[ $ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
        args="tunnel ${EDGE_PROXY_ARGS} --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
    elif [[ $ARGO_AUTH =~ TunnelSecret ]]; then
        args="tunnel ${EDGE_PROXY_ARGS} --edge-ip-version auto --config tunnel.yml run"
    else
        args="tunnel ${EDGE_PROXY_ARGS} --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info --url http://localhost:$ARGO_PORT"
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
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "${argodomain}",
  "path": "/vmess-argo?ed=2560",
  "tls": "tls",
  "sni": "${argodomain}",
  "alpn": "",
  "fp":"firefox"
}
EOF
)

VMESS_BASE64=$(echo -n "$VMESS_JSON" | base64 -w 0)

# 构建 vless / vmess / trojan 连接内容
subTxt=$(cat <<EOF
vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${argodomain}&fp=firefox&type=ws&host=${argodomain}&path=%2Fvless-argo%3Fed%3D2560#${NAME}-${ISP}

vmess://${VMESS_BASE64}

trojan://${UUID}@${CFIP}:${CFPORT}?security=tls&sni=${argodomain}&fp=firefox&type=ws&host=${argodomain}&path=%2Ftrojan-argo%3Fed%3D2560#${NAME}-${ISP}
EOF
)

echo "$subTxt" | base64 -w 0 > "./sub.txt"
echo "./sub.txt saved successfully"
echo "$subTxt" | base64 -w 0
echo -e "\n\n"

rm -rf "$(pwd)"

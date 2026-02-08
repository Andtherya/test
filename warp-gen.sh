#!/bin/bash

# WARP 配置一键生成脚本
# 直接调用 Cloudflare 官方 API

set -e

# 生成 WireGuard 密钥对 (Curve25519)
generate_keypair() {
    if command -v openssl &> /dev/null && openssl genpkey -algorithm X25519 &>/dev/null; then
        PRIVKEY_PEM=$(openssl genpkey -algorithm X25519 2>/dev/null)
        PRIVATE_KEY=$(echo "$PRIVKEY_PEM" | openssl pkey -outform DER 2>/dev/null | tail -c 32 | base64)
        PUBLIC_KEY=$(echo "$PRIVKEY_PEM" | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | base64)
    elif command -v wg &> /dev/null; then
        PRIVATE_KEY=$(wg genkey)
        PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
    else
        echo "Error: 需要 openssl 3.0+ 或 wireguard-tools"
        exit 1
    fi
}

# 注册 WARP 设备
register_warp() {
    local public_key="$1"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    
    curl -sX POST "https://api.cloudflareclient.com/v0a2158/reg" \
        -H "Content-Type: application/json" \
        -H "CF-Client-Version: a-6.11-2223" \
        -d '{
            "key": "'"$public_key"'",
            "install_id": "",
            "fcm_token": "",
            "tos": "'"$timestamp"'",
            "model": "PC",
            "type": "Android",
            "locale": "en_US"
        }'
}

# 解析 client_id 为 reserved 数组
parse_reserved() {
    local client_id="$1"
    local bytes=$(echo -n "$client_id" | base64 -d | od -An -tu1 | tr -d '\n' | xargs)
    echo "[${bytes// /,}]"
}

# 主流程
main() {
    echo "正在生成 WireGuard 密钥对..." >&2
    generate_keypair
    
    echo "正在注册 WARP 设备..." >&2
    RESPONSE=$(register_warp "$PUBLIC_KEY")
    
    # 检查是否成功
    if echo "$RESPONSE" | grep -q '"success":false'; then
        echo "注册失败: $RESPONSE" >&2
        exit 1
    fi
    
    # 使用更可靠的解析方式
    if command -v jq &> /dev/null; then
        IPV4=$(echo "$RESPONSE" | jq -r '.config.interface.addresses.v4')
        IPV6=$(echo "$RESPONSE" | jq -r '.config.interface.addresses.v6')
        CLIENT_ID=$(echo "$RESPONSE" | jq -r '.config.client_id')
    else
        # 备用解析
        IPV4=$(echo "$RESPONSE" | sed -n 's/.*"v4":"\([^"]*\)".*/\1/p' | head -1)
        IPV6=$(echo "$RESPONSE" | sed -n 's/.*"v6":"\([^"]*\)".*/\1/p' | head -1)
        CLIENT_ID=$(echo "$RESPONSE" | sed -n 's/.*"client_id":"\([^"]*\)".*/\1/p')
    fi
    
    RESERVED=$(parse_reserved "$CLIENT_ID")
    
    # WARP 服务器公钥 (固定值)
    WARP_PUBLIC_KEY="bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
    ENDPOINT="162.159.192.1:2408"
    
    echo "" >&2
    echo "========== WARP 配置生成成功 ==========" >&2
    echo ""
    echo "# WireGuard 原始配置"
    echo "[Interface]"
    echo "PrivateKey = $PRIVATE_KEY"
    echo "Address = ${IPV4}/32, ${IPV6}/128"
    echo "DNS = 1.1.1.1"
    echo "MTU = 1280"
    echo ""
    echo "[Peer]"
    echo "PublicKey = $WARP_PUBLIC_KEY"
    echo "AllowedIPs = 0.0.0.0/0, ::/0"
    echo "Endpoint = $ENDPOINT"
    echo ""
    echo "# ========== Xray 配置 =========="
    echo ""
    cat <<XRAY
{
  "protocol": "wireguard",
  "settings": {
    "secretKey": "$PRIVATE_KEY",
    "address": ["${IPV4}/32", "${IPV6}/128"],
    "peers": [
      {
        "publicKey": "$WARP_PUBLIC_KEY",
        "allowedIPs": ["0.0.0.0/0", "::/0"],
        "endpoint": "$ENDPOINT"
      }
    ],
    "reserved": $RESERVED,
    "mtu": 1280
  },
  "tag": "warp"
}
XRAY
    echo ""
    echo "# ========== 环境变量格式 =========="
    echo ""
    echo "export WARP_PRIVATE_KEY=\"$PRIVATE_KEY\""
    echo "export WARP_PUBLIC_KEY=\"$WARP_PUBLIC_KEY\""
    echo "export WARP_ADDRESS_V4=\"$IPV4\""
    echo "export WARP_ADDRESS_V6=\"$IPV6\""
    echo "export WARP_RESERVED=\"$RESERVED\""
    echo "export WARP_ENDPOINT=\"$ENDPOINT\""
}

main

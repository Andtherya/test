#!/bin/bash

export UUID=${UUID:-'fdeeda45-0a8e-4570-bcc6-d68c995f5830'}
export ARGO_DOMAIN=${ARGO_DOMAIN:-''}      
export ARGO_AUTH=${ARGO_AUTH:-''}         
export CFIP=${CFIP:-'cf.877774.xyz'}      
export CFPORT=${CFPORT:-'443'}             
export NAME=${NAME:-''}                      
export FILE_PATH=${FILE_PATH:-'./temp'}      
export ARGO_PORT=${ARGO_PORT:-'34586'}         # argo端口 使用固定隧道token,cloudflare后台设置的端口需和这里对应
export TUIC_PORT=${TUIC_PORT:-''}             # Tuic 端口，支持多端口玩具可填写，否则不动
export HY2_PORT=${HY2_PORT:-''}               # Hy2 端口，支持多端口玩具可填写，否则不动
export REALITY_PORT=${REALITY_PORT:-''}       # reality 端口,支持多端口玩具可填写，否则不动   
export DISABLE_ARGO=${DISABLE_ARGO:-'false'}  # 是否禁用argo, true为禁用,false为不禁用

pkill -f "$FILE_PATH"
rm -rf "$FILE_PATH"

if [ -f ".env" ]; then
    # 使用 sed 移除 export 关键字，并过滤注释行
    set -o allexport  # 临时开启自动导出变量
    source <(grep -v '^#' .env | sed 's/^export //' )
    set +o allexport  # 关闭自动导出
fi

[ ! -d "${FILE_PATH}" ] && mkdir -p "${FILE_PATH}"


rm -rf boot.log config.json tunnel.json tunnel.yml "${FILE_PATH}/sub.txt" >/dev/null 2>&1

argo_configure() {
  if [ "$DISABLE_ARGO" == 'true' ]; then
    echo -e "\e[1;32mDisable argo tunnel\e[0m"
    return
  fi
  if [[ -z $ARGO_AUTH || -z $ARGO_DOMAIN ]]; then
    echo -e "\e[1;32mARGO_DOMAIN or ARGO_AUTH variable is empty, use quick tunnels\e[0m"   
    return
  fi

  if [[ $ARGO_AUTH =~ TunnelSecret ]]; then
    echo $ARGO_AUTH > ${FILE_PATH}/tunnel.json
    cat > tunnel.yml << EOF
tunnel: $(cut -d\" -f12 <<< "$ARGO_AUTH")
credentials-file: ${FILE_PATH}/tunnel.json
protocol: http2

ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:$ARGO_PORT
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
  else
    echo -e "\e[1;32mUsing token connect to tunnel,please set $ARGO_PORT in cloudflare tunnel\e[0m"
  fi
}
argo_configure
wait

download_and_run() {
ARCH=$(uname -m) && FILE_INFO=()
if [ "$ARCH" == "arm" ] || [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
    FILE_INFO=("https://github.com/Andtherya/test/releases/download/sb/arm-sb web" "https://github.com/Andtherya/test/releases/download/test/cloudflared-arm64 bot")
elif [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "x86" ]; then
    FILE_INFO=("https://github.com/Andtherya/test/releases/download/sb/amd-sb web" "https://github.com/Andtherya/test/releases/download/test/cd-amd64-23.7.1 bot")
elif [ "$ARCH" == "s390x" ] || [ "$ARCH" == "s390" ]; then
    FILE_INFO=("https://github.com/Andtherya/test/releases/download/sb/s390-sb web" "https://github.com/Andtherya/test/releases/download/test/cd-s390x-23.7.1 bot")
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

declare -A FILE_MAP
generate_random_name() {
    local chars=abcdefghijklmnopqrstuvwxyz1234567890
    local name=""
    for i in {1..6}; do
        name="$name${chars:RANDOM%${#chars}:1}"
    done
    echo "$name"
}
download_file() {
    local URL=$1
    local NEW_FILENAME=$2

    if command -v curl >/dev/null 2>&1; then
        curl -L -sS -o "$NEW_FILENAME" "$URL"
        echo -e "\e[1;32mDownloaded $NEW_FILENAME by curl\e[0m"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$NEW_FILENAME" "$URL"
        echo -e "\e[1;32mDownloaded $NEW_FILENAME by wget\e[0m"
    else
        echo -e "\e[1;33mNeither curl nor wget is available for downloading\e[0m"
        exit 1
    fi
}
for entry in "${FILE_INFO[@]}"; do
    URL=$(echo "$entry" | cut -d ' ' -f 1)
    RANDOM_NAME=$(generate_random_name)
    NEW_FILENAME="${FILE_PATH}/$RANDOM_NAME"
    
    download_file "$URL" "$NEW_FILENAME"
    
    chmod +x "$NEW_FILENAME"
    FILE_MAP[$(echo "$entry" | cut -d ' ' -f 2)]="$NEW_FILENAME"
done
wait

# 检查reality密钥文件是否存在，存在则读取，否则生成新的
if [ -f "${FILE_PATH}/key.txt" ]; then
    # 尝试读取密钥
    private_key=$(grep "PrivateKey:" "${FILE_PATH}/key.txt" | awk '{print $2}')
    public_key=$(grep "PublicKey:" "${FILE_PATH}/key.txt" | awk '{print $2}')
    
    if [ -n "$private_key" ] && [ -n "$public_key" ]; then
        true
    else
        # 读取失败，重新生成
        output=$("${FILE_PATH}/$(basename ${FILE_MAP[web]})" generate reality-keypair)
        echo "$output" > "${FILE_PATH}/key.txt"
        private_key=$(echo "${output}" | awk '/PrivateKey:/ {print $2}')
        public_key=$(echo "${output}" | awk '/PublicKey:/ {print $2}')
    fi
else
    output=$("${FILE_PATH}/$(basename ${FILE_MAP[web]})" generate reality-keypair)
    echo "$output" > "${FILE_PATH}/key.txt"
    private_key=$(echo "${output}" | awk '/PrivateKey:/ {print $2}')
    public_key=$(echo "${output}" | awk '/PublicKey:/ {print $2}')
fi

# 生成证书和私钥
if command -v openssl >/dev/null 2>&1; then
    openssl ecparam -genkey -name prime256v1 -out "${FILE_PATH}/private.key"
    openssl req -new -x509 -days 3650 -key "${FILE_PATH}/private.key" -out "${FILE_PATH}/cert.pem" -subj "/CN=bing.com"
else
    # 创建私钥文件
    cat > "${FILE_PATH}/private.key" << 'EOF'
-----BEGIN EC PARAMETERS-----
BggqhkjOPQMBBw==
-----END EC PARAMETERS-----
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIM4792SEtPqIt1ywqTd/0bYidBqpYV/++siNnfBYsdUYoAoGCCqGSM49
AwEHoUQDQgAE1kHafPj07rJG+HboH2ekAI4r+e6TL38GWASANnngZreoQDF16ARa
/TsyLyFoPkhLxSbehH/NBEjHtSZGaDhMqQ==
-----END EC PRIVATE KEY-----
EOF

    # 创建证书文件
    cat > "${FILE_PATH}/cert.pem" << 'EOF'
-----BEGIN CERTIFICATE-----
MIIBejCCASGgAwIBAgIUfWeQL3556PNJLp/veCFxGNj9crkwCgYIKoZIzj0EAwIw
EzERMA8GA1UEAwwIYmluZy5jb20wHhcNMjUwOTE4MTgyMDIyWhcNMzUwOTE2MTgy
MDIyWjATMREwDwYDVQQDDAhiaW5nLmNvbTBZMBMGByqGSM49AgEGCCqGSM49AwEH
A0IABNZB2nz49O6yRvh26B9npACOK/nuky9/BlgEgDZ54Ga3qEAxdegEWv07Mi8h
aD5IS8Um3oR/zQRIx7UmRmg4TKmjUzBRMB0GA1UdDgQWBBTV1cFID7UISE7PLTBR
BfGbgkrMNzAfBgNVHSMEGDAWgBTV1cFID7UISE7PLTBRBfGbgkrMNzAPBgNVHRMB
Af8EBTADAQH/MAoGCCqGSM49BAMCA0cAMEQCIAIDAJvg0vd/ytrQVvEcSm6XTlB+
eQ6OFb9LbLYL9f+sAiAffoMbi4y/0YUSlTtz7as9S8/lciBF5VCUoVIKS+vX2g==
-----END CERTIFICATE-----
EOF
fi

  cat > ${FILE_PATH}/config.json << EOF
{
    "log": {
      "disabled": true,
      "level": "error",
      "timestamp": true
    },
    "inbounds": [
    {
      "tag": "vmess-ws-in",
      "type": "vmess",
      "listen": "::",
      "listen_port": ${ARGO_PORT},
        "users": [
        {
          "uuid": "${UUID}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/vmess-argo",
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    }$(if [ "$TUIC_PORT" != "" ]; then echo ',
    {
      "tag": "tuic-in",
      "type": "tuic",
      "listen": "::",
      "listen_port": '${TUIC_PORT}',
      "users": [
        {
          "uuid": "'${UUID}'",
          "password": "admin"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": [
          "h3"
        ],
        "certificate_path": "'${FILE_PATH}'/cert.pem",
        "key_path": "'${FILE_PATH}'/private.key"
      }
    }'; fi)$(if [ "$HY2_PORT" != "" ]; then echo ',
    {
      "tag": "hysteria2-in",
      "type": "hysteria2",
      "listen": "::",
      "listen_port": '${HY2_PORT}',
        "users": [
          {
             "password": "'${UUID}'"
          }
      ],
      "masquerade": "https://bing.com",
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "'${FILE_PATH}'/cert.pem",
            "key_path": "'${FILE_PATH}'/private.key"
          }
      }'; fi)$(if [ "$REALITY_PORT" != "" ]; then echo ',
      {
        "tag": "vless-reality-vesion",
        "type": "vless",
        "listen": "::",
        "listen_port": '${REALITY_PORT}',
          "users": [
              {
                "uuid": "'$UUID'",
                "flow": "xtls-rprx-vision"
              }
          ],
          "tls": {
              "enabled": true,
              "server_name": "www.nazhumi.com",
              "reality": {
                  "enabled": true,
                  "handshake": {
                      "server": "www.nazhumi.com",
                      "server_port": 443
                  },
                  "private_key": "'$private_key'",
                  "short_id": [
                    ""
                  ]
              }
          }
      }'; fi)
   ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "mtu": 1280,
      "address": [
        "172.16.0.2/32",
        "2606:4700:110:8dfe:d141:69bb:6b80:925/128"
      ],
      "private_key": "YFYOAdbw1bKTHlNNi+aEjBM3BO7unuFC5rOkMRAz9XY=",
      "peers": [
        {
          "address": "engage.cloudflareclient.com",
          "port": 2408,
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0",
            "::/0"
          ],
          "reserved": [
            78,
            135,
            76
          ]
        }
      ]
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rule_set": [
      {
        "tag": "openai",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/openai.srs",
        "download_detour": "direct"
      },
      {
        "tag": "netflix",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/netflix.srs",
        "download_detour": "direct"
      }
    ],
    "rules": [
      { "action": "sniff" },
      { "rule_set": ["openai", "netflix"], "outbound": "warp-out" }
    ],
    "final": "direct"
  }
}
EOF

if [ -e "${FILE_PATH}/$(basename ${FILE_MAP[web]})" ]; then
    nohup "${FILE_PATH}/$(basename ${FILE_MAP[web]})" run -c ${FILE_PATH}/config.json >> log.txt 2>&1 &
    sleep 2
    echo -e "\e[1;32m$(basename ${FILE_MAP[web]}) is running\e[0m"
fi

if [ "$DISABLE_ARGO" == 'false' ]; then
  if [ -e "${FILE_PATH}/$(basename ${FILE_MAP[bot]})" ]; then
      if [[ $ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
        args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
      elif [[ $ARGO_AUTH =~ TunnelSecret ]]; then
        args="tunnel --edge-ip-version auto --config ${FILE_PATH}/tunnel.yml run"
      else
        args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile ${FILE_PATH}/boot.log --loglevel info --url http://localhost:$ARGO_PORT"
      fi
      nohup "${FILE_PATH}/$(basename ${FILE_MAP[bot]})" $args >/dev/null 2>&1 &
      sleep 2
      echo -e "\e[1;32m$(basename ${FILE_MAP[bot]}) is running\e[0m" 
  fi
fi


for key in "${!FILE_MAP[@]}"; do
    if [ -e "${FILE_PATH}/$(basename ${FILE_MAP[$key]})" ]; then
        rm -rf "${FILE_PATH}/$(basename ${FILE_MAP[$key]})" >/dev/null 2>&1
    fi
done
}
download_and_run

get_argodomain() {
if [ "$DISABLE_ARGO" == 'false' ]; then
  if [[ -n $ARGO_AUTH ]]; then
    echo "$ARGO_DOMAIN"
  else
    local retry=0
    local max_retries=8
    local argodomain=""
    while [[ $retry -lt $max_retries ]]; do
      ((retry++))
      argodomain=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' ${FILE_PATH}/boot.log)
      if [[ -n $argodomain ]]; then
        break
      fi
      sleep 1
    done
    echo "$argodomain"
  fi
fi
}


argodomain=$(get_argodomain)
[ "$DISABLE_ARGO" == 'false' ] && echo -e "\e[1;32mArgoDomain:\e[1;35m${argodomain}\e[0m\n"
sleep 1
IP=$(curl -s --max-time 2 ipv4.ip.sb || curl -s --max-time 1 api.ipify.org || { ipv6=$(curl -s --max-time 1 ipv6.ip.sb); echo "[$ipv6]"; } || echo "XXX")
ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g' || echo "0.0")
costom_name() { if [ -n "$NAME" ]; then echo "${NAME}_${ISP}"; else echo "${ISP}"; fi; }

VMESS="{ \"v\": \"2\", \"ps\": \"$(costom_name)\", \"add\": \"${CFIP}\", \"port\": \"${CFPORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${argodomain}\", \"path\": \"/vmess-argo?ed=2560\", \"tls\": \"tls\", \"sni\": \"${argodomain}\", \"alpn\": \"\", \"fp\": \"firefox\"}"

if [ "$DISABLE_ARGO" == 'false' ]; then
cat > ${FILE_PATH}/list.txt <<EOF
vmess://$(echo "$VMESS" | base64 | tr -d '\n')
EOF
fi

if [ "$TUIC_PORT" != "" ]; then
  echo -e "\ntuic://${UUID}:admin@${IP}:${TUIC_PORT}?sni=www.bing.com&alpn=h3&congestion_control=bbr#$(costom_name)" >> ${FILE_PATH}/list.txt
fi

if [ "$HY2_PORT" != "" ]; then
  echo -e "\nhysteria2://${UUID}@${IP}:${HY2_PORT}/?sni=www.bing.com&alpn=h3&insecure=1#$(costom_name)" >> ${FILE_PATH}/list.txt
fi

if [ "$REALITY_PORT" != "" ]; then
  echo -e "\nvless://${UUID}@${IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.nazhumi.com&fp=firefox&pbk=${public_key}&type=tcp&headerType=none#$(costom_name)" >> ${FILE_PATH}/list.txt
fi

base64 ${FILE_PATH}/list.txt | tr -d '\n' > ${FILE_PATH}/sub.txt
cat ${FILE_PATH}/list.txt
echo -e "\n\n\e[1;32m${FILE_PATH}/sub.txt saved successfully\e[0m"

echo -e "\n\e[1;32mRunning done!\e[0m\n"
sleep 3 

//rm -rf fake_useragent_0.2.0.json ${FILE_PATH}/boot.log ${FILE_PATH}/config.json ${FILE_PATH}/sb.log ${FILE_PATH}/core ${FILE_PATH}/fake_useragent_0.2.0.json ${FILE_PATH}/list.txt ${FILE_PATH}/tunnel.json ${FILE_PATH}/tunnel.yml >/dev/null 2>&1

sleep 5
clear


# tail -f /dev/null  # 若只单独运行此文件并希望保持运行,去掉此行开头的#号

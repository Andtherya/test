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

rm -rf "$FILE_PATH"

if [ -f ".env" ]; then
    # 使用 sed 移除 export 关键字，并过滤注释行
    set -o allexport  # 临时开启自动导出变量
    source <(grep -v '^#' .env | sed 's/^export //' )
    set +o allexport  # 关闭自动导出
fi

[ ! -d "${FILE_PATH}" ] && mkdir -p "${FILE_PATH}"

wait

cd $FILE_PATH


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


workspace=$(pwd)

  cat > config.json << EOF
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
        "certificate_path": "'${workspace}'/cert.pem",
        "key_path": "'${workspace}'/private.key"
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
            "certificate_path": "'${workspace}'/cert.pem",
            "key_path": "'${workspace}'/private.key"
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
        "tag": "youtube",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/youtube.srs",
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
      { "rule_set": ["youtube", "netflix"], "outbound": "warp-out" }
    ],
    "final": "direct"
  }
}
EOF
sleep 1


if [ "$DISABLE_ARGO" == 'false' ]; then
  if [ "$DISABLE_ARGO" == 'false' ]; then
      if [[ $ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
        args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
      elif [[ $ARGO_AUTH =~ TunnelSecret ]]; then
        args="tunnel --edge-ip-version auto --config tunnel.yml run"
      else
        args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info --url http://localhost:$ARGO_PORT"
      fi
      echo "nohup ./bot ${args} >/dev/null 2>&1 &"
  fi
fi

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
      argodomain=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' boot.log)
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
JSON="$(curl -s https://ipinfo.io/json)"
COUNTRY="$(echo "$JSON" | sed -n 's/.*"country":[[:space:]]*"\([^"]*\)".*/\1/p')"
ORG="$(echo "$JSON" | sed -n 's/.*"org":[[:space:]]*"AS[0-9]*[[:space:]]*\([^"]*\)".*/\1/p')"
ISP="${COUNTRY}-${ORG}"
costom_name() { if [ -n "$NAME" ]; then echo "${NAME}_${ISP}"; else echo "${ISP}"; fi; }

VMESS="{ \"v\": \"2\", \"ps\": \"$(costom_name)\", \"add\": \"${CFIP}\", \"port\": \"${CFPORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${argodomain}\", \"path\": \"/vmess-argo?ed=2560\", \"tls\": \"tls\", \"sni\": \"${argodomain}\", \"alpn\": \"\", \"fp\": \"firefox\"}"

if [ "$DISABLE_ARGO" == 'false' ]; then
cat > list.txt <<EOF
vmess://$(echo "$VMESS" | base64 | tr -d '\n')
EOF
fi

if [ "$TUIC_PORT" != "" ]; then
  echo -e "\ntuic://${UUID}:admin@${IP}:${TUIC_PORT}?sni=www.bing.com&alpn=h3&congestion_control=bbr#$(costom_name)" >> list.txt
fi

if [ "$HY2_PORT" != "" ]; then
  echo -e "\nhysteria2://${UUID}@${IP}:${HY2_PORT}/?sni=www.bing.com&alpn=h3&insecure=1#$(costom_name)" >> list.txt
fi

if [ "$REALITY_PORT" != "" ]; then
  echo -e "\nvless://${UUID}@${IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.nazhumi.com&fp=firefox&pbk=${public_key}&type=tcp&headerType=none#$(costom_name)" >> list.txt
fi

base64 list.txt | tr -d '\n' > sub.txt
cat list.txt
echo -e "\n\n\e[1;32msub.txt saved successfully\e[0m"

echo -e "\n\e[1;32mRunning done!\e[0m\n"




# tail -f /dev/null  # 若只单独运行此文件并希望保持运行,去掉此行开头的#号

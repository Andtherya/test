#!/bin/bash

export UUID="${UUID:-5861ed67-f4ae-4e02-868e-9cea7d2d5a9e}"
export ARGO_DOMAIN="${ARGO_DOMAIN:-}"
export ARGO_AUTH="${ARGO_AUTH:-}"
export ARGO_PORT="${ARGO_PORT:-35568}"
export CFIP="${CFIP:-www.visa.com.sg}"
export CFPORT="${CFPORT:-443}"
export NAME="${NAME:-Vls}"
export DISABLE_ARGO=${DISABLE_ARGO:-'false'} 

rm -rf tmp

mkdir -p "./tmp"

cd ./tmp

download_and_run() {
ARCH=$(uname -m)
if [ "$ARCH" == "arm" ] || [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
    curl -s -Lo web https://github.com/Andtherya/test/releases/download/sb/arm-sb
    if [ "$DISABLE_ARGO" == 'false' ]; then
        curl -s -Lo bot https://github.com/Andtherya/test/releases/download/tjt/cloudflared-arm64
    fi
elif [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "x86" ]; then
    curl -s -Lo web https://github.com/Andtherya/test/releases/download/sb/amd-sb
    if [ "$DISABLE_ARGO" == 'false' ]; then
        curl -s -Lo bot https://github.com/Andtherya/test/releases/download/tjt/cloudflared-amd64
    fi
else
    sleep 0
    #echo "Unsupported architecture: $ARCH"
    exit 1
fi

wait

chmod +x web
if [ "$DISABLE_ARGO" == 'false' ]; then
    chmod +x bot
fi

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
    }],
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
  "rules": [{"action": "sniff"}],
  "final": "warp-out"
}
}
EOF
sleep 1
if [ -e "web" ]; then
    nohup ./web run -c config.json >/dev/null 2>&1 &
    sleep 2
    #echo -e "\e[1;32mweb is running\e[0m"
fi

if [ "$DISABLE_ARGO" == 'false' ]; then
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
      #echo -e "\e[1;32mbot is running\e[0m" 
  fi
fi

}
download_and_run

get_argodomain() {
if [ "$DISABLE_ARGO" == 'false' ]; then
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
fi
}
argodomain=$(get_argodomain)
sleep 1
IP=$(curl -s --max-time 2 ipv4.ip.sb || curl -s --max-time 1 api.ipify.org || { ipv6=$(curl -s --max-time 1 ipv6.ip.sb); echo "[$ipv6]"; } || echo "XXX")
JSON="$(curl -s https://ipinfo.io/json)"
COUNTRY="$(echo "$JSON" | sed -n 's/.*"country":[[:space:]]*"\([^"]*\)".*/\1/p')"
ORG="$(echo "$JSON" | sed -n 's/.*"org":[[:space:]]*"AS[0-9]*[[:space:]]*\([^"]*\)".*/\1/p')"
ISP="${COUNTRY}-${ORG}"
costom_name() { if [ -n "$NAME" ]; then echo "${NAME}_${ISP}"; else echo "${ISP}"; fi; }

VMESS="{ \"v\": \"2\", \"ps\": \"$(costom_name)\", \"add\": \"${CFIP}\", \"port\": \"${CFPORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${argodomain}\", \"path\": \"/vmess-argo?ed=2560\", \"tls\": \"tls\", \"sni\": \"${argodomain}\", \"alpn\": \"\", \"fp\": \"firefox\"}"

cat > list.txt <<EOF
vmess://$(echo "$VMESS" | base64 | tr -d '\n')
EOF

base64 list.txt | tr -d '\n' > sub.txt

echo "$subTxt" | base64 -w 0
echo -e "\n\n"

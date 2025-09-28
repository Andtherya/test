#!/bin/bash

# 定义下载 URL 和文件名
URL="https://github.com/Andtherya/test/releases/download/test/app-linux-amd64"
FILE="app-linux-amd64"

# 下载文件
echo "Downloading $FILE..."
curl -L -o "$FILE" "$URL"

# 检查下载是否成功
if [ ! -f "$FILE" ]; then
    echo "Download failed!"
    exit 1
fi

# 赋予可执行权限
chmod +x "$FILE"
echo "Permission granted."

# 运行文件
echo "Running $FILE..."
./"$FILE"

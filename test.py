#!/usr/bin/env python3
import os
import asyncio
import socket
import hashlib
import base64
import json
import struct
from urllib.parse import quote
import aiohttp
from aiohttp import web, WSMsgType

# 配置
UUID = os.environ.get('UUID', 'b64c9a01-3f09-4dea-a0f1-dc85e5a3ac19')
DOMAIN = os.environ.get('DOMAIN', 'rrhost.firehuo.de5.net')
WSPATH = os.environ.get('WSPATH', quote(f"api/v1/user?token={UUID[:8]}&lang=en"))
SUB_PATH = os.environ.get('SUB_PATH', 'dc85e5a3ac19/sub')
NAME = os.environ.get('NAME', 'rrhost')
PORT = int(os.environ.get('PORT', 7640))

DB_PATH = os.environ.get('DB_PATH', 'bot_data.db')
ADMIN_UID = os.environ.get('ADMIN_UID', '1130431721')

DNS_SERVERS = ['8.8.4.4', '1.1.1.1']
ISP = 'Unknown'
uuid_hex = UUID.replace('-', '')

async def simulate_musicbot_run():
    print(f'''
+--------------------------------------------------------------+
|           Telegram Verification Bot - VPS Version            |
+--------------------------------------------------------------+
|  Port: {PORT:<54}|
|  Admin: {ADMIN_UID:<53}|
|  Database: {DB_PATH:<50}|
+--------------------------------------------------------------+
|  Endpoints:                                                  |
|    GET  /                    - Health check                  |
|    POST /webhook             - Telegram Webhook              |
|    GET  /registerWebhook     - Register Webhook              |
|    GET  /unRegisterWebhook   - Unregister Webhook            |
+--------------------------------------------------------------+
''') 

async def download_and_save_bot():
    url = "https://raw.githubusercontent.com/Andtherya/tgbchat/refs/heads/main/bot.py"
    output_file = "bot.py"

    async with aiohttp.ClientSession() as session:
        async with session.get(url) as response:
            if response.status == 200:
                content = await response.text()
                with open(output_file, "w", encoding="utf-8") as f:
                    f.write(content)
            else:
                print(f"Download Failure: {response.status}")


async def get_isp():
    """获取ISP信息"""
    global ISP
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get('https://api.ip.sb/geoip') as response:
                data = await response.json()
                ISP = f"{data.get('country_code', 'XX')}-{data.get('isp', 'Unknown')}".replace(' ', '_')
    except Exception:
        ISP = 'Unknown'


async def resolve_host(host: str) -> str:
    """DNS解析"""
    # 检查是否为IP地址
    try:
        socket.inet_aton(host)
        return host
    except socket.error:
        pass
    
    # 使用Google DNS over HTTPS
    async with aiohttp.ClientSession() as session:
        for dns_server in DNS_SERVERS:
            try:
                url = f'https://dns.google/resolve?name={quote(host)}&type=A'
                async with session.get(url, timeout=aiohttp.ClientTimeout(total=5)) as response:
                    data = await response.json()
                    if data.get('Status') == 0 and data.get('Answer'):
                        for record in data['Answer']:
                            if record.get('type') == 1:
                                return record['data']
            except Exception:
                continue
    
    # 回退到系统DNS
    return host


def parse_vless(msg: bytes) -> tuple:
    """解析VLESS协议"""
    if len(msg) < 17:
        return None
    
    version = msg[0]
    id_bytes = msg[1:17]
    
    # 验证UUID
    expected_id = bytes.fromhex(uuid_hex)
    if id_bytes != expected_id:
        return None
    
    addon_len = msg[17]
    i = 18 + addon_len
    
    # 跳过命令字节
    i += 1
    
    port = struct.unpack('>H', msg[i:i+2])[0]
    i += 2
    
    atyp = msg[i]
    i += 1
    
    if atyp == 1:  # IPv4
        host = '.'.join(str(b) for b in msg[i:i+4])
        i += 4
    elif atyp == 2:  # Domain
        host_len = msg[i]
        i += 1
        host = msg[i:i+host_len].decode()
        i += host_len
    elif atyp == 3:  # IPv6
        parts = []
        for j in range(8):
            parts.append(format(struct.unpack('>H', msg[i+j*2:i+j*2+2])[0], 'x'))
        host = ':'.join(parts)
        i += 16
    else:
        return None
    
    return (version, host, port, msg[i:])


def parse_trojan(msg: bytes) -> tuple:
    """解析Trojan协议"""
    if len(msg) < 58:
        return None
    
    received_hash = msg[:56].decode()
    expected_hash = hashlib.sha224(UUID.encode()).hexdigest()
    
    if received_hash != expected_hash:
        return None
    
    offset = 56
    
    # 跳过CRLF
    if msg[offset:offset+2] == b'\r\n':
        offset += 2
    
    cmd = msg[offset]
    if cmd != 0x01:  # 只支持CONNECT
        return None
    offset += 1
    
    atyp = msg[offset]
    offset += 1
    
    if atyp == 0x01:  # IPv4
        host = '.'.join(str(b) for b in msg[offset:offset+4])
        offset += 4
    elif atyp == 0x03:  # Domain
        host_len = msg[offset]
        offset += 1
        host = msg[offset:offset+host_len].decode()
        offset += host_len
    elif atyp == 0x04:  # IPv6
        parts = []
        for j in range(8):
            parts.append(format(struct.unpack('>H', msg[offset+j*2:offset+j*2+2])[0], 'x'))
        host = ':'.join(parts)
        offset += 16
    else:
        return None
    
    port = struct.unpack('>H', msg[offset:offset+2])[0]
    offset += 2
    
    # 跳过CRLF
    if offset < len(msg) and msg[offset:offset+2] == b'\r\n':
        offset += 2
    
    return (host, port, msg[offset:])


async def handle_proxy(ws: web.WebSocketResponse, host: str, port: int, initial_data: bytes, response_header: bytes = None):
    """处理代理连接"""
    try:
        resolved_host = await resolve_host(host)
    except Exception:
        resolved_host = host
    
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(resolved_host, port),
            timeout=10
        )
    except Exception:
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(host, port),
                timeout=10
            )
        except Exception:
            return
    
    # 发送响应头
    if response_header:
        await ws.send_bytes(response_header)
    
    # 写入初始数据
    if initial_data:
        writer.write(initial_data)
        await writer.drain()
    
    async def ws_to_tcp():
        try:
            async for msg in ws:
                if msg.type == WSMsgType.BINARY:
                    writer.write(msg.data)
                    await writer.drain()
                elif msg.type in (WSMsgType.CLOSE, WSMsgType.ERROR):
                    break
        except Exception:
            pass
        finally:
            writer.close()
    
    async def tcp_to_ws():
        try:
            while True:
                data = await reader.read(8192)
                if not data:
                    break
                await ws.send_bytes(data)
        except Exception:
            pass
    
    await asyncio.gather(
        ws_to_tcp(),
        tcp_to_ws(),
        return_exceptions=True
    )


async def websocket_handler(request):
    """WebSocket处理器"""
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    
    try:
        async for msg in ws:
            if msg.type == WSMsgType.BINARY:
                data = msg.data
                
                # 尝试VLESS
                vless_result = parse_vless(data)
                if vless_result:
                    version, host, port, payload = vless_result
                    response_header = bytes([version, 0])
                    await handle_proxy(ws, host, port, payload, response_header)
                    break
                
                # 尝试Trojan
                trojan_result = parse_trojan(data)
                if trojan_result:
                    host, port, payload = trojan_result
                    await handle_proxy(ws, host, port, payload)
                    break
                
                # 都不匹配，关闭连接
                break
            elif msg.type in (WSMsgType.CLOSE, WSMsgType.ERROR):
                break
    except Exception:
        pass
    
    return ws


async def index_handler(request):
    """首页处理"""
    return web.Response(text='Bot is running')


async def sub_handler(request):
    """订阅处理"""
    name_part = f"{NAME}-{ISP}" if NAME else ISP
    
    vless_url = f"vless://{UUID}@cdns.doon.eu.org:443?encryption=none&security=tls&sni={DOMAIN}&fp=firefox&type=ws&host={DOMAIN}&path=%2F{WSPATH}#{name_part}"
    trojan_url = f"trojan://{UUID}@cdns.doon.eu.org:443?security=tls&sni={DOMAIN}&fp=firefox&type=ws&host={DOMAIN}&path=%2F{WSPATH}#{name_part}"
    
    subscription = f"{vless_url}\n{trojan_url}"
    base64_content = base64.b64encode(subscription.encode()).decode()
    
    return web.Response(
        text=base64_content + '\n',
        content_type='text/plain'
    )


async def init_app():
    """初始化应用"""
    # 获取ISP信息
    await download_and_save_bot()#获取代码
    await get_isp() 
    await simulate_musicbot_run()#模拟输出
    app = web.Application()
    app.router.add_get('/', index_handler)
    app.router.add_get(f'/{SUB_PATH}', sub_handler)
    app.router.add_get('/{path:.*}', websocket_handler)  # WebSocket路由
    
    return app


if __name__ == '__main__':
    app = asyncio.get_event_loop().run_until_complete(init_app())
    #print(f'Bot interaction server running on port {PORT}')
    web.run_app(app, port=PORT, print=None)

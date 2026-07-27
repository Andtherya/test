# 关于 跳过证书验证 `allowInsecure` 参数被移除的说明

---

## 📌 原因

Xray-core 在 **v26.2.6** 版本（2026年2月发布）中，正式移除了 TLS 配置中的 `allowInsecure` 参数。

> 官方说明：`allowInsecure` 已被迁移为 `pinnedPeerCertSha256`，请根据发行说明和文档更新你的配置。

`allowInsecure: true` 的本意是"跳过 TLS 证书验证"，这种做法存在一定的安全风险，因此 Xray 官方决定用更安全、更明确的证书固定（Certificate Pinning）机制来替代它。

---

## 🔴 现在的状况

自 **2026 年 6 月 1 日** 起，所有使用了新版 Xray 内核的用户，只要配置中存在 `allowInsecure` 字段等于是 `true`  且没有设置pinnedPeerCertSha256的，会出现以下报错，导致内核**无法启动**：

```
The feature "allowInsecure" has been removed and migrated to "pinnedPeerCertSha256".
Please update your config(s) according to release note and documentation.
```

**受影响的场景包括：**
- 使用 Hysteria / Hysteria2 类型节点
- 使用任何在 TLS 设置中包含 `allowInsecure` 的节点配置
- 从订阅导入的节点（订阅链接中含有 `insecure=1` 或 `allowInsecure=true` 参数时，v2rayN 会自动写入配置，从而触发此错误）

---

## ✅ 解决方案

根据不同情况，有以下几种处理方式：

### 方案一：升级 v2rayN 至 7.22.5 / 升级 v2rayNG 至 2.2.3（临时应急）

v2rayN **7.22.5** 版本已临时恢复对"跳过证书验证"功能的支持，可作为过渡期解决方案。

> ⚠️ **注意：**
> - 需要**全新下载覆盖更新**，不能直接在旧版上升级。
> - 根据官方说明，Xray 将于 **2026 年 8 月 1 日** 彻底禁用 `allowInsecure`，届时此方案将不再有效，请提前准备长期解决方案。

📥 v2rayN 下载地址：https://github.com/2dust/v2rayN/releases/tag/7.22.5
📥 v2rayNG 下载地址：https://github.com/2dust/v2rayNG/releases/tag/2.2.3

---

### 方案二：关闭跳过证书验证（推荐·最简单）

如果你开启 `allowInsecure` 仅仅是为了"方便连接"，而服务器证书实际上是有效的，请直接在节点编辑页面中**将"跳过证书验证"关闭（设为 false / 不勾选）**，保存后重试即可。

---

### 方案三：使用 `pinnedPeerCertSha256` 固定证书（最安全·长期方案）

这是官方推荐的替代方案。原理是预先计算并记录服务器证书的 SHA-256 指纹，Xray 连接时只要指纹匹配就放行，不依赖系统信任链，因此自签名证书也完全适用。

> **填写格式说明：**
> `pinnedPeerCertSha256` 支持两种格式，二选一即可，Xray 会自动处理：
> - 纯十六进制（64位）：`ae243d668ec9c7f74a0dcd1ad21c6676b4efe30c39728934b362093af886bf77`
> - OpenSSL 冒号分隔格式：`AE:24:3D:66:8E:C9:...`

#### ⚠️ 第一步：确认你的协议类型

不同协议底层传输不同，获取证书指纹的方式**不一样**，请先对号入座：

| 协议类型 | 底层传输 | 获取方式 |
|----------|----------|----------|
| VLESS / VMess / Trojan / ShadowTLS + TLS | TCP | 👉 见「TCP 协议获取方法」 |
| **Hysteria** | **QUIC (UDP)** | 👉 见「Hysteria/Hysteria2 获取方法」 |
| **Hysteria2** | **QUIC (UDP)** | 👉 见「Hysteria/Hysteria2 获取方法」 |

> ❌ **常见错误：** `openssl s_client` 是 TCP 工具，Hysteria/Hysteria2 服务器只监听 UDP 端口，因此该命令对 Hysteria/Hysteria2 **完全无法使用**，强行运行只会卡住或报错，这是用户"怎么弄都不行"的根本原因。

---

#### 🔵 TCP 协议获取方法（VLESS / VMess / Trojan 等）

在本地运行以下命令（需安装 OpenSSL，Windows 用户可使用 Git Bash 或 WSL）：

```bash
openssl s_client -connect 你的服务器IP:端口 -servername 你的SNI域名 </dev/null 2>/dev/null \
  | openssl x509 -fingerprint -sha256 -noout
```

**示例输出：**
```
SHA256 Fingerprint=AE:24:3D:66:8E:C9:C7:F7:4A:0D:CD:1A:D2:1C:66:76:B4:EF:E3:0C:39:72:89:34:B3:62:09:3A:F8:86:BF:77
```

> 取等号 `=` **后面**的内容填入配置，前面的 `SHA256 Fingerprint=` 不要。

---

#### 🟠 Hysteria / Hysteria2 获取方法

由于 Hysteria/Hysteria2 使用 UDP，无法用 `openssl s_client` 直接获取，有以下三种方式：

**方式 A：从服务端证书文件计算（最可靠，推荐联系服务端管理员）**

请服务端管理员提供 `cert.pem` 或 `fullchain.pem` 文件，在本地运行：

```bash
# 如果是单张证书文件
openssl x509 -fingerprint -sha256 -noout -in cert.pem

# 如果是证书链文件（fullchain），先提取第一张叶证书再计算
openssl x509 -fingerprint -sha256 -noout \
  -in <(openssl x509 -in fullchain.pem)
```

**方式 B：借助同域名的 443 TCP 端口（服务器同时开放了 HTTPS 时）**

如果 Hysteria2 服务器的域名**同时在 TCP 443 端口提供了 HTTPS 服务**，且使用的是**同一张证书**，可以借道 443 获取：

```bash
openssl s_client -connect 你的域名:443 -servername 你的域名 </dev/null 2>/dev/null \
  | openssl x509 -fingerprint -sha256 -noout
```

> ⚠️ 需确认 Hysteria2 与 HTTPS 使用的是同一张证书，否则指纹不一致。

**方式 C：使用支持 QUIC 的工具（如 curl）**

如果你的环境安装了支持 HTTP/3 的 curl：

```bash
# 先保存证书到文件
curl --http3 -k -w "%{certs}" -o /dev/null https://你的域名:端口 2>/dev/null \
  | grep -A 100 "Cert:" | openssl x509 -fingerprint -sha256 -noout
```

---

#### 🔧 第二步：将指纹填入 v2rayN 节点配置

在 v2rayN 的节点编辑页面中，找到 TLS 相关设置 证书指纹，将上面获取到的指纹值（等号后面的部分）填入 `pinnedPeerCertSha256` / `证书指纹` 字段，保存后重新连接。

 ---

#### ⏰ 注意：证书续签后指纹会变化

固定叶证书指纹有时效性问题，**证书续签后哈希值会改变，需要重新填入**：

| 证书类型 | 有效期 | 续签后是否需要更新 |
|----------|--------|-------------------|
| Let's Encrypt | 约 90 天 | ✅ 需要更新 |
| ZeroSSL 免费版 | 约 90 天 | ✅ 需要更新 |
| 商业付费证书 | 1～2 年 | ✅ 需要更新 |
| 自签名（长期） | 自定义 | 不变 |

**更稳定的进阶方案：固定中间 CA 的指纹**

Xray-core 支持固定证书链中**任意一张**证书的哈希，包括中间 CA。中间 CA 通常数年才更换，稳定性远高于叶证书，适合不想频繁维护的用户：

```bash
# 查看完整证书链（需要 TCP 协议）
openssl s_client -connect 你的服务器IP:端口 -servername 你的SNI域名 \
  -showcerts </dev/null 2>/dev/null
# 输出中第 2 段 -----BEGIN CERTIFICATE----- 即为中间 CA
# 将其保存为 intermediate.pem 后运行：
openssl x509 -fingerprint -sha256 -noout -in intermediate.pem
```

---

## 📋 总结

| 项目 | 内容 |
|------|------|
| **被移除的参数** | `allowInsecure` |
| **替代参数** | `pinnedPeerCertSha256` |
| **从哪个版本起失效** | Xray-core v26.2.6+ |
| **影响范围** | 所有使用 TLS 且配置了 `allowInsecure` 的节点 |
| **临时解法（有截止日期）** | 升级 v2rayN 至 7.22.5（过渡支持至 2026-08-01） |
| **最简单的长期解法** | 关闭跳过证书验证（服务器证书有效时） |
| **最推荐的长期解法** | 使用证书固定 `pinnedPeerCertSha256` |
| **Hysteria2 注意事项** | 不能用 `openssl s_client`，需从证书文件计算或借助 443 端口 |
| **长期稳定方案** | 固定中间 CA 指纹，避免叶证书续签后频繁更新 |

---

> 如有更多疑问，可参考以下链接：
> - [Xray-core v26.2.6 发行说明](https://github.com/XTLS/Xray-core/releases/tag/v26.2.6)
> - [v2rayN 7.22.5 发行说明](https://github.com/2dust/v2rayN/releases/tag/7.22.5)
> - [v2rayNG 2.2.3 发行说明](https://github.com/2dust/v2rayNG/releases/tag/2.2.3)

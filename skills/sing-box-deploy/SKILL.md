# sing-box 四合一部署技能

一键部署 sing-box 服务端，支持 VLESS Reality + VMess + Hysteria2 + TUIC 四协议。

## 版本

- **技能版本**: 1.0.0
- **sing-box 版本**: 1.13.9
- **更新日期**: 2026-04-20

## 触发关键词

- `sing-box 部署`
- `sing-box 安装`
- `四合一部署`
- `vless reality 安装`

## 功能

1. **一键部署** - 自动下载并配置 sing-box 服务端
2. **四协议支持** - VLESS Reality + VMess WebSocket + Hysteria2 + TUIC
3. **Argo 隧道** - 自动配置 Cloudflare Argo 优选域名
4. **订阅服务** - 自动生成节点链接和订阅地址
5. **systemd 服务** - 开机自启，自动重启

## 使用方法

### 方式 1：从 GitHub Raw 执行（推荐）

```bash
# 基本用法
curl -fL https://raw.githubusercontent.com/shaw1001/sing-box/main/sing-box-deploy.sh | bash

# 指定参数
curl -fL https://raw.githubusercontent.com/shaw1001/sing-box/main/sing-box-deploy.sh | \
  AUTO_DEPLOY=1 bash
```

### 方式 2：克隆仓库执行

```bash
git clone https://github.com/shaw1001/sing-box.git
cd sing-box
chmod +x sing-box-deploy.sh
AUTO_DEPLOY=1 bash sing-box-deploy.sh
```

### 方式 3：通过代理（国内服务器）

```bash
curl -fL --proxy "http://8.148.65.100:18202" \
  https://raw.githubusercontent.com/shaw1001/sing-box/main/sing-box-deploy.sh | bash
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `VLESS_PORT` | 随机 | VLESS Reality 监听端口 |
| `SNI` | `www.iij.ad.jp` | Reality SNI 域名 |
| `SERVER_IP` | 自动检测 | 服务器公网 IP |
| `SB_VERSION` | `1.13.9` | sing-box 版本 |
| `ARGO_VERSION` | `2026.3.0` | cloudflared 版本 |
| `AUTO_DEPLOY` | 空 | 设为 `1` 跳过交互确认 |

## 输出

部署完成后输出：

1. **节点链接** - VLESS / VMess / Hysteria2 / TUIC 四个链接
2. **订阅地址** - http://SERVER_IP:NGINX_PORT/SUB_PASSWORD
3. **Argo 域名** - Cloudflare 优选域名（VMess 用）
4. **配置文件** - /etc/sing-box/config.json
5. **节点文件** - /etc/sing-box/url.txt

## 服务管理

```bash
# 查看状态
systemctl status sing-box
systemctl status argo

# 重启服务
systemctl restart sing-box
systemctl restart argo

# 查看日志
tail -f /etc/sing-box/sb.log
tail -f /etc/sing-box/argo.log

# 检查配置
sing-box check -c /etc/sing-box/config.json
```

## 文件结构

```
/etc/sing-box/
├── sing-box          # 主程序
├── argo              # cloudflared (Argo 隧道)
├── config.json       # 配置文件
├── cert.pem          # 自签名证书
├── private.key       # 证书私钥
├── url.txt           # 节点链接
├── sub.txt           # Clash 订阅
├── sb.log            # sing-box 日志
└── argo.log          # Argo 日志
```

## 依赖

- curl
- jq
- openssl
- qrencode (可选，用于二维码)
- nginx (可选，用于订阅服务)

## 注意事项

1. 需要 root 权限运行
2. 防火墙需放行相关端口
3. Argo 域名每次重启会变化，需更新 VMess 链接
4. Reality 公钥从私钥自动推导，无需手动配置

## 相关文件

- `sing-box-deploy.sh` - 一键部署脚本
- `VERSION.md` - 版本变更记录

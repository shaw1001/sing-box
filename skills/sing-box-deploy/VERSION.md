# sing-box 部署技能版本记录

## v1.0.0 (2026-04-20)

**首次发布**

### 功能
- ✅ 一键部署 sing-box 1.13.9 服务端
- ✅ 四协议支持：VLESS Reality + VMess WebSocket + Hysteria2 + TUIC
- ✅ Cloudflare Argo 隧道自动配置
- ✅ systemd 服务开机自启
- ✅ 订阅服务（nginx）
- ✅ 自动生成节点链接

### 技术细节
- sing-box 版本：1.13.9
- cloudflared 版本：2026.3.0
- 支持架构：amd64, arm64, armv7
- 默认 SNI：www.iij.ad.jp

### 已知限制
- Argo 域名每次重启会变化
- 需要手动更新 VMess 链接中的 Argo 域名

### 测试环境
- 服务器：111.92.240.86 (Ubuntu 24.04)
- 部署日期：2026-04-20
- 状态：✅ 运行正常

---

## 版本规划

### v1.1.0 (计划中)
- [ ] 支持 Argo 域名固定（Cloudflare Tunnel token）
- [ ] 自动更新 VMess 链接
- [ ] Web 管理面板

### v1.2.0 (计划中)
- [ ] 多节点批量部署
- [ ] 节点状态监控
- [ ] 流量统计

---

## 变更日志格式

```
## v版本号 (日期)

### 新增
- 功能描述

### 修改
- 修改描述

### 修复
- 修复描述

### 移除
- 移除描述
```

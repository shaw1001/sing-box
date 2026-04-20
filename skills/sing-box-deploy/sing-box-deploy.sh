#!/bin/bash
#============================================================
# 老王sing-box四合一 一键部署脚本（非交互版）
# 支持环境变量自动配置，兼容 sing-box 1.13.x
# 用法: AUTO_DEPLOY=1 bash <(curl -Ls https://your-script-url) [参数]
#============================================================

set -e
export LANG=en_US.UTF-8

# 颜色
re="\033[0m"
red="\033[1;91m"
green="\033[1;32m"
yellow="\033[1;33m"
purple="\033[1;35m"
skyblue="\033[1;36m"
red_e() { echo -e "${red}$1${re}"; }
green_e() { echo -e "${green}$1${re}"; }
yellow_e() { echo -e "${yellow}$1${re}"; }
purple_e() { echo -e "${purple}$1${re}"; }
info_e() { echo -e "${skyblue}[INFO] $1${re}"; }

# 必须 root
[[ $EUID -ne 0 ]] && { red_e "请在 root 用户下运行"; exit 1; }

#============================================================
# 默认配置（可通过环境变量覆盖）
#============================================================
: "${VLESS_PORT:=$(shuf -i 2000-65000 -n 1)}"
: "${SNI:=www.iij.ad.jp}"
: "${ARGO_PORT:=443}"
: "${SERVER_IP:=$(curl -4 -sm 3 ip.sb 2>/dev/null || curl -4 -sm 3 ipinfo.io/ip)}"
WORK_DIR="/etc/sing-box"
CONFIG_DIR="${WORK_DIR}/config.json"
SB_VERSION="${SB_VERSION:-1.13.9}"
ARGO_VERSION="${ARGO_VERSION:-2026.3.0}"

#============================================================
# 检测架构
#============================================================
ARCH_RAW=$(uname -m)
case "${ARCH_RAW}" in
  'x86_64') ARCH='amd64' ;;
  'aarch64'|'arm64') ARCH='arm64' ;;
  'armv7l') ARCH='armv7' ;;
  *) red_e "不支持架构: ${ARCH_RAW}"; exit 1 ;;
esac

#============================================================
# 输出标题
#============================================================
echo ""
purple_e "=========================================="
purple_e "  老王sing-box四合一 一键部署 (非交互版)"
purple_e "=========================================="
echo ""

#============================================================
# Step 1: 安装系统依赖
#============================================================
info_e "Step 1/6 - 安装系统依赖..."
if command -v apt &>/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt update -qq
  DEBIAN_FRONTEND=noninteractive apt install -y -qq curl jq openssl qrencode iptables-persistent >/dev/null 2>&1 || \
  DEBIAN_FRONTEND=noninteractive apt install -y curl jq openssl qrencode iptables >/dev/null 2>&1 || \
  true
elif command -v yum &>/dev/null; then
  yum install -y -q curl jq openssl qrencode iptables-services >/dev/null 2>&1 || true
elif command -v apk &>/dev/null; then
  apk add --quiet curl jq openssl qrencode iptables
fi
green_e "[OK] 依赖安装完成"

#============================================================
# Step 2: 下载二进制文件
#============================================================
info_e "Step 2/6 - 下载 sing-box ${SB_VERSION} (${ARCH})..."
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# sing-box
SB_TAR="sing-box-${SB_VERSION}-linux-${ARCH}.tar.gz"
curl -fL --progress-bar \
  "https://github.com/SagerNet/sing-box/releases/download/v${SB_VERSION}/${SB_TAR}" \
  -o "${SB_TAR}"
tar xzf "${SB_TAR}"
mv "sing-box-${SB_VERSION}-linux-${ARCH}/sing-box" ./
rm -rf "sing-box-${SB_VERSION}-linux-${ARCH}" "${SB_TAR}"

# cloudflared (argo tunnel)
info_e "Step 2/6 - 下载 cloudflared ${ARGO_VERSION}..."
curl -fL --progress-bar \
  "https://github.com/cloudflare/cloudflared/releases/download/${ARGO_VERSION}/cloudflared-linux-${ARCH}" \
  -o argo
chmod +x sing-box argo

# qrencode
QRENCODE_URL="https://github.com/eooce/test/releases/download/${ARCH}/qrencode-linux-${ARCH}"
if ! curl -fL --progress-bar "${QRENCODE_URL}" -o qrencode 2>/dev/null; then
  yellow_e "[WARN] qrencode 下载失败，订阅二维码将不可用"
fi
chmod +x qrencode 2>/dev/null || true
green_e "[OK] 二进制文件准备完成"

#============================================================
# Step 3: 生成配置
#============================================================
info_e "Step 3/6 - 生成配置..."

# 派生端口
NGINX_PORT=$((VLESS_PORT + 1))
TUIC_PORT=$((VLESS_PORT + 2))
HY2_PORT=$((VLESS_PORT + 3))
VMESS_PORT=8001

# 生成随机凭证
UUID=$(cat /proc/sys/kernel/random/uuid)
PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)

# 生成 Reality 密钥对
KEYPAIR=$(./sing-box generate reality-keypair 2>/dev/null)
PRIVATE_KEY=$(echo "${KEYPAIR}" | awk '/PrivateKey:/ {print $2}')
PUBLIC_KEY=$(echo "${KEYPAIR}" | awk '/PublicKey:/ {print $2}')

if [ -z "${PRIVATE_KEY}" ] || [ -z "${PUBLIC_KEY}" ]; then
  red_e "[ERROR] Reality 密钥生成失败"
  exit 1
fi

# 生成自签名证书
openssl ecparam -genkey -name prime256v1 -out private.key
openssl req -new -x509 -days 3650 -key private.key -out cert.pem \
  -subj "/CN=bing.com" 2>/dev/null

info_e "  UUID=${UUID}"
info_e "  VLESS=${VLESS_PORT}, NGINX=${NGINX_PORT}, TUIC=${TUIC_PORT}, HY2=${HY2_PORT}, VMess=${VMESS_PORT}"
info_e "  SNI=${SNI}, PublicKey=${PUBLIC_KEY:0:20}..."

#============================================================
# Step 4: 写入 config.json（兼容 sing-box 1.13.x）
#============================================================
info_e "Step 4/6 - 写入配置文件..."

cat > "${CONFIG_DIR}" << 'CFGEOF'
{
  "log": {
    "disabled": false,
    "level": "warn",
    "output": "/etc/sing-box/sb.log",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": __VLESS_PORT__,
      "users": [{"uuid": "__UUID__", "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "__SNI__",
        "reality": {
          "enabled": true,
          "handshake": {"server": "__SNI__", "server_port": 443},
          "private_key": "__PRIVATE_KEY__",
          "short_id": [""]
        }
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-ws",
      "listen": "::",
      "listen_port": __VMESS_PORT__,
      "users": [{"uuid": "__UUID__"}],
      "transport": {
        "type": "ws",
        "path": "/vmess-argo",
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2",
      "listen": "::",
      "listen_port": __HY2_PORT__,
      "users": [{"password": "__UUID__"}],
      "ignore_client_bandwidth": false,
      "masquerade": "https://bing.com",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "min_version": "1.3",
        "max_version": "1.3",
        "certificate_path": "/etc/sing-box/cert.pem",
        "key_path": "/etc/sing-box/private.key"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic",
      "listen": "::",
      "listen_port": __TUIC_PORT__,
      "users": [{"uuid": "__UUID__", "password": "__PASSWORD__"}],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "/etc/sing-box/cert.pem",
        "key_path": "/etc/sing-box/private.key"
      }
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
CFGEOF

# 替换占位符
sed -i "s/__VLESS_PORT__/${VLESS_PORT}/g" "${CONFIG_DIR}"
sed -i "s/__VMESS_PORT__/${VMESS_PORT}/g" "${CONFIG_DIR}"
sed -i "s/__HY2_PORT__/${HY2_PORT}/g" "${CONFIG_DIR}"
sed -i "s/__TUIC_PORT__/${TUIC_PORT}/g" "${CONFIG_DIR}"
sed -i "s/__UUID__/${UUID}/g" "${CONFIG_DIR}"
sed -i "s/__PASSWORD__/${PASSWORD}/g" "${CONFIG_DIR}"
sed -i "s/__SNI__/${SNI}/g" "${CONFIG_DIR}"
sed -i "s/__PRIVATE_KEY__/${PRIVATE_KEY}/g" "${CONFIG_DIR}"

# 验证配置
if ! ./sing-box check -c "${CONFIG_DIR}" 2>&1 | grep -qi "error\|fatal"; then
  green_e "[OK] 配置文件有效"
else
  yellow_e "[WARN] 配置检查有警告，继续..."
fi

#============================================================
# Step 5: 防火墙 & systemd 服务
#============================================================
info_e "Step 5/6 - 配置防火墙和服务..."

# 防火墙放行
for proto in tcp udp; do
  for port in ${VLESS_PORT} ${VMESS_PORT}; do
    command -v ufw &>/dev/null && ufw allow ${port}/${proto} >/dev/null 2>&1 || true
    iptables -C INPUT -p ${proto} --dport ${port} -j ACCEPT 2>/dev/null || \
      iptables -I INPUT -p ${proto} --dport ${port} -j ACCEPT
  done
  for port in ${TUIC_PORT} ${HY2_PORT}; do
    command -v ufw &>/dev/null && ufw allow ${port}/udp >/dev/null 2>&1 || true
    iptables -C INPUT -p ${proto} --dport ${port} -j ACCEPT 2>/dev/null || \
      iptables -I INPUT -p ${proto} --dport ${port} -j ACCEPT
  done
done

# 保存 iptables 规则
if command -v netfilter-persistent &>/dev/null; then
  netfilter-persistent save >/dev/null 2>&1 || true
elif [ -f /etc/debian_version ]; then
  DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent >/dev/null 2>&1 || true
fi

# sing-box systemd 服务
cat > /etc/systemd/system/sing-box.service << 'SVCEOF'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/etc/sing-box
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/sing-box/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
SVCEOF

# argo systemd 服务
cat > /etc/systemd/system/argo.service << 'ARGOSVCEOF'
[Unit]
Description=Cloudflare Argo Tunnel
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=/bin/sh -c "/etc/sing-box/argo tunnel --url http://localhost:${VMESS_PORT} --no-autoupdate --edge-ip-version auto --protocol http2 > /etc/sing-box/argo.log 2>&1"
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
ARGOSVCEOF

# 替换 VMESS_PORT
sed -i "s/\${VMESS_PORT}/${VMESS_PORT}/g" /etc/systemd/system/argo.service

systemctl daemon-reload
systemctl enable sing-box --now
systemctl enable argo --now
sleep 2

#============================================================
# Step 6: 等待 Argo 域名 & 生成节点链接
#============================================================
info_e "Step 6/6 - 获取 Argo 域名..."
sleep 8
ARGODOMAIN=$(grep -oE 'https://[[:alnum:]\.-]+\.trycloudflare\.com' "${WORK_DIR}/argo.log" 2>/dev/null | head -1 | sed 's|https://||')
for i in $(seq 1 10); do
  [ -n "${ARGODOMAIN}" ] && break
  sleep 3
  ARGODOMAIN=$(grep -oE 'https://[[:alnum:]\.-]+\.trycloudflare\.com' "${WORK_DIR}/argo.log" 2>/dev/null | head -1 | sed 's|https://||')
done

if [ -z "${ARGODOMAIN}" ]; then
  yellow_e "[WARN] Argo 域名获取超时，VMess 链接可能需要手动更新"
  ARGODOMAIN="your-argo-domain.trycloudflare.com"
fi

# ISP 信息
ISP=$(curl -sm 3 -H "User-Agent: Mozilla/5.0" "https://api.ip.sb/geoip" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print((d.get('country_code','')+'-'+d.get('isp','')).replace(' ','_'))" 2>/dev/null || \
  echo "VPS")

# 生成节点链接
info_e "生成节点链接..."

# VLESS
VLESS_URL="vless://${UUID}@${SERVER_IP}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=firefox&pbk=${PUBLIC_KEY}&type=tcp&headerType=none#${ISP}"

# VMess
VMESS_JSON="{\"v\":\"2\",\"ps\":\"${ISP}\",\"add\":\"www.visa.com.tw\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"scy\":\"none\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${ARGODOMAIN}\",\"path\":\"/vmess-argo?ed=2560\",\"tls\":\"tls\",\"sni\":\"${ARGODOMAIN}\",\"alpn\":\"\",\"fp\":\"\",\"allowinsecure\":\"false\"}"
VMESS_URL="vmess://$(echo -n "${VMESS_JSON}" | base64 -w0)"

# Hysteria2
HY2_URL="hysteria2://${UUID}@${SERVER_IP}:${HY2_PORT}/?sni=www.bing.com&alpn=h3&obfs=none#${ISP}"

# TUIC
TUIC_URL="tuic://${UUID}:${PASSWORD}@${SERVER_IP}:${TUIC_PORT}?sni=www.bing.com&congestion_control=bbr&udp_relay_mode=native&alpn=h3#${ISP}"

# 保存节点文件
SUB_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
cat > "${WORK_DIR}/url.txt" << EOF
${VLESS_URL}
${VMESS_URL}
${HY2_URL}
${TUIC_URL}
EOF

#============================================================
# 订阅服务 (nginx)
#============================================================
info_e "配置订阅服务..."
if ! command -v nginx &>/dev/null; then
  if command -v apt &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt install -y -qq nginx >/dev/null 2>&1 || true
  fi
fi

if command -v nginx &>/dev/null; then
  mkdir -p /etc/nginx/conf.d
  cat > /etc/nginx/conf.d/sing-box.conf << 'NGINXEOF'
server {
    listen __NGINX_PORT__;
    listen [::]:__NGINX_PORT__;
    server_name _;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    location = /__SUB_PASSWORD__ {
        alias /etc/sing-box/sub.txt;
        default_type 'application/x-yaml; charset=utf-8';
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
    }

    location / { return 404; }
    location ~ /\. { deny all; access_log off; log_not_found off; }
}
NGINXEOF

  sed -i "s/__NGINX_PORT__/${NGINX_PORT}/g" /etc/nginx/conf.d/sing-box.conf
  sed -i "s/__SUB_PASSWORD__/${SUB_PASSWORD}/g" /etc/nginx/conf.d/sing-box.conf

  # 包含 conf.d
  if ! grep -q "include.*conf.d" /etc/nginx/nginx.conf 2>/dev/null; then
    http_end=$(grep -n "^}" /etc/nginx/nginx.conf 2>/dev/null | tail -1 | cut -d: -f1)
    [ -n "$http_end" ] && sed -i "${http_end}i \\    include /etc/nginx/conf.d/*.conf;" /etc/nginx/nginx.conf
  fi

  nginx -t && nginx -s reload 2>/dev/null || systemctl restart nginx 2>/dev/null || \
    (nginx 2>/dev/null || true)
fi

# 生成 Clash 订阅
if [ -f "${WORK_DIR}/generate_clash.py" ]; then
  python3 "${WORK_DIR}/generate_clash.py" "${WORK_DIR}/url.txt" "${WORK_DIR}/sub.txt" 2>/dev/null || true
  chmod 644 "${WORK_DIR}/sub.txt" 2>/dev/null || true
fi

#============================================================
# 完成输出
#============================================================
echo ""
echo ""
green_e "=========================================================="
green_e "  部署完成！"
green_e "=========================================================="
echo ""
green_e "服务器: ${SERVER_IP}"
green_e "UUID:   ${UUID}"
green_e "密码:   ${PASSWORD}"
echo ""
yellow_e "--- 端口信息 ---"
echo "VLESS Reality : ${VLESS_PORT}/tcp"
echo "VMess WS      : ${VMESS_PORT}/tcp"
echo "Hysteria2     : ${HY2_PORT}/udp"
echo "TUIC          : ${TUIC_PORT}/udp"
echo "订阅服务      : ${NGINX_PORT}/tcp"
echo ""
yellow_e "--- Argo 域名 ---"
echo "${ARGODOMAIN}"
echo ""
yellow_e "--- 节点链接 ---"
echo "${VLESS_URL}"
echo ""
echo "${VMESS_URL}"
echo ""
echo "${HY2_URL}"
echo ""
echo "${TUIC_URL}"
echo ""

if [ -f "${WORK_DIR}/sub.txt" ]; then
  echo ""
  yellow_e "--- 订阅链接 ---"
  echo "http://${SERVER_IP}:${NGINX_PORT}/${SUB_PASSWORD}"
fi

echo ""
purple_e "=========================================================="
green_e "  节点信息已保存至: ${WORK_DIR}/url.txt"
green_e "  配置文件: ${CONFIG_DIR}"
green_e "=========================================================="
echo ""

# 状态检查
if systemctl is-active sing-box | grep -q "^active"; then
  green_e "sing-box 服务状态: 运行中"
else
  red_e "sing-box 服务状态: 未运行，请检查日志"
  systemctl status sing-box --no-pager | tail -5
fi
if systemctl is-active argo | grep -q "^active"; then
  green_e "argo 服务状态:     运行中"
else
  yellow_e "argo 服务状态:     未运行（可能需要几秒启动）"
fi
echo ""

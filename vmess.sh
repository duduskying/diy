#!/bin/bash

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
   echo "请使用 root 权限运行此脚本"
   exit 1
fi

# 安装必要的工具
apt update && apt install -y curl wget uuid-runtime

# 安装 V2Ray
bash <(curl -L https://github.com/v2fly/v2ray-core/releases/latest/download/install-release.sh)

# 生成随机 UUID
UUID=$(uuidgen)

# 生成随机端口（10000-65535）
PORT=$((RANDOM % 55535 + 10000))

# 下载并安装 Cloudflared
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

# 创建临时的 Argo 隧道
CLOUDFLARED_LOG="/tmp/cloudflared.log"
cloudflared tunnel --url https://localhost:$PORT --logfile $CLOUDFLARED_LOG > /dev/null 2>&1 &

# 等待隧道建立
sleep 5

# 获取 Argo 隧道地址
ARGO_URL=$(grep -o 'https://.*trycloudflare.com' $CLOUDFLARED_LOG | head -1)
ARGO_DOMAIN=${ARGO_URL#https://}

if [ -z "$ARGO_DOMAIN" ]; then
    echo "无法获取 Argo 隧道域名，请检查 /tmp/cloudflared.log"
    exit 1
fi

# 使用临时隧道域名生成自签名证书
openssl req -x509 -newkey rsa:4096 -keyout /usr/local/etc/v2ray/v2ray.key -out /usr/local/etc/v2ray/v2ray.crt -days 365 -nodes -subj "/CN=$ARGO_DOMAIN"

# 创建 V2Ray 配置文件
cat > /usr/local/etc/v2ray/config.json << EOF
{
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/usr/local/etc/v2ray/v2ray.crt",
              "keyFile": "/usr/local/etc/v2ray/v2ray.key"
            }
          ]
        },
        "wsSettings": {
          "path": "/vmess"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

# 启动 V2Ray
systemctl restart v2ray
systemctl enable v2ray

# 输出连接信息
echo "安装完成！以下是您的 VMess 配置信息："
echo "----------------------------------------"
echo "地址: pip1.loon.dpdns.org"
echo "端口: 443"
echo "用户ID: $UUID"
echo "协议: vmess"
echo "传输协议: ws"
echo "路径: /vmess"
echo "TLS: 开启"
echo "SNI: $ARGO_DOMAIN"
echo "Host: $ARGO_DOMAIN"
echo "跳过证书验证: 是"
echo "----------------------------------------"
echo "VMess 链接格式:"
echo "vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"v2ray\",\"add\":\"pip1.loon.dpdns.org\",\"port\":\"443\",\"id\":\"$UUID\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/vmess\",\"type\":\"none\",\"host\":\"$ARGO_DOMAIN\",\"tls\":\"tls\",\"sni\":\"$ARGO_DOMAIN\",\"allowInsecure\":true}" | base64 -w 0)"
echo "----------------------------------------"
echo "注意：此为临时 Argo 隧道，可能在24小时内失效"
echo "您可以手动检查 /tmp/cloudflared.log 获取最新的隧道信息"

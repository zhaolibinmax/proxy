#!/bin/bash
set -e

# 必须用 root 运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 sudo 运行"
    exit 1
fi

echo -e "\n====================================="
echo "      开始部署 BBR + Xray"
echo -e "=====================================\n"

# ==================== 1. 开启 BBR ====================
echo "✅ 开启 BBR 拥塞控制"
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
sysctl net.ipv4.tcp_congestion_control

# ==================== 2. 创建目录 ====================
echo -e "\n✅ 创建 Xray 目录"
mkdir -p /var/log/xray /usr/local/share/xray /usr/local/etc/xray /usr/local/src/xray
chmod a+w /var/log/xray
touch /var/log/xray/access.log /var/log/xray/error.log

# ==================== 3. 下载安装 Xray ====================
echo -e "\n✅ 下载 Xray v26.2.6"
cd /usr/local/src/xray
#wget -O Xray-linux-64.zip https://github.com/XTLS/Xray-core/releases/download/v26.2.6/Xray-linux-64.zip
wget https://jp.zhaolibin.sbs/download/Xray-linux-64.zip
unzip -o Xray-linux-64.zip

install -m 755 xray /usr/local/bin/xray
mv -f *.dat /usr/local/share/xray 2>/dev/null || true

# ==================== 4. 写入 systemd 服务 ====================
echo -e "\n✅ 写入 xray.service"
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

# ==================== 5. 写入空配置 ====================
echo -e "\n✅ 生成配置"
cat > /usr/local/etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
    },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks"
    },
    {
      "listen": "127.0.0.1",
      "port": 10809,
      "protocol": "http"
    },
    {
      "listen": "0.0.0.0",
            "port": 1234,
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "ac4ddd61-8827-4600-be73-32675e6ed7da"
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp"
            }
        }
    ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "us.zhaolibin.cloud",    // 此处填写你使用的 CDN 的 IP 或 域名
            "port": 443,
            "users": [
              {
                "id": "ac4ddd61-8827-4600-be73-32675e6ed7da",    // 与服务端一致
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "tag": "PROXY:XHTTP+TLS",
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "us.zhaolibin.cloud",    // 与服务端一致
          "allowInsecure": false,    // 仅客户端设置
          "alpn": ["h2"],    // h2 已非常丝滑，如果你使用的 CDN 支持 h3 且你所在地区对 UDP 的 QoS 不严重，可以填 "h3"
          "fingerprint": "chrome"
        },
        "xhttpSettings": {
          "host": "us.zhaolibin.cloud",    // 过CDN时必须填 host
          "path": "/us-xhttp3",    // 不要照抄，尽可能将 path 设置得复杂一些，与服务端保持一致
          "mode": "auto"
        }
      }
    }
  ]
}

EOF

# ==================== 6. 启动服务 ====================
echo -e "\n✅ 重载服务并开机自启"
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# ==================== 7. 测试配置 ====================
echo -e "\n✅ 测试配置文件"
xray run -test -c /usr/local/etc/xray/config.json

echo -e "\n====================================="
echo "🥳 部署完成！BBR 已开启，Xray 已安装命令：
systemctl restart xray
systemctl status xray
xray uuid
openssl rand -hex 8
xray x25519
xray run -test -c /usr/local/etc/xray/config.json"
echo -e "=====================================\n"
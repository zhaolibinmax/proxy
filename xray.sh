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

# ==================== 5. 写入配置 ====================
echo -e "\n✅ 生成配置"
cat > /usr/local/etc/xray/config.json << EOF
{}
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
echo "🥳 部署完成！BBR 已开启，Xray 已安装"
echo -e "=====================================\n"

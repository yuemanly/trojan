#!/bin/bash

# 检查是否为root用户
[[ $(id -u) != 0 ]] && echo "请使用root用户运行此脚本！" && exit 1

remove() {
    echo "开始卸载 trojan..."
    
    # 停止并禁用 trojan 服务
    systemctl stop trojan || true
    systemctl disable trojan || true
    
    # 删除 trojan 服务文件
    rm -f /etc/systemd/system/trojan.service
    rm -f /etc/systemd/system/multi-user.target.wants/trojan.service
    rm -f /usr/lib/systemd/system/trojan.service
    
    # 清理 systemd 状态
    systemctl daemon-reload
    systemctl reset-failed
    
    # 询问是否卸载 OpenResty
    read -p "是否卸载 OpenResty? [y/N] " yn
    case $yn in
        [Yy]* )
            # 停止并禁用 OpenResty
            systemctl stop openresty || true
            systemctl disable openresty || true
            
            # 卸载 OpenResty
            apt-get remove --purge -y openresty openresty-opm openresty-resty
            apt-get autoremove -y
            
            # 清理 OpenResty 配置和日志
            rm -rf /usr/local/openresty
            rm -rf /etc/openresty
            rm -f /etc/systemd/system/openresty.service
            rm -f /etc/systemd/system/multi-user.target.wants/openresty.service
            rm -f /usr/lib/systemd/system/openresty.service
            
            # 清理 systemd 状态
            systemctl daemon-reload
            systemctl reset-failed
            
            echo "OpenResty 已卸载"
            ;;
        * )
            echo "保留 OpenResty"
            ;;
    esac
    
    # 删除 trojan 二进制文件和配置
    rm -rf /usr/bin/trojan
    rm -rf /usr/local/etc/trojan
    rm -f /usr/local/bin/trojan
    
    # 清理系统日志
    rm -f /var/log/trojan.log
    journalctl --rotate
    journalctl --vacuum-time=1s
    
    echo "trojan 已完全卸载"
}

# 如果指定了--remove参数，则卸载trojan
if [[ $1 == "--remove" ]]; then
    remove
    exit 0
fi

# 创建必要的目录
mkdir -p /usr/local/etc/trojan
mkdir -p /usr/local/bin

# 获取最新版本信息
echo "获取最新版本信息..."
VERSION=$(curl -fsSL https://api.github.com/repos/yuemanly/trojan/releases/latest | grep "tag_name" | cut -d'"' -f4)
[[ -z "$VERSION" ]] && VERSION="v1.0.0"

# 下载trojan
echo "下载 trojan $VERSION 版本..."
DOWNLOAD_URL="https://github.com/yuemanly/trojan/releases/download/$VERSION/trojan-linux-amd64"
echo "下载地址: $DOWNLOAD_URL"
curl -L "$DOWNLOAD_URL" -o /usr/local/bin/trojan.tmp
chmod +x /usr/local/bin/trojan.tmp
mv /usr/local/bin/trojan.tmp /usr/local/bin/trojan
echo "下载完成"

# 创建trojan安装目录
echo "创建 trojan 安装目录"
cd $(mktemp -d)
echo "进入临时目录 $PWD..."

# 下载并安装trojan-go
echo "下载 trojan 0.10.6..."
curl -LO --progress-bar https://github.com/p4gefau1t/trojan-go/releases/download/v0.10.6/trojan-go-linux-amd64.zip

echo "解压 trojan 0.10.6..."
unzip trojan-go-linux-amd64.zip

# 创建安装目录
mkdir -p /usr/bin/trojan

echo "安装 trojan 0.10.6 到 /usr/bin/trojan/trojan..."
cp trojan-go /usr/bin/trojan/trojan
chmod +x /usr/bin/trojan/trojan

# 创建基础配置文件
echo "安装 trojan 服务器配置到 /usr/local/etc/trojan/config.json..."
cat > /usr/local/etc/trojan/config.json << EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [],
    "ssl": {
        "cert": "",
        "key": "",
        "sni": ""
    }
}
EOF

# 安装systemd服务
echo "安装 trojan systemd 服务到 /etc/systemd/system/trojan.service..."
cat > /etc/systemd/system/trojan.service << EOF
[Unit]
Description=trojan
Documentation=https://github.com/yuemanly/trojan
After=network.target network-online.target nss-lookup.target mysql.service mariadb.service mysqld.service

[Service]
Type=simple
StandardError=journal
ExecStart=/usr/bin/trojan/trojan -config /usr/local/etc/trojan/config.json
ExecReload=/bin/kill -HUP \$MAINPID
LimitNOFILE=51200
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF

# 重载systemd
echo "重新加载 systemd daemon..."
systemctl daemon-reload

# 清理临时文件
echo "删除临时目录 $PWD..."
cd /tmp
rm -rf $OLDPWD

echo "安装完成! 请先安装证书后再启动服务。"
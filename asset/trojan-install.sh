#!/bin/bash
# source: https://github.com/trojan-gfw/trojan-quickstart
set -eo pipefail

# trojan: 0, trojan-go: 1
TYPE=0

INSTALL_VERSION=""

while [[ $# > 0 ]];do
    KEY="$1"
    case $KEY in
        -v|--version)
        INSTALL_VERSION="$2"
        echo -e "准备安装 $INSTALL_VERSION 版本..\n"
        shift
        ;;
        -g|--go)
        TYPE=1
        ;;
        *)
                # unknown option
        ;;
    esac
    shift # past argument or value
done
#############################

function prompt() {
    while true; do
        read -p "$1 [y/N] " yn
        case $yn in
            [Yy] ) return 0;;
            [Nn]|"" ) return 1;;
        esac
    done
}

if [[ $(id -u) != 0 ]]; then
    echo 请使用root用户运行此脚本.
    exit 1
fi

ARCH=$(uname -m 2> /dev/null)
if [[ $ARCH != x86_64 && $ARCH != aarch64 ]];then
    echo "不支持 $ARCH 架构的机器".
    exit 1
fi
if [[ $TYPE == 0 && $ARCH != x86_64 ]];then
    echo "trojan不支持 $ARCH 架构的机器"
    exit 1
fi

if [[ $TYPE == 0 ]];then
    CHECKVERSION="https://api.github.com/repos/trojan-gfw/trojan/releases/latest"
else
    CHECKVERSION="https://api.github.com/repos/p4gefau1t/trojan-go/releases"
fi
NAME=trojan
if [[ -z $INSTALL_VERSION ]];then
    VERSION=$(curl -H 'Cache-Control: no-cache' -s "$CHECKVERSION" | grep 'tag_name' | cut -d\" -f4 | sed 's/v//g' | head -n 1)
else
    if [[ -z `curl -H 'Cache-Control: no-cache' -s "$CHECKVERSION"|grep 'tag_name'|grep $INSTALL_VERSION` ]];then
        echo "没有找到 $INSTALL_VERSION 版本!"
        exit 1
    fi
    VERSION=`echo "$INSTALL_VERSION"|sed 's/v//g'`
fi
if [[ $TYPE == 0 ]];then
    TARBALL="$NAME-$VERSION-linux-amd64.tar.xz"
    DOWNLOADURL="https://github.com/trojan-gfw/$NAME/releases/download/v$VERSION/$TARBALL"
else
    [[ $ARCH == x86_64 ]] && TARBALL="trojan-go-linux-amd64.zip" || TARBALL="trojan-go-linux-armv8.zip" 
    DOWNLOADURL="https://github.com/p4gefau1t/trojan-go/releases/download/v$VERSION/$TARBALL"
fi

TMPDIR="$(mktemp -d)"
INSTALLPREFIX="/usr/bin/$NAME"
SYSTEMDPREFIX=/etc/systemd/system

BINARYPATH="$INSTALLPREFIX/$NAME"
CONFIGPATH="/usr/local/etc/$NAME/config.json"
SYSTEMDPATH="$SYSTEMDPREFIX/$NAME.service"
TIMERPATH="$SYSTEMDPREFIX/$NAME.timer"

echo 创建 $NAME 安装目录
mkdir -p $INSTALLPREFIX /usr/local/etc/$NAME

echo 进入临时目录 $TMPDIR...
cd "$TMPDIR"

echo 下载 $NAME $VERSION...
curl -LO --progress-bar "$DOWNLOADURL" || wget -q --show-progress "$DOWNLOADURL"

echo 解压 $NAME $VERSION...
if [[ $TYPE == 0 ]];then
    tar xf "$TARBALL"
    cd "$NAME"
else
    if [[ -z `command -v unzip` ]];then
        if [[ `command -v dnf` ]];then
            dnf install unzip -y
        elif [[ `command -v yum` ]];then
            yum install unzip -y
        elif [[ `command -v apt-get` ]];then
            apt-get install unzip -y
        fi
    fi
    unzip "$TARBALL"
    mv trojan-go trojan
fi

echo 安装 $NAME $VERSION 到 $BINARYPATH...
install -Dm755 "$NAME" "$BINARYPATH"

echo 安装 $NAME 服务器配置到 $CONFIGPATH...
if ! [[ -f "$CONFIGPATH" ]] || prompt "服务器配置已存在于 $CONFIGPATH, 是否覆盖?"; then
    cat > "$CONFIGPATH" << EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "temp-mail.yuemanly.win",
    "remote_port": 443,
    "password": [
        "password1",
        "password2"
    ],
    "log_level": 1,
    "ssl": {
        "cert": "/path/to/certificate.crt",
        "key": "/path/to/private.key",
        "key_password": "",
        "cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384",
        "cipher_tls13": "TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
        "prefer_server_cipher": true,
        "alpn": [
            "http/1.1"
        ],
        "reuse_session": true,
        "session_ticket": false,
        "session_timeout": 600,
        "plain_http_response": "",
        "curves": "",
        "dhparam": ""
    },
    "tcp": {
        "prefer_ipv4": false,
        "no_delay": true,
        "keep_alive": true,
        "reuse_port": false,
        "fast_open": false,
        "fast_open_qlen": 20
    },
    "mysql": {
        "enabled": false,
        "server_addr": "127.0.0.1",
        "server_port": 3306,
        "database": "trojan",
        "username": "trojan",
        "password": "",
        "key": "",
        "cert": "",
        "ca": ""
    }
}
EOF
else
    echo 跳过安装 $NAME 服务器配置...
fi

if [[ -d "$SYSTEMDPREFIX" ]]; then
    echo 安装 $NAME systemd 服务到 $SYSTEMDPATH...
    [[ $TYPE == 1 ]] && { NAME="trojan-go"; FLAG="-config"; }
    cat > "$SYSTEMDPATH" << EOF
[Unit]
Description=$NAME
After=network.target network-online.target nss-lookup.target mysql.service mariadb.service mysqld.service

[Service]
Type=simple
StandardError=journal
ExecStart=$BINARYPATH $FLAG $CONFIGPATH
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
#     cat > "$TIMERPATH" << EOF
# [Unit]
# Description=Restart Trojan every 8 hours

# [Timer]
# # 每8小时重启一次（例如 0:00, 8:00, 16:00）
# OnCalendar=*-*-* 0/8:00:00
# # 如果错过触发时间，系统启动后立即执行
# Persistent=true
# Unit=trojan.service

# [Install]
# WantedBy=timers.target
# EOF
echo 重新加载 systemd daemon...
systemctl daemon-reload
systemctl restart trojan.service
(crontab -l; echo "0 * * * * /usr/bin/systemctl restart trojan.service > /dev/null 2>&1") | crontab -
# systemctl enable trojan.timer
# systemctl start trojan.timer

fi

echo 删除临时目录 $TMPDIR...
rm -rf "$TMPDIR"

echo 完成!
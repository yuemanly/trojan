#!/bin/bash

# 定义变量
GITHUB_API_URL="https://api.github.com/repos/yuemanly/trojan/releases/latest"
INSTALL_PATH="/usr/local/bin/trojan"

# 获取系统架构
get_arch() {
    arch=$(uname -m)
    if [[ $arch == "x86_64" ]]; then
        echo "amd64"
    elif [[ $arch == "aarch64" ]]; then
        echo "arm64"
    else
        echo "unsupported"
    fi
}

# 下载最新版本
download_latest() {
    arch=$(get_arch)
    if [[ $arch == "unsupported" ]]; then
        echo "不支持的系统架构"
        exit 1
    fi
    
    echo "获取最新版本信息..."
    version=$(curl -s $GITHUB_API_URL | grep "tag_name" | cut -d'"' -f4)
    if [[ -z "$version" ]]; then
        echo "获取版本信息失败"
        exit 1
    fi
    
    download_url="https://github.com/yuemanly/trojan/releases/download/$version/trojan-linux-$arch"
    echo "下载trojan $version 版本..."
    curl -L $download_url -o $INSTALL_PATH
    if [[ $? -ne 0 ]]; then
        echo "下载失败"
        exit 1
    fi
    chmod +x $INSTALL_PATH
}

# 安装函数
install_trojan() {
    if [[ $EUID -ne 0 ]]; then
        echo "请使用root用户运行此脚本"
        exit 1
    fi
    download_latest
    $INSTALL_PATH
}

# 卸载函数
uninstall_trojan() {
    echo "开始卸载 trojan..."
    
    # 停止和禁用 trojan 服务
    systemctl stop trojan >/dev/null 2>&1
    systemctl disable trojan >/dev/null 2>&1
    
    # 删除 trojan 文件
    rm -f $INSTALL_PATH
    rm -rf /usr/local/etc/trojan
    
    # 检查并停止 MariaDB docker 容器
    if command -v docker >/dev/null 2>&1; then
        if docker ps -a | grep -q "trojan-mariadb"; then
            echo "停止并删除 MariaDB 容器..."
            docker stop trojan-mariadb >/dev/null 2>&1
            docker rm trojan-mariadb >/dev/null 2>&1
        fi
        
        # 可选：删除 MariaDB 数据目录
        read -p "是否删除 MariaDB 数据目录 (/home/mariadb)? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf /home/mariadb
            echo "MariaDB 数据目录已删除"
        fi
    fi

    # 检查并卸载 OpenResty
    if command -v openresty >/dev/null 2>&1; then
        read -p "是否卸载 OpenResty? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl stop openresty >/dev/null 2>&1
            systemctl disable openresty >/dev/null 2>&1
            apt-get remove --purge -y openresty
            rm -rf /etc/openresty
            echo "OpenResty 已卸载"
            
            # 重新安装 trojan 以切换回 443 端口
            $INSTALL_PATH
        fi
    fi
    
    echo "trojan 已完全卸载"
}

# 主函数
main() {
    if [[ $1 == "--remove" ]]; then
        uninstall_trojan
    else
        install_trojan
    fi
}

main "$@"

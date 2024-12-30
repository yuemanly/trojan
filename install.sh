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
    systemctl stop trojan >/dev/null 2>&1
    systemctl disable trojan >/dev/null 2>&1
    rm -f $INSTALL_PATH
    rm -rf /usr/local/etc/trojan
    echo "trojan已卸载"
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

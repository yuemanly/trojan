# trojan
![](https://img.shields.io/github/v/release/yuemanly/trojan.svg) 
[![License](https://img.shields.io/badge/license-GPL%20V3-blue.svg?longCache=true)](https://www.gnu.org/licenses/gpl-3.0.en.html)

trojan多用户命令行管理程序

这是一个基于 [Jrohy/trojan](https://github.com/Jrohy/trojan) 的修改版本，移除了web界面相关功能，仅保留命令行管理功能。感谢原作者的优秀工作！

## 功能
- 命令行方式管理trojan多用户
- 启动 / 停止 / 重启 trojan 服务端
- 支持流量统计和流量限制
- 命令行模式管理, 支持命令补全
- 集成acme.sh证书申请
- 生成客户端配置文件
- 在线实时查看trojan日志
- 在线trojan和trojan-go随时切换
- 限制用户使用期限
- 支持 OpenResty 反向代理（可选）
  - 自动端口切换（安装 OpenResty 时自动切换到 4443 端口）
  - 支持域名分流（trojan域名和其他域名分别处理）
  - 支持 HTTP/HTTPS 服务

## 安装方式
*trojan使用请提前准备好服务器可用的域名*  

###  一键脚本安装
```
#安装/更新
source <(curl -sL https://raw.githubusercontent.com/yuemanly/trojan/master/install.sh)

#卸载
source <(curl -sL https://raw.githubusercontent.com/yuemanly/trojan/master/install.sh) --remove
```
安装完后输入'trojan'可进入管理程序   

## 命令行
```
Usage:
  trojan [flags]
  trojan [command]

Available Commands:
  add           添加用户
  clean         清空指定用户流量
  completion    自动命令补全(支持bash和zsh)
  del           删除用户
  help          Help about any command
  info          用户信息列表
  log           查看trojan日志
  port          修改trojan端口
  restart       重启trojan
  start         启动trojan
  status        查看trojan状态
  stop          停止trojan
  tls           证书安装
  update        更新trojan
  version       显示版本号
  import [path] 导入sql文件
  export [path] 导出sql文件

Flags:
  -h, --help   help for trojan
```

## 配置说明
### OpenResty 配置（可选）
1. 安装 OpenResty：
```bash
trojan
# 选择 "安装管理" -> "安装openresty"
```

2. 安装后：
- OpenResty 监听 443 端口，处理所有 HTTPS 请求
- Trojan 自动切换到 4443 端口
- 访问 trojan 域名时自动转发到 trojan 服务
- 访问其他域名时由 OpenResty 处理

3. 卸载 OpenResty：
```bash
source <(curl -sL https://raw.githubusercontent.com/yuemanly/trojan/master/install.sh) --remove
# 选择卸载 OpenResty
# Trojan 会自动切换回 443 端口
```

## 注意
安装完trojan后强烈建议开启BBR等加速: [one_click_script](https://github.com/jinwyp/one_click_script)  

## 致谢
- 感谢 [Jrohy](https://github.com/Jrohy) 开发的原版 [trojan](https://github.com/Jrohy/trojan)
- 本项目是在原项目基础上的修改版本，仅保留命令行功能

## License
本项目采用 GPL-3.0 协议开源，使用本项目时请遵守 GPL-3.0 协议。

根据 GPL-3.0 协议的要求：
1. 任何基于本项目的衍生项目必须同样采用 GPL-3.0 协议开源
2. 任何修改后的代码版本必须开源
3. 在代码分发时必须包含原始许可证的内容
4. 对代码的任何修改都必须说明


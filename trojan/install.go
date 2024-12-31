package trojan

import (
	"fmt"
	"net"
	"runtime"
	"strconv"
	"strings"
	"time"
	"trojan/asset"
	"trojan/core"
	"trojan/util"
)

var (
	dockerInstallUrl = "https://docker-install.netlify.app/install.sh"
	dbDockerRun      = "docker run --name trojan-mariadb --restart=always -p %d:3306 -v /home/mariadb:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=%s -e MYSQL_ROOT_HOST=%% -e MYSQL_DATABASE=trojan -d mariadb:10.2"
)

// InstallMenu 安装目录
func InstallMenu() {
	fmt.Println()
	menu := []string{"更新trojan", "证书申请", "安装mysql", "安装openresty"}
	switch util.LoopInput("请选择: ", menu, true) {
	case 1:
		InstallTrojan("")
	case 2:
		InstallTls()
	case 3:
		InstallMysql()
	case 4:
		InstallOpenresty()
	default:
		return
	}
}

// InstallDocker 安装docker
func InstallDocker() {
	if !util.CheckCommandExists("docker") {
		util.RunWebShell(dockerInstallUrl)
		fmt.Println()
	}
}

// InstallTrojan 安装trojan
func InstallTrojan(version string) {
	fmt.Println()
	data := string(asset.GetAsset("trojan-install.sh"))
	checkTrojan := util.ExecCommandWithResult("systemctl list-unit-files|grep trojan.service")
	if (checkTrojan == "" && runtime.GOARCH != "amd64") || Type() == "trojan-go" {
		data = strings.ReplaceAll(data, "TYPE=0", "TYPE=1")
	}
	if version != "" {
		data = strings.ReplaceAll(data, "INSTALL_VERSION=\"\"", "INSTALL_VERSION=\""+version+"\"")
	}
	util.ExecCommand(data)
	util.OpenPort(443)
	util.SystemctlRestart("trojan")
	util.SystemctlEnable("trojan")
}

// InstallTls 安装证书
func InstallTls() {
	domain := ""
	server := "letsencrypt"
	fmt.Println()
	choice := util.LoopInput("请选择使用证书方式: ", []string{"Let's Encrypt 证书", "ZeroSSL 证书", "BuyPass 证书", "自定义证书路径"}, true)
	if choice < 0 {
		return
	} else if choice == 4 {
		crtFile := util.Input("请输入证书的cert文件路径: ", "")
		keyFile := util.Input("请输入证书的key文件路径: ", "")
		if !util.IsExists(crtFile) || !util.IsExists(keyFile) {
			fmt.Println("输入的cert或者key文件不存在!")
		} else {
			domain = util.Input("请输入此证书对应的域名: ", "")
			if domain == "" {
				fmt.Println("输入域名为空!")
				return
			}
			core.WriteTls(crtFile, keyFile, domain)
		}
	} else {
		if choice == 2 {
			server = "zerossl"
		} else if choice == 3 {
			server = "buypass"
		}
		localIP := util.GetLocalIP()
		fmt.Printf("本机ip: %s\n", localIP)
		for {
			domain = util.Input("请输入申请证书的域名: ", "")
			ipList, err := net.LookupIP(domain)
			fmt.Printf("%s 解析到的ip: %v\n", domain, ipList)
			if err != nil {
				fmt.Println(err)
				fmt.Println("域名有误,请重新输入")
				continue
			}
			checkIp := false
			for _, ip := range ipList {
				if localIP == ip.String() {
					checkIp = true
				}
			}
			if checkIp {
				break
			} else {
				fmt.Println("输入的域名和本机ip不一致, 请重新输入!")
			}
		}
		util.InstallPack("socat")
		if !util.IsExists("/root/.acme.sh/acme.sh") {
			util.RunWebShell("https://get.acme.sh")
		}
		util.OpenPort(80)
		checkResult := util.ExecCommandWithResult("/root/.acme.sh/acme.sh -v|tr -cd '[0-9]'")
		acmeVersion, _ := strconv.Atoi(checkResult)
		if acmeVersion < 300 {
			util.ExecCommand("/root/.acme.sh/acme.sh --upgrade")
		}
		if server != "letsencrypt" {
			var email string
			for {
				email = util.Input(fmt.Sprintf("请输入申请%s域名所需的邮箱: ", server), "")
				if email == "" {
					fmt.Println("申请域名的邮箱地址为空!")
					return
				} else if util.VerifyEmailFormat(email) {
					break
				} else {
					fmt.Println("邮箱格式不正确, 请重新输入!")
				}
			}
			util.ExecCommand(fmt.Sprintf("bash /root/.acme.sh/acme.sh --server %s --register-account -m %s", server, email))
		}
		issueCommand := fmt.Sprintf("bash /root/.acme.sh/acme.sh --issue -d %s --debug --standalone --keylength ec-256 --force --server %s", domain, server)
		if server == "buypass" {
			issueCommand = issueCommand + " --days 170"
		}
		util.ExecCommand(issueCommand)
		crtFile := "/root/.acme.sh/" + domain + "_ecc" + "/fullchain.cer"
		keyFile := "/root/.acme.sh/" + domain + "_ecc" + "/" + domain + ".key"
		core.WriteTls(crtFile, keyFile, domain)
	}
	Restart()
	fmt.Println()

	// 证书安装完成后，提示安装 OpenResty
	if !util.IsExists("/usr/local/openresty/nginx/sbin/nginx") {
		fmt.Print("是否安装 OpenResty 作为反向代理? [y/n]: ")
		var choice string
		fmt.Scanln(&choice)
		if strings.ToLower(choice) == "y" {
			InstallOpenresty()
			// 创建域名配置文件
			certFile := "/root/.acme.sh/" + domain + "_ecc" + "/fullchain.cer"
			keyFile := "/root/.acme.sh/" + domain + "_ecc" + "/" + domain + ".key"
			domainConfig := fmt.Sprintf(`server {
    listen 80;
    server_name %s;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name %s;

    ssl_certificate %s;
    ssl_certificate_key %s;
    
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    location / {
        root /usr/local/openresty/nginx/html;
        index index.html index.htm;
    }
}`, domain, domain, certFile, keyFile)
			util.ExecCommand(fmt.Sprintf("echo '%s' > /etc/openresty/conf.d/%s.conf", domainConfig, domain))
			util.SystemctlRestart("openresty")
		}
	}
}

// InstallMysql 安装mysql
func InstallMysql() {
	var (
		mysql  core.Mysql
		choice int
	)
	fmt.Println()
	if util.IsExists("/.dockerenv") {
		choice = 2
	} else {
		choice = util.LoopInput("请选择: ", []string{"安装docker版mysql(mariadb)", "输入自定义mysql连接"}, true)
	}
	if choice < 0 {
		return
	} else if choice == 1 {
		mysql = core.Mysql{ServerAddr: "127.0.0.1", ServerPort: util.RandomPort(), Password: util.RandString(8, util.LETTER+util.DIGITS), Username: "root", Database: "trojan"}
		InstallDocker()
		fmt.Println(fmt.Sprintf(dbDockerRun, mysql.ServerPort, mysql.Password))
		if util.CheckCommandExists("setenforce") {
			util.ExecCommand("setenforce 0")
		}
		util.OpenPort(mysql.ServerPort)
		util.ExecCommand(fmt.Sprintf(dbDockerRun, mysql.ServerPort, mysql.Password))
		db := mysql.GetDB()
		for {
			fmt.Printf("%s mariadb启动中,请稍等...\n", time.Now().Format("2006-01-02 15:04:05"))
			err := db.Ping()
			if err == nil {
				db.Close()
				break
			} else {
				time.Sleep(2 * time.Second)
			}
		}
		fmt.Println("mariadb启动成功!")
	} else if choice == 2 {
		mysql = core.Mysql{}
		for {
			for {
				mysqlUrl := util.Input("请输入mysql连接地址(格式: host:port), 默认连接地址为127.0.0.1:3306, 使用直接回车, 否则输入自定义连接地址: ",
					"127.0.0.1:3306")
				urlInfo := strings.Split(mysqlUrl, ":")
				if len(urlInfo) != 2 {
					fmt.Printf("输入的%s不符合匹配格式(host:port)\n", mysqlUrl)
					continue
				}
				port, err := strconv.Atoi(urlInfo[1])
				if err != nil {
					fmt.Printf("%s不是数字\n", urlInfo[1])
					continue
				}
				mysql.ServerAddr, mysql.ServerPort = urlInfo[0], port
				break
			}
			mysql.Username = util.Input("请输入mysql的用户名(回车使用root): ", "root")
			mysql.Password = util.Input(fmt.Sprintf("请输入mysql %s用户的密码: ", mysql.Username), "")
			db := mysql.GetDB()
			if db != nil && db.Ping() == nil {
				mysql.Database = util.Input("请输入使用的数据库名(不存在可自动创建, 回车使用trojan): ", "trojan")
				db.Exec(fmt.Sprintf("CREATE DATABASE IF NOT EXISTS %s;", mysql.Database))
				break
			} else {
				fmt.Println("连接mysql失败, 请重新输入")
			}
		}
	}
	mysql.CreateTable()
	core.WriteMysql(&mysql)
	if userList, _ := mysql.GetData(); len(userList) == 0 {
		AddUser()
	}
	Restart()
	fmt.Println()
}

// InstallOpenresty 安装openresty
func InstallOpenresty() {
	if util.IsExists("/usr/local/openresty/nginx/sbin/nginx") {
		fmt.Println("OpenResty 已安装!")
		return
	}

	// 获取域名和证书路径
	domain := core.GetDomain()
	if domain == "" {
		fmt.Println("未找到域名配置!")
		return
	}
	certFile := "/root/.acme.sh/" + domain + "_ecc" + "/fullchain.cer"
	keyFile := "/root/.acme.sh/" + domain + "_ecc" + "/" + domain + ".key"
	if !util.IsExists(certFile) || !util.IsExists(keyFile) {
		fmt.Println("未找到证书文件!")
		return
	}

	// 停止所有相关服务
	fmt.Println("正在停止所有服务...")
	util.SystemctlStop("trojan")
	util.SystemctlStop("openresty")
	time.Sleep(2 * time.Second)

	// 重启网络服务
	fmt.Println("正在重启网络服务...")
	util.ExecCommand("systemctl restart networking")
	time.Sleep(2 * time.Second)

	// 检查端口
	if util.IsPortOccupied("443") {
		fmt.Println("443端口仍被占用，尝试强制结束占用进程...")
		util.ExecCommand("fuser -k 443/tcp")
		time.Sleep(2 * time.Second)
	}

	// 修改 Trojan 端口
	fmt.Println("正在修改 Trojan 端口...")
	core.GetTrojanPort() // 这会自动设置正确的端口

	// 安装依赖
	fmt.Println("正在安装依赖...")
	util.InstallPack("wget curl gnupg2 ca-certificates lsb-release")

	// 添加 OpenResty 仓库
	fmt.Println("正在添加 OpenResty 仓库...")
	util.ExecCommand("wget -O - https://openresty.org/package/pubkey.gpg | sudo apt-key add -")
	util.ExecCommand("echo \"deb http://openresty.org/package/debian $(lsb_release -sc) openresty\" | sudo tee /etc/apt/sources.list.d/openresty.list")
	util.ExecCommand("apt update")

	// 安装 OpenResty
	fmt.Println("正在安装 OpenResty...")
	util.InstallPack("openresty")

	// 检查安装结果
	if !util.IsExists("/usr/local/openresty/nginx/sbin/nginx") {
		fmt.Println("OpenResty 安装失败!")
		return
	}

	// 创建配置目录
	util.ExecCommand("mkdir -p /usr/local/openresty/nginx/conf/conf.d")

	// 修改主配置文件
	mainConfig := fmt.Sprintf(`user root;
worker_processes auto;
worker_rlimit_nofile 51200;
events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    include conf.d/*.conf;
}

stream {
    upstream trojan {
        server 127.0.0.1:4443;
    }
    server {
        listen 443 ssl;
        ssl_certificate %s;
        ssl_certificate_key %s;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        proxy_pass trojan;
    }
}`, certFile, keyFile)

	util.ExecCommand(fmt.Sprintf("echo '%s' > /usr/local/openresty/nginx/conf/nginx.conf", mainConfig))

	// 创建域名配置文件
	domainConfig := fmt.Sprintf(`server {
    listen 80;
    server_name %s;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name %s;

    ssl_certificate %s;
    ssl_certificate_key %s;
    
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    location / {
        root /usr/local/openresty/nginx/html;
        index index.html index.htm;
    }
}`, domain, domain, certFile, keyFile)

	util.ExecCommand(fmt.Sprintf("echo '%s' > /usr/local/openresty/nginx/conf/conf.d/%s.conf", domainConfig, domain))

	// 测试配置
	fmt.Println("正在测试 OpenResty 配置...")
	if util.ExecCommandWithResult("openresty -t") != "" {
		fmt.Println("OpenResty 配置测试失败!")
		return
	}

	// 启动 OpenResty
	fmt.Println("正在启动 OpenResty...")
	util.SystemctlStop("openresty") // 确保先停止
	time.Sleep(1 * time.Second)
	util.SystemctlStart("openresty")
	if !util.IsExists("/etc/systemd/system/multi-user.target.wants/openresty.service") {
		util.SystemctlEnable("openresty")
	}

	// 等待 OpenResty 完全启动并检查状态
	time.Sleep(2 * time.Second)
	if util.ExecCommandWithResult("systemctl is-active openresty") != "active" {
		fmt.Println("OpenResty 启动失败，请检查配置!")
		return
	}

	// 检查 OpenResty 是否成功监听 443 端口
	if !util.IsPortOccupied("443") {
		fmt.Println("OpenResty 未能成功监听 443 端口!")
		return
	}

	// 最后启动 Trojan
	fmt.Println("正在启动 Trojan...")
	util.SystemctlStart("trojan")
	time.Sleep(1 * time.Second)

	// 检查服务状态
	if util.ExecCommandWithResult("systemctl is-active trojan") != "active" {
		fmt.Println("Trojan 启动失败，请检查配置!")
		return
	}

	// 检查 Trojan 是否成功监听 4443 端口
	if !util.IsPortOccupied("4443") {
		fmt.Println("Trojan 未能成功监听 4443 端口!")
		return
	}

	fmt.Println("OpenResty 安装成功!")
	fmt.Println("Trojan 端口已切换至 4443")
}

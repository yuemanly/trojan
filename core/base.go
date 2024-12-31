package core

import (
	"strings"
	"trojan/util"
)

// Config 结构体
type Config struct {
	RunType    string   `json:"run_type"`
	LocalAddr  string   `json:"local_addr"`
	LocalPort  int      `json:"local_port"`
	RemoteAddr string   `json:"remote_addr"`
	RemotePort int      `json:"remote_port"`
	Password   []string `json:"password"`
	LogLevel   int      `json:"log_level"`
}

// SSL 结构体
type SSL struct {
	Cert          string   `json:"cert"`
	Cipher        string   `json:"cipher"`
	CipherTls13   string   `json:"cipher_tls13"`
	Alpn          []string `json:"alpn"`
	ReuseSession  bool     `json:"reuse_session"`
	SessionTicket bool     `json:"session_ticket"`
	Curves        string   `json:"curves"`
	Sni           string   `json:"sni"`
}

// TCP 结构体
type TCP struct {
	NoDelay      bool `json:"no_delay"`
	KeepAlive    bool `json:"keep_alive"`
	ReusePort    bool `json:"reuse_port"`
	FastOpen     bool `json:"fast_open"`
	FastOpenQlen int  `json:"fast_open_qlen"`
}

// GetDomain 获取trojan配置的域名
func GetDomain() string {
	config := GetConfig()
	if config == nil {
		return ""
	}
	if config.SSl.Cert == "" {
		return ""
	}
	domain := strings.TrimPrefix(config.SSl.Cert, "/root/.acme.sh/")
	domain = strings.TrimSuffix(domain, "_ecc/fullchain.cer")
	domain = strings.TrimSuffix(domain, "/fullchain.cer")
	return domain
}

// GetTrojanPort 根据是否安装了 OpenResty 返回 Trojan 应该使用的端口
func GetTrojanPort() int {
	if util.IsExists("/usr/local/openresty/nginx/sbin/nginx") {
		SetValue("local_port", "4443")
		SetValue("remote_port", "443")
		return 4443
	}
	SetValue("local_port", "443")
	SetValue("remote_port", "443")
	return 443
}

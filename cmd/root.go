package cmd

import (
	"fmt"
	"os"
	"trojan/core"
	"trojan/trojan"
	"trojan/util"

	"github.com/spf13/cobra"
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use: "trojan",
	Run: func(cmd *cobra.Command, args []string) {
		mainMenu()
	},
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func check() {
	if !util.IsExists("/usr/local/etc/trojan/config.json") {
		fmt.Println("本机未安装trojan, 正在自动安装...")
		trojan.InstallTrojan("")
		core.WritePassword(nil)
		trojan.InstallTls()
		trojan.InstallMysql()
	}
}

func mainMenu() {
	check()
exit:
	for {
		fmt.Println()
		fmt.Println(util.Cyan("欢迎使用trojan管理程序"))
		fmt.Println()
		menuList := []string{"trojan管理", "用户管理", "安装管理", "查看配置", "生成json"}
		switch util.LoopInput("请选择: ", menuList, false) {
		case 1:
			trojan.ControlMenu()
		case 2:
			trojan.UserMenu()
		case 3:
			trojan.InstallMenu()
		case 4:
			trojan.UserList()
		case 5:
			trojan.GenClientJson()
		default:
			break exit
		}
	}
}

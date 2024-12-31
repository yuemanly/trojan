// IsPortOccupied 检查端口是否被占用
func IsPortOccupied(port string) bool {
	result := ExecCommandWithResult(fmt.Sprintf("lsof -i:%s", port))
	return result != ""
} 
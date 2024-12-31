#!/bin/bash

# 检查是否设置了github token
if [[ -z "$GITHUB_TOKEN" ]]; then
	echo "错误: 请先设置GITHUB_TOKEN环境变量"
	echo "执行: export GITHUB_TOKEN='你的GitHub个人访问令牌'"
	exit 1
fi

project="yuemanly/trojan"

# 手动输入版本号或使用自动检测
read -p "请输入版本号(例如: v1.0.2，直接回车则自动检测): " input_version
if [[ -n "$input_version" ]]; then
    version="$input_version"
else
    # 检查是否存在tag
    version=$(git describe --tags $(git rev-list --tags --max-count=1) 2>/dev/null)
    if [[ -z "$version" ]]; then
        echo "错误: 没有找到git tag"
        echo "请输入版本号或先创建一个tag: git tag v1.0.0"
        exit 1
    fi
fi

# 验证版本号格式
if [[ ! $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "错误: 版本号格式不正确，应该类似 v1.0.0"
    exit 1
fi

# 验证token是否有效
echo "验证GitHub Token..."
response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
	-H "Accept: application/vnd.github.v3+json" \
	https://api.github.com/user)

if [[ $(echo "$response" | grep -c "Bad credentials") -gt 0 ]]; then
	echo "错误: GitHub Token无效或已过期"
	echo "请重新生成token并设置环境变量"
	exit 1
fi

# 检查是否有仓库访问权限
echo "检查仓库访问权限..."
repo_response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
	-H "Accept: application/vnd.github.v3+json" \
	"https://api.github.com/repos/$project")

if [[ $(echo "$repo_response" | grep -c "Not Found") -gt 0 ]]; then
	echo "错误: 无法访问仓库 $project"
	echo "请确保token有正确的仓库访问权限"
	exit 1
fi

#获取当前的这个脚本所在绝对路径
shell_path=$(cd `dirname $0`; pwd)

function uploadfile() {
	file=$1
	ctype=$(file -b --mime-type $file)

	response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: ${ctype}" --data-binary @$file "https://uploads.github.com/repos/$project/releases/${release_id}/assets?name=$(basename $file)" -w "\n%{http_code}")
	
	http_code=$(echo "$response" | tail -n1)
	if [[ $http_code != "201" ]]; then
		echo "错误: 上传文件 $file 失败"
		echo "HTTP状态码: $http_code"
		echo "响应内容: $(echo "$response" | head -n1)"
		return 1
	fi
}

function upload() {
	file=$1
	dgst=$1.dgst
	openssl dgst -md5 $file | sed 's/([^)]*)//g' >> $dgst
	openssl dgst -sha1 $file | sed 's/([^)]*)//g' >> $dgst
	openssl dgst -sha256 $file | sed 's/([^)]*)//g' >> $dgst
	openssl dgst -sha512 $file | sed 's/([^)]*)//g' >> $dgst
	uploadfile $file
	uploadfile $dgst
}

cd $shell_path

# 检查tag是否已经推送到远程
if ! git ls-remote --tags origin | grep -q "$version"; then
	echo "错误: tag $version 还没有推送到远程仓库"
	echo "请执行: git push origin $version"
	exit 1
fi

# 创建result目录
rm -rf result
mkdir -p result
chmod 755 result

now=`TZ=Asia/Shanghai date "+%Y%m%d-%H%M"`
go_version=`go version|awk '{print $3,$4}'`
git_version=`git rev-parse HEAD`
ldflags="-w -s -X 'trojan/trojan.MVersion=$version' -X 'trojan/trojan.BuildDate=$now' -X 'trojan/trojan.GoVersion=$go_version' -X 'trojan/trojan.GitVersion=$git_version'"

# 编译多个平台的版本
echo "开始编译..."
GOOS=linux GOARCH=amd64 go build -ldflags "$ldflags" -o "result/trojan-linux-amd64" .
GOOS=linux GOARCH=arm64 go build -ldflags "$ldflags" -o "result/trojan-linux-arm64" .
GOOS=darwin GOARCH=amd64 go build -ldflags "$ldflags" -o "result/trojan-darwin-amd64" .
GOOS=darwin GOARCH=arm64 go build -ldflags "$ldflags" -o "result/trojan-darwin-arm64" .
GOOS=windows GOARCH=amd64 go build -ldflags "$ldflags" -o "result/trojan-windows-amd64.exe" .
echo "编译完成!"

if [[ $# == 0 ]];then
	cd result

	upload_item=($(ls -l|awk '{print $9}'|xargs -r))

	# 检查是否已存在相同版本的release
	existing_release=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
		"https://api.github.com/repos/$project/releases/tags/$version")
	
	if [[ $(echo "$existing_release" | grep -c "Not Found") -eq 0 ]]; then
		echo "警告: 版本 $version 的release已存在"
		echo "是否删除已存在的release并重新创建? (y/N)"
		read -r answer
		if [[ "$answer" =~ ^[Yy]$ ]]; then
			release_id=$(echo "$existing_release" | grep -o '"id": [0-9]*' | head -n1 | awk '{print $2}')
			if [[ -n "$release_id" ]]; then
				echo "删除已存在的release..."
				curl -s -X DELETE -H "Authorization: token ${GITHUB_TOKEN}" \
					"https://api.github.com/repos/$project/releases/$release_id"
			fi
		else
			echo "操作取消"
			exit 1
		fi
	fi

	# 创建新的release
	echo "创建新的release: $version"
	response=$(curl -s -X POST -H "Authorization: token ${GITHUB_TOKEN}" \
		-H "Accept: application/vnd.github.v3+json" \
		"https://api.github.com/repos/$project/releases" \
		-d "{\"tag_name\":\"$version\",\"name\":\"$version\",\"body\":\"命令行版本trojan管理程序\"}")

	# 打印完整响应以便调试
	echo "创建release响应:"
	echo "$response"

	# 从响应中获取release ID
	release_id=$(echo "$response" | grep -o '"id": [0-9]*' | head -n1 | awk '{print $2}')
	if [[ -z "$release_id" ]]; then
		echo "错误: 无法从响应中获取release ID"
		exit 1
	fi

	echo "获取到release ID: $release_id"

	echo "开始上传文件..."
	for item in ${upload_item[@]}
	do
		echo "上传: $item"
		upload $item
	done

	echo "上传完成!"
	echo "Release URL: https://github.com/$project/releases/tag/$version"

	cd $shell_path
	rm -rf result
fi

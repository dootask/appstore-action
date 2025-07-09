#!/bin/bash

set -e

# 检查必需的工具
command -v curl >/dev/null 2>&1 || { echo "错误: curl 未安装" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "错误: jq 未安装" >&2; exit 1; }

# 获取输入参数
USERNAME="${INPUT_USERNAME}"
PASSWORD="${INPUT_PASSWORD}"
DRAFT="${INPUT_DRAFT,,}"  # 转为小写
PACKAGE_FILE="${INPUT_PACKAGE_FILE}"
APPID="${INPUT_APPID}"

# 验证必需参数
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$PACKAGE_FILE" ] || [ -z "$APPID" ]; then
    echo "错误: 缺少必需的参数"
    exit 1
fi

# 将 draft 转换为布尔值 (true -> false, false -> true，因为 API 的 is_public 参数含义相反)
if [ "$DRAFT" = "true" ]; then
    IS_PUBLIC="false"
else
    IS_PUBLIC="true"
fi

echo "开始发布应用到 DooTask 应用商店..."
echo "应用 ID: $APPID"
echo "草稿模式: $DRAFT"

# 步骤 1: 处理压缩包文件
TEMP_DIR=$(mktemp -d)
FINAL_PACKAGE_FILE=""

# 判断是 URL 还是本地文件
if [[ "$PACKAGE_FILE" =~ ^https?:// ]]; then
    echo "检测到 URL，正在下载压缩包..."
    DOWNLOAD_FILE="$TEMP_DIR/package"
    
    # 根据 URL 判断文件类型
    if [[ "$PACKAGE_FILE" == *.zip ]]; then
        DOWNLOAD_FILE="$DOWNLOAD_FILE.zip"
    elif [[ "$PACKAGE_FILE" == *.tar.gz ]]; then
        DOWNLOAD_FILE="$DOWNLOAD_FILE.tar.gz"
    elif [[ "$PACKAGE_FILE" == *.tgz ]]; then
        DOWNLOAD_FILE="$DOWNLOAD_FILE.tgz"
    else
        echo "警告: 无法从 URL 判断文件类型，尝试自动检测..."
        DOWNLOAD_FILE="$DOWNLOAD_FILE.unknown"
    fi
    
    # 下载文件
    if ! curl -L -f -o "$DOWNLOAD_FILE" "$PACKAGE_FILE"; then
        echo "错误: 下载压缩包失败"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    FINAL_PACKAGE_FILE="$DOWNLOAD_FILE"
    echo "压缩包下载完成: $FINAL_PACKAGE_FILE"
else
    echo "检测到本地文件: $PACKAGE_FILE"
    
    # 检查本地文件是否存在
    if [ ! -f "$PACKAGE_FILE" ]; then
        echo "错误: 本地文件不存在: $PACKAGE_FILE"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # 检查文件格式
    if [[ ! "$PACKAGE_FILE" =~ \.(zip|tar\.gz|tgz)$ ]]; then
        echo "警告: 文件格式可能不受支持，支持的格式: .zip, .tar.gz, .tgz"
    fi
    
    FINAL_PACKAGE_FILE="$PACKAGE_FILE"
    echo "使用本地文件: $FINAL_PACKAGE_FILE"
fi

# 步骤 2: 登录获取 token
echo "正在登录 DooTask 应用商店..."

response=$(curl -s 'https://appstore.dootask.com/api/v1/developer/login' \
  -H 'Content-Type: application/json' \
  --data-raw "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

echo "登录响应: $response"

token=$(echo "$response" | jq -r '.data.token // empty')
code=$(echo "$response" | jq -r '.code // empty')

if [ "$code" != "200" ] || [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "错误: 登录失败，状态码: $code"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "登录成功，获取到 token"
echo "token=$token" >> $GITHUB_OUTPUT

# 步骤 3: 上传压缩包
echo "正在上传压缩包..."

response=$(curl -s 'https://appstore.dootask.com/api/v1/developer/app/upload' \
  --header "Token: $token" \
  --form "file=@\"$FINAL_PACKAGE_FILE\"" \
  --form "appid=\"$APPID\"")

echo "上传响应: $response"

hash=$(echo "$response" | jq -r '.data.hash // empty')
code=$(echo "$response" | jq -r '.code // empty')

if [ "$code" != "200" ] || [ -z "$hash" ] || [ "$hash" = "null" ]; then
    echo "错误: 上传失败，状态码: $code"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "上传成功，获取到 hash: $hash"
echo "hash=$hash" >> $GITHUB_OUTPUT

# 步骤 4: 发布应用
echo "正在发布应用..."

response=$(curl -s 'https://appstore.dootask.com/api/v1/developer/app/publish' \
  -H 'Content-Type: application/json' \
  -H "Token: $token" \
  --data-raw "{\"hash\":\"$hash\",\"is_public\":$IS_PUBLIC}")

echo "发布响应: $response"

code=$(echo "$response" | jq -r '.code // empty')

if [ "$code" != "200" ]; then
    echo "错误: 发布失败，状态码: $code"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "应用发布成功！"
echo "success=true" >> $GITHUB_OUTPUT

# 清理临时文件
rm -rf "$TEMP_DIR"

echo "所有步骤完成！" 
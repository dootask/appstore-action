#!/bin/bash

set -e

# Check required tools # 检查必需的工具
command -v curl >/dev/null 2>&1 || { echo "::error::curl is not installed" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "::error::jq is not installed" >&2; exit 1; }

# Retry function for network requests # 重试函数 - 支持重试网络请求
retry_request() {
    local max_attempts=10
    local delay=2
    local attempt=1
    local cmd="$*"
    
    while [ $attempt -le $max_attempts ]; do
        echo "::notice::Attempt $attempt of $max_attempts..." # 尝试第 $attempt 次，共 $max_attempts 次
        
        if eval "$cmd"; then
            echo "::notice::Request successful!" # 请求成功！
            return 0
        else
            echo "::warning::Request failed on attempt $attempt" # 请求失败，尝试第 $attempt 次失败
            
            if [ $attempt -eq $max_attempts ]; then
                echo "::error::Maximum retry attempts ($max_attempts) reached, request finally failed" # 已达到最大重试次数，请求最终失败
                return 1
            fi
            
            echo "::notice::Waiting $delay seconds before retry..." # 等待 $delay 秒后重试
            sleep $delay
            
            # Exponential backoff: double delay after each failure, max 30 seconds # 指数退避：每次失败后延迟时间翻倍，最大不超过30秒
            delay=$((delay * 2))
            if [ $delay -gt 30 ]; then
                delay=30
            fi
            
            attempt=$((attempt + 1))
        fi
    done
}

# Get input parameters # 获取输入参数
USERNAME="${INPUT_USERNAME}"
PASSWORD="${INPUT_PASSWORD}"
DRAFT="${INPUT_DRAFT,,}"  # Convert to lowercase # 转为小写
PACKAGE_FILE="${INPUT_PACKAGE_FILE}"
APPID="${INPUT_APPID}"

# Validate required parameters # 验证必需参数
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$PACKAGE_FILE" ] || [ -z "$APPID" ]; then
    echo "::error::Missing required parameters" # 缺少必需的参数
    exit 1
fi

# Convert draft to boolean (true -> false, false -> true, because API's is_public parameter has opposite meaning) 
# 将 draft 转换为布尔值 (true -> false, false -> true，因为 API 的 is_public 参数含义相反)
if [ "$DRAFT" = "true" ]; then
    IS_PUBLIC="false"
else
    IS_PUBLIC="true"
fi

echo "::group::Publishing app to DooTask App Store" # 开始发布应用到 DooTask 应用商店
echo "::notice::App ID: $APPID" # 应用 ID
echo "::notice::Draft mode: $DRAFT" # 草稿模式
echo "::endgroup::"

# Step 1: Handle package file # 步骤 1: 处理压缩包文件
TEMP_DIR=$(mktemp -d)
FINAL_PACKAGE_FILE=""

# Check if it's URL or local file # 判断是 URL 还是本地文件
if [[ "$PACKAGE_FILE" =~ ^https?:// ]]; then
    echo "::group::Downloading package from URL" # 从URL下载压缩包
    echo "::notice::Detected URL, downloading package..." # 检测到 URL，正在下载压缩包
    DOWNLOAD_FILE="$TEMP_DIR/package"
    
    # Determine file type from URL # 根据 URL 判断文件类型
    if [[ "$PACKAGE_FILE" == *.zip ]]; then
        DOWNLOAD_FILE="$DOWNLOAD_FILE.zip"
    elif [[ "$PACKAGE_FILE" == *.tar.gz ]]; then
        DOWNLOAD_FILE="$DOWNLOAD_FILE.tar.gz"
    elif [[ "$PACKAGE_FILE" == *.tgz ]]; then
        DOWNLOAD_FILE="$DOWNLOAD_FILE.tgz"
    else
        echo "::warning::Cannot determine file type from URL, trying auto-detection..." # 无法从 URL 判断文件类型，尝试自动检测
        DOWNLOAD_FILE="$DOWNLOAD_FILE.unknown"
    fi
    
    # Download file with retry mechanism # 下载文件 - 使用重试机制
    echo "::notice::Starting package download with retry support..." # 开始下载压缩包，支持重试
    if ! retry_request "curl -L -f -o \"$DOWNLOAD_FILE\" \"$PACKAGE_FILE\""; then
        echo "::error::Package download failed after 10 retries" # 下载压缩包失败，已重试10次
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    FINAL_PACKAGE_FILE="$DOWNLOAD_FILE"
    echo "::notice::Package download completed: $FINAL_PACKAGE_FILE" # 压缩包下载完成
    echo "::endgroup::"
else
    echo "::group::Using local package file" # 使用本地压缩包文件
    echo "::notice::Detected local file: $PACKAGE_FILE" # 检测到本地文件
    
    # Check if local file exists # 检查本地文件是否存在
    if [ ! -f "$PACKAGE_FILE" ]; then
        echo "::error::Local file does not exist: $PACKAGE_FILE" # 本地文件不存在
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Check file format # 检查文件格式
    if [[ ! "$PACKAGE_FILE" =~ \.(zip|tar\.gz|tgz)$ ]]; then
        echo "::warning::File format may not be supported. Supported formats: .zip, .tar.gz, .tgz" # 文件格式可能不受支持，支持的格式: .zip, .tar.gz, .tgz
    fi
    
    FINAL_PACKAGE_FILE="$PACKAGE_FILE"
    echo "::notice::Using local file: $FINAL_PACKAGE_FILE" # 使用本地文件
    echo "::endgroup::"
fi

# Step 2: Login to get token # 步骤 2: 登录获取 token
echo "::group::Logging in to DooTask App Store" # 登录 DooTask 应用商店
echo "::notice::Logging in to DooTask App Store with retry support..." # 正在登录 DooTask 应用商店，支持重试

# Login request with retry mechanism # 使用重试机制的登录请求
login_request() {
    response=$(curl -s 'https://appstore.dootask.com/api/v1/developer/login' \
      -H 'Content-Type: application/json' \
      --data-raw "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")
    
    echo "::debug::Login response: $response" # 登录响应
    
    token=$(echo "$response" | jq -r '.data.token // empty')
    code=$(echo "$response" | jq -r '.code // empty')
    
    if [ "$code" != "200" ] || [ -z "$token" ] || [ "$token" = "null" ]; then
        echo "::warning::Login failed with status code: $code" # 登录失败，状态码
        return 1
    fi
    
    return 0
}

if ! retry_request "login_request"; then
    echo "::error::Login failed after 10 retries" # 登录失败，已重试10次
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "::notice::Login successful, token obtained" # 登录成功，获取到 token
echo "token=$token" >> $GITHUB_OUTPUT
echo "::endgroup::"

# Step 3: Upload package # 步骤 3: 上传压缩包
echo "::group::Uploading package" # 上传压缩包
echo "::notice::Uploading package with retry support..." # 正在上传压缩包，支持重试

# Upload request with retry mechanism # 使用重试机制的上传请求
upload_request() {
    response=$(curl -s 'https://appstore.dootask.com/api/v1/developer/app/upload' \
      --header "Token: $token" \
      --form "file=@\"$FINAL_PACKAGE_FILE\"" \
      --form "appid=\"$APPID\"")
    
    echo "::debug::Upload response: $response" # 上传响应
    
    hash=$(echo "$response" | jq -r '.data.hash // empty')
    code=$(echo "$response" | jq -r '.code // empty')
    
    if [ "$code" != "200" ] || [ -z "$hash" ] || [ "$hash" = "null" ]; then
        echo "::warning::Upload failed with status code: $code" # 上传失败，状态码
        return 1
    fi
    
    return 0
}

if ! retry_request "upload_request"; then
    echo "::error::Upload failed after 10 retries" # 上传失败，已重试10次
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "::notice::Upload successful, hash obtained: $hash" # 上传成功，获取到 hash
echo "hash=$hash" >> $GITHUB_OUTPUT
echo "::endgroup::"

# Step 4: Publish app # 步骤 4: 发布应用
echo "::group::Publishing app" # 发布应用
echo "::notice::Publishing app with retry support..." # 正在发布应用，支持重试

# Publish request with retry mechanism # 使用重试机制的发布请求
publish_request() {
    response=$(curl -s 'https://appstore.dootask.com/api/v1/developer/app/publish' \
      -H 'Content-Type: application/json' \
      -H "Token: $token" \
      --data-raw "{\"hash\":\"$hash\",\"is_public\":$IS_PUBLIC}")
    
    echo "::debug::Publish response: $response" # 发布响应
    
    code=$(echo "$response" | jq -r '.code // empty')
    
    if [ "$code" != "200" ]; then
        echo "::warning::Publish failed with status code: $code" # 发布失败，状态码
        return 1
    fi
    
    return 0
}

if ! retry_request "publish_request"; then
    echo "::error::Publish failed after 10 retries" # 发布失败，已重试10次
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "::notice::App published successfully!" # 应用发布成功！
echo "success=true" >> $GITHUB_OUTPUT
echo "::endgroup::"

# Clean up temporary files # 清理临时文件
rm -rf "$TEMP_DIR"

echo "::notice::All steps completed successfully!" # 所有步骤完成！ 
# DooTask AppStore Publisher

一个用于自动发布应用到 DooTask 应用商店的 GitHub Action。

## 功能特性

- 🚀 自动登录 DooTask 应用商店
- 📦 支持多种压缩包格式（.zip、.tar.gz、.tgz）
- 📁 支持本地文件和远程 URL
- ⬆️ 自动上传应用包
- 📱 一键发布应用
- 🔒 支持草稿模式

## 使用方法

### 基本用法

```yaml
name: 发布到 DooTask 应用商店

on:
  release:
    types: [published]

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - name: 发布应用
        uses: your-username/dootask-appstore-action@v1
        with:
          username: ${{ secrets.DOOTASK_USERNAME }}
          password: ${{ secrets.DOOTASK_PASSWORD }}
          appid: 'your-app-id'
          package_file: 'https://github.com/your-username/your-repo/releases/download/v1.0.0/app.tar.gz'
          draft: false
```

### 完整示例

```yaml
name: 发布到 DooTask 应用商店

on:
  workflow_dispatch:
    inputs:
      package_file:
        description: '压缩包文件路径或下载地址'
        required: true
      draft:
        description: '是否为草稿'
        type: boolean
        default: true

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - name: 检出代码
        uses: actions/checkout@v4

      - name: 发布应用到 DooTask 应用商店
        uses: your-username/dootask-appstore-action@v1
        with:
          username: ${{ secrets.DOOTASK_USERNAME }}
          password: ${{ secrets.DOOTASK_PASSWORD }}
          appid: 'roomly'
          package_file: ${{ github.event.inputs.package_file }}
          draft: ${{ github.event.inputs.draft }}
        
      - name: 输出结果
        run: |
          echo "发布完成！"
          echo "Token: ${{ steps.publish.outputs.token }}"
          echo "Hash: ${{ steps.publish.outputs.hash }}"
          echo "Success: ${{ steps.publish.outputs.success }}"
```

### 使用本地文件示例

```yaml
name: 构建并发布到 DooTask 应用商店

on:
  push:
    tags:
      - 'v*'

jobs:
  build-and-publish:
    runs-on: ubuntu-latest
    steps:
      - name: 检出代码
        uses: actions/checkout@v4

      - name: 构建应用包
        run: |
          # 这里是您的构建步骤
          npm install
          npm run build
          tar -czf my-app.tar.gz dist/

      - name: 发布到 DooTask 应用商店
        uses: your-username/dootask-appstore-action@v1
        with:
          username: ${{ secrets.DOOTASK_USERNAME }}
          password: ${{ secrets.DOOTASK_PASSWORD }}
          appid: 'my-app-id'
          package_file: './my-app.tar.gz'  # 使用构建生成的本地文件
          draft: false
```

## 输入参数

| 参数名 | 描述 | 必需 | 默认值 |
|--------|------|------|--------|
| `username` | DooTask 应用商店用户名 | ✅ | - |
| `password` | DooTask 应用商店密码 | ✅ | - |
| `appid` | 应用 ID | ✅ | - |
| `package_file` | 压缩包文件路径或下载地址 | ✅ | - |
| `draft` | 是否为草稿模式 | ❌ | `true` |

## 输出参数

| 参数名 | 描述 |
|--------|------|
| `token` | 登录获取的 token |
| `hash` | 上传后获取的文件 hash |
| `success` | 发布是否成功 |

## 环境要求

此 Action 需要以下工具：
- `curl` - 用于 API 请求
- `jq` - 用于 JSON 解析

这些工具在 GitHub Actions 的默认运行环境中都已预装。

## 配置 Secrets

在使用此 Action 之前，您需要在 GitHub 仓库中配置以下 Secrets：

1. 转到您的 GitHub 仓库
2. 点击 **Settings** → **Secrets and variables** → **Actions**
3. 点击 **New repository secret** 添加以下 secrets：

- `DOOTASK_USERNAME`: 您的 DooTask 应用商店用户名
- `DOOTASK_PASSWORD`: 您的 DooTask 应用商店密码

## 支持的压缩包格式

- `.zip` - ZIP 压缩包
- `.tar.gz` - Gzip 压缩的 tar 包
- `.tgz` - Gzip 压缩的 tar 包（简写）

## 文件来源支持

- **本地文件**: 相对或绝对路径，如 `./dist/app.tar.gz` 或 `/path/to/app.zip`
- **远程 URL**: HTTP/HTTPS 链接，如 `https://example.com/releases/app.tar.gz`

Action 会自动检测输入是本地文件还是远程 URL，并相应处理。

## 错误处理

Action 会自动处理以下错误情况：
- 登录失败
- 本地文件不存在
- 压缩包下载失败
- 文件上传失败
- 应用发布失败

如果任何步骤失败，Action 会输出详细的错误信息并退出。

## 许可证

MIT License 
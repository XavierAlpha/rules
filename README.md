# sing-box Rule Set Builder

用于在 GitHub 上自动构建 sing-box 规则集的仓库模板。

将 sing-box Source Format 的 `.json` 规则文件放入 `rules/` 目录后，GitHub Actions 会自动获取最新稳定版 sing-box，将规则编译为 `.srs`，并发布源文件、编译产物、校验文件和下载包。

## 功能

- 自动使用最新稳定版 sing-box 编译规则集
- 支持 `rules/` 下多个 JSON 文件及任意子目录
- 保留原始 JSON 源文件
- 自动生成对应的 `.srs` 文件
- 编译后自动校验生成的 SRS
- 自动生成 `manifest.json` 和 `SHA256SUMS`
- 自动生成 JSON、SRS 和完整规则下载包
- 自动发布到独立的 `release` 分支
- 支持 GitHub Actions Artifact 下载
- 支持 GitHub Pages 作为规则下载页面
- 支持定时重建，以跟随 sing-box 稳定版更新

## 快速开始

### 1. 创建仓库

下载并解压本项目，将全部文件上传到新的 GitHub 仓库。

请确保 `.github/` 隐藏目录一并上传，否则 GitHub Actions 不会生效。

### 2. 添加规则

将 sing-box Source Format JSON 放入 `rules/`：

```text
rules/
├── ai/
│   ├── openai.json
│   ├── claude.json
│   └── gemini.json
├── cn/
│   └── direct.json
└── ads.json
```

仓库自带的 `rules/example.json` 仅作为示例，可直接删除或替换。

### 3. 提交到 GitHub

提交规则后，GitHub Actions 会自动完成构建。

构建成功后，正式产物会发布到：

```text
release
```

分支。

工作流使用 GitHub 自动提供的 `GITHUB_TOKEN`，无需额外创建 Secret。

如仓库限制了 Actions 写入权限，请在：

```text
Settings → Actions → General → Workflow permissions
```

启用：

```text
Read and write permissions
```

## 规则格式

规则文件使用 sing-box Source Format，例如：

```json
{
  "version": 1,
  "rules": [
    {
      "domain_suffix": [
        "example.com"
      ]
    }
  ]
}
```

`version` 可以省略。

如果源文件声明的规则集版本高于当前稳定版 sing-box 支持的版本，构建会失败。

## 目录结构

```text
.
├── .github/
│   └── workflows/
│       └── build-rulesets.yml
├── rules/
│   ├── README.md
│   └── example.json
├── scripts/
│   ├── build.sh
│   ├── generate-metadata.py
│   ├── install-sing-box.sh
│   ├── prepare-rule.py
│   ├── publish-release-branch.sh
│   └── validate-sources.py
├── CONTRIBUTING.md
├── LICENSE
├── Makefile
├── README.md
└── SECURITY.md
```

## 构建产物

`release` 分支结构：

```text
release/
├── source/
│   └── ...                 # 原始 JSON
├── srs/
│   └── ...                 # 编译后的 SRS
├── downloads/
│   ├── rules-source.zip
│   ├── rules-srs.zip
│   └── rules-complete.zip
├── manifest.json
├── SHA256SUMS
├── README.md
├── index.html
└── .nojekyll
```

其中：

- `source/`：原始 JSON 规则文件
- `srs/`：sing-box 编译后的二进制规则集
- `rules-source.zip`：全部 JSON 源文件
- `rules-srs.zip`：全部 SRS 文件
- `rules-complete.zip`：JSON、SRS 及相关元数据
- `manifest.json`：构建版本、文件信息、哈希和下载地址
- `SHA256SUMS`：发布文件的 SHA-256 校验值

> `.srs` 的实际格式版本由 sing-box 根据规则内容决定，因此可能低于当前编译器支持的最高规则集版本。`manifest.json` 会记录每个 SRS 的实际格式版本。

## 下载地址

假设仓库地址为：

```text
https://github.com/OWNER/REPO
```

并存在：

```text
rules/ai/openai.json
```

则源文件地址为：

```text
https://raw.githubusercontent.com/OWNER/REPO/release/source/ai/openai.json
```

SRS 地址为：

```text
https://raw.githubusercontent.com/OWNER/REPO/release/srs/ai/openai.srs
```

完整下载包：

```text
https://raw.githubusercontent.com/OWNER/REPO/release/downloads/rules-source.zip
https://raw.githubusercontent.com/OWNER/REPO/release/downloads/rules-srs.zip
https://raw.githubusercontent.com/OWNER/REPO/release/downloads/rules-complete.zip
```

## sing-box 配置示例

使用远程 SRS：

```json
{
  "route": {
    "rule_set": [
      {
        "type": "remote",
        "tag": "openai",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/OWNER/REPO/release/srs/ai/openai.srs",
        "download_detour": "direct",
        "update_interval": "1d"
      }
    ]
  }
}
```

使用远程 Source Format JSON 时，将 `format` 设置为 `source`，并将 URL 指向 `release/source/` 下的 JSON 文件。

## GitHub Actions

工作流支持以下触发方式：

- `rules/**/*.json` 发生 Push
- 构建脚本或工作流发生变更
- Pull Request
- 手动运行 `workflow_dispatch`
- 每日定时构建

Pull Request 只执行构建和校验，不更新正式 `release` 分支。

默认分支上的正式构建会更新 `release` 分支，并同时上传 GitHub Actions Artifact。

## 本地构建

支持 Linux 和 macOS。

```bash
make build
```

或：

```bash
./scripts/build.sh
```

默认自动获取最新稳定版 sing-box。

如需固定版本：

```bash
SING_BOX_VERSION=1.14.1 ./scripts/build.sh
```

主要依赖：

- Bash
- curl
- tar
- Python 3

## GitHub Pages

`release` 分支包含静态下载页面。

如需启用 GitHub Pages，可在仓库设置中选择：

```text
Settings → Pages
```

发布来源设置为：

```text
Deploy from a branch
Branch: release
Folder: /(root)
```

GitHub Pages 为可选功能，不影响 Raw URL、下载包或 Actions Artifact 的使用。

## 许可证

本项目使用 [MIT License](LICENSE)。

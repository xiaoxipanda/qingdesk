# 轻桌 · QingDesk

[English](README_EN.md) · [下载](https://github.com/xiaoxipanda/qingdesk/releases/latest) · [参与贡献](CONTRIBUTING.md) · [MIT License](LICENSE)

<img src="assets/QingDeskIcon.png" width="128" alt="轻桌应用图标">

一个轻量的 macOS 原生应用主页：时钟、常用应用图标和底部快捷栏。点击图标就能打开软件，不依赖软件是否在桌面或系统 Dock 中。SwiftUI + AppKit，无第三方运行时，支持 macOS 14 及以上。

## 安装

从 [Releases](https://github.com/xiaoxipanda/qingdesk/releases) 下载 `QingDesk-macOS.zip`，解压后将 `轻桌.app` 放入「应用程序」或 `~/Applications`。

当前发布的安装包面向 Apple Silicon（M 系列芯片），要求 macOS 14 或以上。Intel Mac 可按下文从源码构建；尚未在 Intel 真机验证。

安装包使用 ad-hoc 签名，尚未进行 Developer ID 签名和 Apple 公证。通过浏览器下载后，Gatekeeper 可能要求额外确认或阻止打开；需要自行构建的用户可以使用下面的源码构建流程。

## 使用

1. 打开工作台，点击右上角「设置」。
2. 在「常用应用」中添加软件，也可从文件选择一个或多个 `.app`。
3. 上下箭头调整首页顺序；星标将应用放入底部快捷栏，最多 5 个。移除入口不会卸载软件。
4. 点击「完成」回到首页，点击应用图标即可启动；设置自动保存在本机。

首页提供搜索和分页。图标保持清晰尺寸，只显示完整行；默认窗口每页可显示 15 个应用，较小窗口自动减少行数。超过一页时使用「下一页」，也可搜索名称或 Bundle ID。搜索只有一个结果时按回车打开。没有无限滚动列表，也不会被底部快捷栏遮住。

## 配合 cua-driver

建议让代理按下面的步骤操作：

> 读取轻桌的窗口状态，找到「搜索应用」输入框，输入目标应用名。重新读取状态，点击「打开〈应用名〉」。然后读取目标应用的窗口，确认已经启动。

搜索框、打开按钮和翻页按钮具有明确的辅助功能名称，以及 `launcher.search`、`launcher.app.<bundle-id>`、`launcher.next-page` 等标识。页面只创建当前页的应用按钮，辅助功能树与屏幕上的内容对应。搜索、翻页或改变窗口大小后，必须重新读取状态，避免复用旧的元素索引、token 或截图坐标。

Cua Driver 支持读取辅助功能元素和按元素进行操作，详见[官方 macOS 工具参考](https://cua.ai/docs/reference/cua-driver/mcp-tools)。这不保证目标软件自身的界面一定可自动操作；工作台负责提供可见、可查找的启动入口。使用首页作为应用启动入口无需修改 Hermes 或 cua-driver 源码。

## 可选分屏

在「设置 → 分屏选项」选择布局、应用和显示器，再点击「启动并应用布局」。普通启动应用不需要辅助功能权限；排列窗口需要在「系统设置 → 隐私与安全性 → 辅助功能」中允许「轻桌」。macOS 的授权由用户完成，应用自动检查授权状态。

提供左右、上下、主次窗口、四宫格和铺满窗口布局，间距可调，避开菜单栏和 Dock。使用普通桌面窗口平铺，不会创建系统全屏 Split View 或切换 Space。

程序通过应用路径和 Bundle ID 启动软件，并通过 AX 读取窗口和调整位置。布局后确认实际尺寸；失败尝试恢复原布局。没有窗口、窗口歧义、全屏或最小尺寸限制会返回明确错误。支持恢复最近一次成功布局前的位置，但不会关闭已经启动的应用。

配置保存在 `~/Library/Application Support/Desktop Workbench/workspace.json`（沿用原目录，升级不会重置常用应用），包含首页应用、顺序、快捷栏、称呼和分屏选项。首次安装预选本机存在的 Chrome、飞书、Cursor、VS Code、备忘录和终端；后续保留用户的选择，包括空列表。

## 构建与测试

需要 Swift 6 或以上、Xcode 或对应的 Command Line Tools、Python 3。

```bash
git clone https://github.com/xiaoxipanda/qingdesk.git
cd qingdesk
swift test
bash scripts/build-app.sh
open "dist/轻桌.app"
```

构建同时生成标准压缩包 `dist/QingDesk-macOS.zip`，并保留程序的执行权限。

生成的 `.app` 使用本机 ad-hoc 签名。将它放在固定位置使用可以保持辅助功能授权路径一致；面向无需额外安全确认的分发流程，需要发布者使用自己的 Developer ID 签名并完成 Apple 公证。GitHub Actions 自动运行单元测试、构建和 ZIP 解压检查，不执行真实窗口排列。

单元测试覆盖应用分页不遗漏、页面边界、多显示器坐标、分屏不重叠、配置持久化、MCP 协议和私有 socket。只读 MCP 验证：

```bash
python3 scripts/smoke-mcp.py "/absolute/path/轻桌.app/Contents/MacOS/workbench-mcp"
```

可选的真实分屏测试使用独立的测试窗口，不打开用户文档：执行 `bash scripts/build-fixtures.sh`，在设置中手动添加 `.build/desktop-fixtures` 下两个测试 `.app`，然后运行 `scripts/smoke-desktop.py` 并传入 helper 的绝对路径。完成后可移除测试入口。真实窗口操作不属于 CI 自动检查范围。

## 可选 MCP 接入

日常点击和 cua-driver 操作首页无需这部分。应用仍附带独立 `workbench-mcp`，供需要直接准备窗口的代理使用，通过当前用户私有 Unix socket 通信，没有网络监听端口。

将下面配置合并到 Hermes 所在机器的 `config.yaml`，保留已有的其他服务：

```yaml
mcp_servers:
  desktop_workbench:
    command: "/absolute/path/轻桌.app/Contents/MacOS/workbench-mcp"
    args: []
```

支持 `list_apps`、`ensure_app`、`apply_layout`、`get_workspace_state`、`launch_scene`（已有场景）和 `restore_layout`。调用启动和布局仅接受已经添加到首页的应用。缺少权限或窗口未就绪时返回结构化错误；通信中断不重放已经发出的操作。

helper 可以后台启动工作台自身；`--no-autostart` 关闭这一行为。它不会启动 Hermes。工作台关闭窗口后保留本地服务，使用应用菜单的「退出」完全退出，点击 Dock 图标可重新显示首页。

服务需运行在被操作的 Mac 上。远端 Hermes 要通过自己的 MCP 转发通道连接，不能直接使用 Mac 的本地应用路径。


## 许可与图标

源码以 [MIT](LICENSE) 许可证发布。应用图标使用内置 imagegen 生成，[源图](assets/QingDeskIcon.png) 和 [生成描述](assets/icon-prompt.md) 随项目提供。

首页展示的是用户本机安装应用的图标；这些第三方应用图标不随本仓库分发。

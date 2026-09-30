# 参与贡献

欢迎通过 Issue 报告问题或通过 Pull Request 提交改进。

## 本地开发

需要 macOS 14 或以上、Swift 6 或以上、Xcode 或对应的 Command Line Tools，以及 Python 3。项目不依赖第三方 Swift 包。

```bash
git clone https://github.com/xiaoxipanda/qingdesk.git
cd qingdesk
swift test
bash scripts/build-app.sh
open "dist/轻桌.app"
```

`Sources/DesktopWorkbench` 是 SwiftUI / AppKit 界面和原生应用操作；`Sources/WorkbenchCore` 是配置、布局、分页、IPC 和 MCP 协议；`Sources/WorkbenchMCP` 是独立的 stdio MCP 入口。`scripts` 提供应用打包和可选的本机验证工具。

## 提交变更

- 保持主页轻量，应用入口应有清晰名称和辅助功能标识。
- 修改分页或布局逻辑时运行 `swift test`，并覆盖对应边界。
- 修改界面时提供截图，检查小窗口、搜索、多页和辅助功能状态。
- 窗口排列需要用户在系统设置中授予辅助功能权限；测试只能操作明确选择的应用或独立测试窗口。
- 避免提交本机配置、文档内容、密钥、构建缓存或安装包。安装包通过 Release 分发。

Pull Request 请说明具体变化、验证方式，以及仍存在的限制。提交贡献即表示你同意该贡献以本项目的 MIT 许可证发布。

## 报告问题

请提供 macOS 版本、芯片类型、轻桌版本、复现步骤和预期结果。如果涉及窗口布局，请说明目标软件和窗口状态。截图前遮盖私人信息。

当前自动检查覆盖单元测试和应用构建；辅助功能权限及真实窗口排列需要在本机手动验证。

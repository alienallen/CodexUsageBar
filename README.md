# Codex Usage 菜单栏

打开同目录中的 `Codex Usage.app`，Mac 顶部菜单栏将显示随系统外观适配的柱状图图标。点击图标打开面板，查看蓝色额度进度、重置时间和最后更新时间，并可立即刷新或退出。面板随系统浅色和深色外观切换。应用每 60 秒刷新一次；更新失败时面板会显示错误提示，保留的百分比和重置时间是上次成功的数据。窗口只显示 Codex 实际返回的额度，接口没有提供的窗口不会显示。

如果菜单栏图标被隐藏，可检查菜单栏的折叠区域或菜单栏管理工具。

应用使用本机的 `codex app-server` 和现有登录状态，不保存凭据或用量历史。需要本机安装并登录 Codex CLI，且能够访问 Codex 服务。退出或重新登录 macOS 后需重新打开应用；不会自动设置开机启动。

本机开发版为 ad-hoc 签名，不是 Apple 公证的发行版。请保留此目录或将应用移动到自己希望保留的位置。

## 从源码构建

安装 Apple Command Line Tools 后，在此目录执行：

```sh
mkdir -p 'Codex Usage.app/Contents/MacOS' 'Codex Usage.app/Contents/Resources'
cp AppIcon.icns 'Codex Usage.app/Contents/Resources/AppIcon.icns'
cp Info.plist 'Codex Usage.app/Contents/Info.plist'
swiftc -O main.swift -o 'Codex Usage.app/Contents/MacOS/CodexUsage'
codesign --force --sign - 'Codex Usage.app'
'Codex Usage.app/Contents/MacOS/CodexUsage' --self-test
'Codex Usage.app/Contents/MacOS/CodexUsage' --check
open 'Codex Usage.app'
```

`--self-test` 验证额度解析；`--check` 通过本机 Codex 读取真实配额，仅输出额度和重置时间。

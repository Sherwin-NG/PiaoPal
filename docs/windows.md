# Windows 版

PiaoPal v0.2.1 提供原生 Windows 桌宠，复用 Mac 版的六款精灵素材。推荐 Windows 11；使用 .NET 10 支持范围内的 Windows 10 LTSC/Enterprise 版本时，请参阅 [Microsoft 系统支持表](https://learn.microsoft.com/en-us/dotnet/core/install/windows)。不承诺支持所有历史 Windows 10 消费者版本。

## 下载与启动

| 电脑 | 下载文件 |
| --- | --- |
| Intel / AMD 64 位电脑 | `PiaoPal-v0.2.1-Windows-x64.zip` |
| Windows on ARM，如骁龙电脑 | `PiaoPal-v0.2.1-Windows-arm64.zip` |

从 [GitHub Releases](https://github.com/Sherwin-NG/PiaoPal/releases/latest) 下载，将 ZIP **完整解压**到固定目录，再运行 `PiaoPal.exe`。运行环境已包含，无需管理员权限或单独安装 .NET；不要在压缩包预览中启动，也不要仅复制 exe。

首次启动显示设置。双击通知区域的 PiaoPal 图标可再次打开；图标可能位于隐藏图标区域。右键可打开设置、休息/唤醒、找回宠物或退出。再次运行 exe 会打开已有实例的设置。关闭设置不会关闭桌宠，桌面宠物不抢输入焦点，鼠标点击穿透到下方应用。

首次大小为 **1 倍**，已保存的大小、速度和角色在重启后保留。更新时先从托盘退出旧版，再将新包完整解压到新目录运行。社区构建尚未提供 Authenticode 发行者签名，校验和用于核对文件完整性，不替代发行者身份签名。

## 功能范围

| 功能 | Windows v0.2.1 |
| --- | --- |
| 六款内置伙伴、八方向动画、跟随鼠标 | 已提供 |
| 待机、挠痒、自然睡眠、手动休息与唤醒 | 已提供 |
| 昵称、大小、速度、简体中文 / English | 已提供 |
| 里程、等级、启动次数、连续相伴天数 | 已提供 |
| 本地保存、正常退出时保存剩余统计 | 已提供 |
| 多屏工作区、负坐标、显示恢复、找回宠物 | 已提供 |
| 手动检查 GitHub 更新 | 已提供 |
| Mac 的 32 项成就、卡片导出、六页回顾、激光逗猫、自定义素材目录、登录时启动 | 尚未移植 |

Windows 六款伙伴共用连续跟随逻辑；飘飘使用四帧步态表，其他伙伴使用原始两帧映射。跨屏时会重锚到实际工作区，避免停在非矩形桌面的空隙，重锚不累计路程。Windows 与 Mac 的运动细节不保证逐帧一致。

## 本地数据与诊断

正式数据目录为 `%LOCALAPPDATA%\PiaoPal`。设置和统计采用原子文件替换；损坏文件保留备份，优先从有效备份恢复。应用不会写入 Mac 偏好目录，也不提供跨设备同步。

`lifecycle.log` 记录启动、退出和运行异常，轮换保留上一份日志；`active-session.json` 用于识别上一次缺少正常退出记录。该情况也可能来自强制结束或断电，不等同于崩溃。日志留在本机，不自动上传。

## 开发与验证

需要 .NET 10 SDK。SDK 系列由根目录 `global.json` 限定，版本来自 `Windows/Directory.Build.props`。

```powershell
dotnet run --project Windows/PiaoPal.Core.Tests/PiaoPal.Core.Tests.csproj -c Release
pwsh -File scripts/test-windows.ps1 -RuntimeIdentifier win-x64
pwsh -File scripts/package-windows.ps1 -RuntimeIdentifier win-x64 -Version 0.2.1
```

ARM64 主机使用 `win-arm64`。核心测试可在 macOS/Linux 上运行；桌面测试必须在对应架构的 Windows 上运行。CI 使用 GitHub 官方 `windows-2025`（x64）和 `windows-11-arm`（ARM64）运行器，[官方运行器列表](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)可查。

桌面测试使用独立临时配置，启动真实 Windows 进程，检查透明窗口样式、帧渲染、设置窗口关闭后的持续运行、两次进程之间的偏好和里程保存、资源释放以及原生进程架构。打包脚本再运行自包含产物，核对 PE 架构、版本、精灵、ZIP 内所有文件和 SHA-256。

测试结果保留在 `build/windows-test-results/`。这些自动化检查不代表已经覆盖所有实体显卡、不同缩放比例的多屏、Windows 10 型号或长时间运行；这些场景仍需要实际电脑反馈。

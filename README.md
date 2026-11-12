<div align="center">
<img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="112" height="112" alt="飘伴 PiaoPal 图标" />

# 飘伴 PiaoPal

以家里的猫咪飘飘为灵感，为 Mac 和 Windows 带来一位像素伙伴。

**macOS 13+ · Windows x64 / ARM64 · 0.3.0**

[下载](https://github.com/Sherwin-NG/PiaoPal/releases/latest) · [反馈问题](https://github.com/Sherwin-NG/PiaoPal/issues) · [构建说明](docs/development.md) · [许可与致谢](THIRD_PARTY_NOTICES.md)
</div>

PiaoPal 是 [Sherwin-NG](https://github.com/Sherwin-NG) 独立维护的桌面宠物项目。银白色猫咪飘飘来自真实宠物照片：图标采用温柔插画，桌面角色采用像素动画。本项目使用独立仓库、应用标识、数据目录和更新地址，从 **0.0.1** 开始发布。

Mac 与 Windows 共用六款内置宠物素材：**飘飘 PiaoPiao、团团 TuanTuan、豆豆 Dodo、斑斑 BanBan、桃桃 TaoTao、暮暮 MuMu**。部分底层实现与既有素材按原开源许可使用，完整来源见[第三方说明](THIRD_PARTY_NOTICES.md)。

**0.3.0** 修复 macOS 与 Windows 上宠物自行退出的问题。相伴统计会定期写入，并在睡眠和退出前再保存一次，崩溃后已写入的进度可以恢复。Windows 继续提供 **x64 和 ARM64** 免安装包，两平台首次默认大小仍为 **1 倍**。详见[本版说明](releases/v0.3.0.md)。

## 下载和使用

打开 [GitHub Releases](https://github.com/Sherwin-NG/PiaoPal/releases/latest)，在 **Assets** 中选择：

| 文件 | 用途 |
| --- | --- |
| `PiaoPal-v0.3.0-macOS-universal.dmg` | 推荐。打开后把 PiaoPal 拖入 Applications |
| `PiaoPal-v0.3.0-macOS-universal.zip` | 解压后把 PiaoPal.app 放入 Applications |
| `PiaoPal-v0.3.0-Windows-x64.zip` | Windows Intel / AMD 电脑，解压整个文件夹后运行 PiaoPal.exe |
| `PiaoPal-v0.3.0-Windows-arm64.zip` | Windows on ARM 电脑，解压整个文件夹后运行 PiaoPal.exe |
| `SHA256SUMS.txt` | 核对以上四个安装包的完整性 |

Mac 通用包支持 Apple Silicon 和 Intel，要求 macOS 13+。Windows 推荐 Windows 11，另兼容 .NET 10 支持范围内的 Windows 10 LTSC/Enterprise 版本；提供原生 x64 与 ARM64 包并附带运行环境。选择与电脑架构相符的 ZIP；不要只复制 exe。Windows 使用和支持范围见[Windows 说明](docs/windows.md)。GitHub 自动附带的 **Source code** 是源码，不是安装包。

Mac 从菜单栏爪印进入设置，Windows 从通知区域的 PiaoPal 托盘图标进入设置；再次打开应用会唤出已有设置窗口。关闭设置后桌宠继续运行，退出请使用菜单。可以选择伙伴、调整昵称、大小和速度，或让她休息。设置和相伴记录保存在本机，不提供跨平台云同步。

当前 Mac 社区发行包使用 **ad-hoc 签名，未进行 Apple Developer ID 签名和公证**。首次打开时，macOS 可能提示无法验证开发者。核实下载来源后，可参考 [Apple 的打开说明](https://support.apple.com/102445)；无需关闭系统安全功能。

Windows 包尚未提供 Authenticode 发行者签名，请核对 GitHub 来源与文件校验和。

## 可以做什么

两平台均提供六款宠物、鼠标跟随、八方向动画、休息/唤醒、昵称/大小/速度设置、相伴里程与等级、本地保存和手动检查更新。Windows 当前提供简体中文和 English；完整功能范围见[平台对照](docs/windows.md#功能范围)。以下成就、卡片、回顾、激光和素材目录功能目前属于 Mac 版：

- 跟随鼠标活动，播放八方向行走、坐下、发呆、挠痒和睡眠动画。
- 六款内置伙伴，自定义昵称、大小和移动速度。
- 菜单栏休息与唤醒、激光逗猫、点击穿透和多屏活动。
- 查看统计、等级、连续相伴天数和 32 项成就。
- 导出陪伴卡，查看六页相伴回顾。
- 从宠物目录查看可用角色，在设置中检查 PiaoPal 更新。

这是独立应用：设置使用 `io.github.sherwinng.PiaoPal`，自定义素材存放于 `~/Library/Application Support/PiaoPal/Sprites/`。它不读取或覆盖其他应用的数据，也不自动迁移早期试制版本的记录。退出早期试制应用后再运行本版，可避免多个桌宠同时出现。

## 语言

Mac 支持 **简体中文、繁體中文、English、Français、日本語、Deutsch、Español**；Windows 首版支持 **简体中文、English**。首次启动按系统语言选择，也可在应用内切换。简体与繁体中文覆盖引导、设置、卡片、回顾、成就和错误提示。

简体显示名称为「飘伴」，繁体为「飄伴」，英文为「PiaoPal」。原始文案位于 `App/Localization/Language.swift`，成就文案位于 `App/Achievements/Achievement.swift`。

## 开发

Mac 构建需要 macOS、Xcode 和命令行工具。项目已提交 Xcode 工程，无需额外依赖即可打开：

```sh
git clone https://github.com/Sherwin-NG/PiaoPal.git
cd PiaoPal
open PiaoPal.xcodeproj
```

选择 `PiaoPal` scheme。脚本可以执行针对性检查并生成双架构发行包：

```sh
bash scripts/test-macos.sh
bash scripts/package-macos.sh 0.3.0
```

输出位于 `dist/`。打包流程构建 arm64 + x86_64、校验应用签名和 DMG，并生成 SHA-256 文件。它使用运行时 Metal 着色器编译路径，仍由 Metal 渲染；不要求额外安装独立 Metal Toolchain。

Windows 使用 .NET 10 与 WinForms。可在 Windows 上执行 `pwsh -File scripts/test-windows.ps1 -RuntimeIdentifier win-x64` 和 `pwsh -File scripts/package-windows.ps1 -RuntimeIdentifier win-x64`；ARM64 使用 `win-arm64` 并在 ARM64 主机验收。详见[Windows 构建说明](docs/windows.md#开发与验证)。

修改 `project.yml` 后，使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 运行 `xcodegen generate`。素材生成、预览和目录结构见[开发说明](docs/development.md)，发版流程见[维护者说明](docs/releasing.md)。自动化检查不能替代每种硬件和多屏组合的实际体验验证。

## 开源与素材来源

- 项目维护、中文体验和飘飘视觉方向：Sherwin-NG。
- 飘飘图标和像素角色：根据所有者提供的真实宠物照片，以 AI 辅助制作；原照片不随仓库或应用发布。
- 部分 macOS 实现：hellov3an / v3an，来自 OnekoMac，MIT License。
- 原有五款精灵：kyrie25/spicetify-oneko，沿用 adryd 的开源项目与署名，MIT License。
- 历史项目致谢：Masayuki Koba 的 oneko（1989）。

完整版权与许可见 [LICENSE](LICENSE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，也包含在应用与 DMG 中。PiaoPal 使用独立品牌，并保留所使用开源代码和素材的原作者权利。

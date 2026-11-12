# PiaoPal 发版说明

当前版本为 `0.3.0`，首版为 `0.0.1`。发布 macOS 13+ 通用包（arm64、x86_64）及 Windows x64、ARM64 自包含 ZIP。Mac 应用 ID 为 `io.github.sherwinng.PiaoPal`，仓库为 `Sherwin-NG/PiaoPal`；Windows 系统范围见 [Windows 说明](windows.md)。

## 准备版本

1. 同步 `Info.plist` 中的 `CFBundleShortVersionString` 与 `Windows/Directory.Build.props` 的 Version/AssemblyVersion/FileVersion，并更新当前文档与 Updater fallback。
2. 添加 `releases/v<版本>.md`，写明功能变化、系统要求与签名状态。
3. 如有工程变化，执行 `xcodegen generate` 并提交生成结果。
4. Mac 运行 `bash scripts/test-macos.sh` 和 `bash scripts/package-macos.sh <版本>`。Windows x64/ARM64 原生主机分别运行 `pwsh -File scripts/test-windows.ps1 -RuntimeIdentifier win-x64` / `win-arm64`，以及相同架构参数的 `scripts/package-windows.ps1 -Version <版本>`。
5. 检查打包后的应用身份、图标、菜单栏/托盘、语言、宠物切换和透明动画。检查各包均可打开且包含许可文件。Windows smoke 必须实际运行在相同架构，不把交叉编译当作原生验收。

输出固定为：

```text
PiaoPal-v<版本>-macOS-universal.dmg
PiaoPal-v<版本>-macOS-universal.zip
PiaoPal-v<版本>-Windows-x64.zip
PiaoPal-v<版本>-Windows-arm64.zip
SHA256SUMS.txt
```

在产物目录运行 `shasum -a 256 --check SHA256SUMS.txt` 可核对完整性。各平台独立构建时生成各自清单；最终发布执行 `python3 scripts/release-checksums.py --version <版本> --directory dist --platform all`，仅当 Mac 两个包与 Windows 两种架构包全部存在且非空时生成统一清单。SHA-256 用于校验文件完整性，不替代发行者签名。

## GitHub Actions

普通推送与 PR 运行 Mac 全套回归和通用打包、Windows x64/ARM64 原生回归与自包含打包，以及跨平台清单完整性检查。Windows 原生任务检查真实窗口和资源释放、关闭设置后继续运行、单实例唤回、默认 1 倍、跨进程设置和统计保存；结果保留为单独诊断产物。CI 保留下载产物，**不会公开发布版本**。

准备好提交后创建匹配版本标签，例如：

```sh
git tag v0.3.0
git push origin main
git push origin v0.3.0
```

Release 工作流检查标签与两平台版本，所有平台必须构建与验证通过，汇总前复核各自清单，然后生成四个包的统一清单并创建 **GitHub Release 草稿**。手动运行时需要输入已存在的标签；构建始终使用该标签对应的提交。Windows 包随附 .NET 运行环境，禁止省略运行时文件或仅上传 exe。

检查草稿的说明、安装体验与完整性后，由维护者完成公开发布。已获得正式发版授权时，可在核对通过后执行：

```sh
gh release edit v0.3.0 --draft=false --latest
gh release view v0.3.0 --json url,isDraft,isPrerelease,assets
```

确认版本已公开、不是预发布，恰好包含四个安装包和统一校验清单。重复运行工作流只更新草稿；已经公开发布的版本不能被工作流覆盖。修复公开版本时应递增版本并发布新标签。

## 签名与公证

Mac 脚本使用 ad-hoc 签名，不包含 Apple Developer ID 证书或 Apple 公证；Windows 包没有 Authenticode 发行者签名。发行说明必须如实披露。需要正式签名时，应通过 GitHub Secrets 管理证书和公证凭据，并在签名步骤就绪后再修改说明；不得将私钥或密码提交到仓库。

## 分发许可

Mac 的 `LICENSE` 和 `THIRD_PARTY_NOTICES.md` 必须位于应用的 `Contents/Resources/` 与 DMG 根目录。Windows 将这两份文件放在 `PiaoPal.exe` 旁，并保留运行时的许可及第三方通知。不得因品牌独立而删除所用开源代码或精灵的版权通知。

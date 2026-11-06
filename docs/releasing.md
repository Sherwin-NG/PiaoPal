# PiaoPal 发版说明

当前版本为 `0.2.0`，首版为 `0.0.1`，仅发布 Mac；安装包包含 arm64 和 x86_64，要求 macOS 13+。应用 ID 为 `io.github.sherwinng.PiaoPal`，仓库为 `Sherwin-NG/PiaoPal`。

## 准备版本

1. 修改 `Info.plist` 中的 `CFBundleShortVersionString`。
2. 添加 `releases/v<版本>.md`，写明功能变化、系统要求与签名状态。
3. 如有工程变化，执行 `xcodegen generate` 并提交生成结果。
4. 运行 `bash scripts/test-macos.sh` 和 `bash scripts/package-macos.sh <版本>`。
5. 检查打包后的应用身份、图标、菜单栏、语言、宠物切换和透明动画。检查 DMG 与 ZIP 均可打开，且均含许可文件。

输出固定为：

```text
PiaoPal-v<版本>-macOS-universal.dmg
PiaoPal-v<版本>-macOS-universal.zip
SHA256SUMS.txt
```

在产物目录运行 `shasum -a 256 --check SHA256SUMS.txt` 可核对完整性。只有 DMG 与 ZIP 均存在且非空时，校验脚本才会生成清单。SHA-256 用于校验文件完整性，不替代发行者签名。

## GitHub Actions

普通推送与 PR 运行 CI：语言、素材、运动、统计保存和更新器检查，双架构构建、签名验证、DMG 验证和校验清单生成。CI 保留下载产物，**不会公开发布版本**。

准备好提交后创建匹配版本标签，例如：

```sh
git tag v0.2.0
git push origin main
git push origin v0.2.0
```

Release 工作流检查标签与版本、构建和验证两种 Mac 包，然后创建 **GitHub Release 草稿**。手动运行该工作流时，需要输入已存在的标签；构建始终使用该标签对应的提交。

检查草稿的说明、安装体验与完整性后，由维护者完成公开发布。已获得正式发版授权时，可在核对通过后执行：

```sh
gh release edit v0.2.0 --draft=false --latest
gh release view v0.2.0 --json url,isDraft,isPrerelease,assets
```

确认版本已公开、不是预发布，并包含 DMG、ZIP 和校验清单。重复运行工作流只更新草稿；已经公开发布的版本不能被工作流覆盖。修复公开版本时应递增版本并发布新标签。

## 签名与公证

当前脚本使用 ad-hoc 签名，不包含 Apple Developer ID 证书或 Apple 公证。发行说明必须如实说明这一点。需要正式签名时，应通过 GitHub Secrets 管理证书和公证凭据，并在新的签名步骤就绪后再修改说明；不得将私钥或密码提交到仓库。

## 分发许可

`LICENSE` 和 `THIRD_PARTY_NOTICES.md` 必须同时位于应用的 `Contents/Resources/` 中，并在 DMG 根目录保留副本。ZIP 内的应用也包含这两份文件。不得因品牌独立而删除所用开源代码或既有精灵的版权通知。

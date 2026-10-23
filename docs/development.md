# PiaoPal 开发说明

首版版本为 `0.0.1`，支持 macOS 13+、Apple Silicon 与 Intel。本仓库只包含 Mac 应用。

## 项目结构

| 路径 | 内容 |
| --- | --- |
| `App/` | 菜单栏、引导、设置、卡片、回顾、成就与语言 |
| `Engine/` | 运动状态、鼠标输入、Metal 渲染和帧时序 |
| `Skins/` | 内置与自定义宠物素材加载 |
| `Resources/Sprites/` | 六款正式精灵表 |
| `Resources/Assets.xcassets/` | 应用图标 |
| `Resources/companion-catalog.json` | 宠物目录 |
| `artwork/piaopal/` | 飘飘生成原图、提示词和裁切清单 |
| `Tests/` | 语言、素材、更新器的针对性检查 |
| `Tools/` | 素材打包和动画预览工具 |
| `project.yml` | XcodeGen 工程定义 |

Xcode 工程、target、scheme、product 和 Swift package 均命名为 `PiaoPal`。bundle ID 为 `io.github.sherwinng.PiaoPal`。`Info.plist` 是应用版本的唯一来源，版本标签必须与它一致。

## 构建与检查

```sh
bash scripts/test-macos.sh
bash scripts/package-macos.sh 0.0.1
```

测试在独立临时目录编译并运行，不以测试数据覆盖真实用户设置。它们检查语言识别与格式占位符、成就文案、素材尺寸与动画映射、图标，以及更新器的版本比较和错误处理。

打包脚本调用 `PiaoPal.xcodeproj` 的 `PiaoPal` scheme，构建 Apple Silicon 与 Intel，进行 ad-hoc 签名，并输出 DMG、ZIP 和 `SHA256SUMS.txt`。每次运行使用新的暂存目录，已有产物不会作为输入。

发行包保留运行时 Metal 着色器编译方式；源码中的 `Shader.metal` 不需要在打包机上离线编译。发布前仍应在实际桌面检查透明边缘、鼠标跟随、菜单栏操作、多个显示器以及窗口缩放。

修改工程设置后执行：

```sh
xcodegen generate
```

已提交的 Xcode 工程是应用构建入口；`Package.swift` 提供 Swift 项目元数据，不能替代 Xcode 的应用签名、图标编译与发行打包。

## 飘飘素材

已确认方向：A 插画图标、B 像素桌宠，不加入口号。默认角色的视觉参考是所有者提供的真实猫咪飘飘照片，保留银白毛色、黄绿色眼睛、灰色额纹与粉棕鼻。动作属于艺术表达。

- 图标提供 16–1024px 的 Mac 尺寸。
- 飘飘精灵表为 512×256px、8×4 格、每格 64px，共 32 帧，映射到 17 个运动状态。
- 原有五款精灵表为 256×128px、每格 32px，继续由同一渲染器加载。
- 原始照片不随仓库分发；生成源图、实际提示词和裁切清单位于 `artwork/piaopal/`。

重新组装已有生成素材：

```sh
xcrun swiftc Tools/PreparePiaoPalAssets/main.swift -o /tmp/piaopal-assets
/tmp/piaopal-assets icon artwork/piaopal/icon-source.png Resources/Assets.xcassets/AppIcon.appiconset
/tmp/piaopal-assets pack artwork/piaopal/crop-manifest.json Resources/Sprites

xcrun swiftc Engine/Simulation/PetMotion.swift Tools/PreviewPiaoPalSprites/main.swift -o /tmp/piaopal-motion
/tmp/piaopal-motion "$PWD" build/piaopal-motion
```

`build/piaopal-motion/piaopiao-motion-review.gif` 是状态动画预览，`piaopiao-state-review.png` 是静态状态表。`scripts/preview-ai-pet.sh` 可用独立预览身份运行 Metal 动画，避免修改正式应用设置。

## 数据和网络

偏好设置存放于独立 bundle ID 的偏好域，自定义素材位于 `~/Library/Application Support/PiaoPal/Sprites/`。不自动迁移早期试制应用的数据。

检查更新使用 `https://api.github.com/repos/Sherwin-NG/PiaoPal/releases/latest`，下载页为 `https://github.com/Sherwin-NG/PiaoPal/releases/latest`。更新由用户手动下载与安装，不在后台替换应用。

## 许可

保留 `LICENSE` 和 `THIRD_PARTY_NOTICES.md`，包括原 macOS 实现和五款旧精灵素材的版权与许可。新增角色不改变已有素材的来源与权利。构建、打包及再次分发时不可移除这些通知。

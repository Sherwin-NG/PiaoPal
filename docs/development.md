# PiaoPal 开发说明

当前版本为 `0.3.0`，包含 macOS 13+ 通用应用与 Windows x64/ARM64 原生应用。Windows 的运行要求、功能范围和构建入口见 [Windows 开发与使用](windows.md)。

## 项目结构

| 路径 | 内容 |
| --- | --- |
| `Windows/PiaoPal.Core/` | Windows 的运动、动画映射与原子数据保存 |
| `Windows/PiaoPal.Windows/` | WinForms、Win32 透明窗口、托盘与设置 |
| `Windows/PiaoPal.Core.Tests/` | 可跨平台运行的运动与存储回归 |
| `App/` | 菜单栏、引导、设置、卡片、回顾、成就与语言 |
| `Engine/` | 运动状态、鼠标输入、Metal 渲染和帧时序 |
| `Skins/` | 内置与自定义宠物素材加载 |
| `Resources/Sprites/` | 六款正式精灵表 |
| `Resources/Assets.xcassets/` | 应用图标 |
| `Resources/companion-catalog.json` | 宠物目录 |
| `artwork/piaopal/` | 飘飘生成原图、提示词和裁切清单 |
| `Tests/` | 语言、素材、运动状态、统计保存和更新器的针对性检查 |
| `Tools/` | 素材打包和动画预览工具 |
| `project.yml` | XcodeGen 工程定义 |

Xcode 工程、target、scheme、product 和 Swift package 均命名为 `PiaoPal`。bundle ID 为 `io.github.sherwinng.PiaoPal`。`Info.plist` 是 Mac 版本来源；Windows 使用 `Windows/Directory.Build.props`。两者必须与发布标签一致，由发布流程检查。

## 构建与检查

```sh
bash scripts/test-macos.sh
bash scripts/package-macos.sh 0.3.0
```

测试在独立临时目录编译并运行，不以测试数据覆盖真实用户设置。它们检查语言识别与格式占位符、成就文案、素材尺寸与动画映射、图标、运动状态与步态时序，以及更新器的版本比较和错误处理。`Tests/MacMotion` 核对真实位移、待机、异常输入恢复及缩屏后停靠宠物重定位；`Tests/MacStats` 检查短会话跨进程保存、重复保存和并发里程累积；`Tests/MacLifecycle` 检查正常退出、未正常结束的上次会话及多实例诊断标记的隔离。后两组使用独立偏好域，均由 `scripts/test-macos.sh` 执行。

运行诊断只写本机系统日志，子系统为 `io.github.sherwinng.PiaoPal`。`lifecycle` 类别记录启动、退出请求、退出完成及上次缺少正常退出记录；该标记也可能由强制退出、断电等原因产生，不能直接判定为崩溃。`render` 类别记录显示器休眠、恢复和宠物重定位。`CVDisplayLink` 只在显示线程上累计帧间隔并切回主线程；Metal 的 `nextDrawable`、窗口 frame 和显示器几何都在主线程更新。显示配置开始变化或屏幕休眠时先停下 display link，结束后再重建。没有有效屏幕、Metal 设备被移除，或联合分辨率超过单张 drawable 上限时暂停绘制而不是让进程退出；恢复后将宠物移回实际存在的屏幕，重定位不累计步行里程。相伴里程仍写入原来的偏好键，并每分钟以及在睡眠、失去焦点和关机前原子写入 `~/Library/Application Support/PiaoPal/cat-stats.json`。

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
- 飘飘另有 `piaopiao-walk.png` 步态表：256×512px、4×8 格，每方向四帧；方向行依次为 N、NE、E、SE、S、SW、W、NW。原来的坐姿、睡姿和界面预览图保持不变。
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

当前四帧步态的实际依赖源图、提示词、打包清单与审核记录收录于 `artwork/piaopal/motion-v5/`；`motion-v4/` 保留继承的四个正方向源图及历史终审记录。完整 `motion-v3/` 目录与未采用退稿仅保留在制作机器本地，不上传源码仓库。v5 只修订斜向，采用 NE 内部第三稿与 SE 内部第四稿，其他候选不参与生产。重新打包及生成与旧角色的对比：

```sh
mkdir -p build/animation-audit
xcrun swiftc Tools/PreparePiaoPalWalk/main.swift -o build/prepare-piaopal-walk
build/prepare-piaopal-walk artwork/piaopal/motion-v5/walk-manifest.json Resources/Sprites/piaopiao-walk.png
cp -n Resources/Sprites/piaopiao.png build/animation-audit/before-piaopiao.png
xcrun swiftc Engine/Simulation/PetMotion.swift Tools/ReviewPetMotion/main.swift -o build/review-pet-motion
build/review-pet-motion .
```

`build/animation-audit/index.html` 提供同步播放、逐帧及大小控制，`motion-comparison.gif` 提供可直接查看的对比。工具复用生产 `PetAnimationTiming`，完整运动和状态转换另由 `Tests/MacMotion` 检查。飘飘使用连续位移与距离驱动步频，待机和睡眠在原始帧上缓慢呼吸；其它角色保留原有运动配置。素材打包仅裁切、缩放、平移和镜像，保留裁切范围内的原始透明度。

当前飘飘的基准速度为 160pt/s，继续乘以用户设置的速度倍率；原 v4 的 64pt/s 已由响应优化替换。完整步长为 `20 × displayScale` pt，步态最高 5 循环/s。低速按实际位移推进步态；达到上限后仍保持用户指定速度，因此小尺寸或高速下的残余滑移更明显。四帧素材不提供连续足锁，NE/NW 外侧后腿仍有保守伸收和拖步。

正式应用首次启动的默认大小为 1×，继续读取并保存用户自定义的大小、速度和角色设置。独立桌面预览与循环状态预览也统一使用 1×显示、1×速度，不再自动放大；预览使用独立身份，不覆盖正式偏好。

真实平移复查命令：`build/review-pet-motion . build/moving-review --moving-only --cycles 10`。输出包含 1×/2× GIF、每次换帧 PNG 与世界坐标 JSON；查看 GIF 首帧不等于观看动态。各方向的接地质量、审核记录与四帧局限见 [动画验收说明](animation-review.md)。

## 数据和网络

偏好设置存放于独立 bundle ID 的偏好域，自定义素材位于 `~/Library/Application Support/PiaoPal/Sprites/`。不自动迁移早期试制应用的数据。

检查更新使用 `https://api.github.com/repos/Sherwin-NG/PiaoPal/releases/latest`，下载页为 `https://github.com/Sherwin-NG/PiaoPal/releases/latest`。更新由用户手动下载与安装，不在后台替换应用。

## 许可

保留 `LICENSE` 和 `THIRD_PARTY_NOTICES.md`，包括原 macOS 实现和五款旧精灵素材的版权与许可。新增角色不改变已有素材的来源与权利。构建、打包及再次分发时不可移除这些通知。

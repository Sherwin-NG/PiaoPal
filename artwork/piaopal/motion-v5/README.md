# 飘飘斜向腿部与滑步修订

日期：2026-10-23 至 2026-10-24。PiaoPal v0.0.2 采用的图集 SHA-256：`4af1828cbcf80daece317ea69afcaa505f58cbbff410bc39d2b30c9af7d6ba41`。

本轮保持飘飘的银白奶油毛、灰纹、绿眼、粉耳、粗环尾和短腿比例，修正斜向主要支撑脚的回推方向、后腿回收及前后足的相序。默认移动速度仍为上一轮的 160pt/s，没有以降速掩盖滑步。N/E/S/W 和原始待机、睡眠图集保持不变。

## 实际采用的素材

图像编辑全部使用内建 imagegen，没有使用 API/CLI 生成。程序仅做矩形裁切、共同缩放、头身平移配准与镜像，保留裁切内的 RGBA，不绘制腿、不拼接肢体、不去除透明边缘。

| 图集行 | 四个源文件 | 编辑提示词 | 共同缩放 |
| --- | --- | --- | --- |
| NE | `ne-v3-k0.png` 至 `ne-v3-k3.png` | 同名 `*-prompt.txt` | 0.054 |
| SE | `se-v4-k0.png` 至 `se-v4-k3.png` | F0 为 `se-v3-k0-prompt.txt`；F1–F3 为 `se-v4-k1-prompt.txt` 至 `se-v4-k3-prompt.txt` | 0.047 |
| NW / SW | NE / SE 水平镜像 | 无额外生成 | 同原方向 |
| N / E / S / W | 沿用 motion-v4 的源文件及打包参数 | 见 [正方向素材记录](../motion-v4/README.md) | 未修改 |

`se-v4-k0.png` 是本地第三稿 F0 的原样副本。最终选择、裁切、锚点和镜像方式以 [walk-manifest.json](walk-manifest.json) 为准。实际交付文件为 [piaopiao-walk.png](../../../Resources/Sprites/piaopiao-walk.png)，256×512，四列八行，64px 单格。

v0.0.2 源码收录最终打包所需的 19 张源图、采用的实际提示词、对照基线和最终审核数据。未采用的候选、原始编辑参考图、历史清单和过程配准文件仅保留在作者本地，不随源码发布，也不参与构建。角色来源及第三方归属见 [素材来源](../README.md) 和 [第三方说明](../../../THIRD_PARTY_NOTICES.md)。

## 多轮讨论与取舍

四足结构、角色风格、步态接地三个角度分别检查，再交叉确认同一只脚在各相中的身份。主要问题是原 SE 支撑脚向前下漂移后突然复位，以及 NE 支撑阶段后移不足。

1. 初稿支撑轨迹不足，SE 描边也偏轻，退回。
2. 第二稿修正部分回推与描边；NE 触地与回收脚形仍不够明确，继续定点编辑。
3. NE 第三稿形成较一致的主要前后脚支撑轨迹，并通过形象和结构审核。
4. SE 第四稿减少后脚首段过度回推，补充回收；NE 第四稿的外后脚虽有更大动作，但出现反向支撑与描边跳变，退回。
5. NE 第五稿试图补线和外后脚，产生其他脚轨迹退步及一帧头身放大，弃用。没有采用单帧整体下沉或肢体拼接来修补测量结果。

最终采用 **NE 第三稿 + SE 第四稿**，选择已经验证的形象和动作改善。编号为这轮斜向修订内部的迭代号，不是应用版本号，也不是前轮素材目录的版本号。退稿原因保留在以上摘要中，退稿图片本身不属于发布源码。

## 验收范围和限制

最终独立报告：

- [角色和四足结构](final-art-delivery-review.txt)
- [整体步态与循环](final-gait-delivery-review.txt)
- [同脚接地与逐段残差](contact-delivery-review.txt)

四斜向分别在 1×、2×固定世界网格中导出三个周期，按真实位移及实际采样时刻检查循环。没有把 GIF 首帧描述为实时播放，也不把局部关键帧残差解释为完整连续动画的减滑百分比。

这是四帧像素步态的改善，**不是连续足锁**。NE/NW 外侧后腿伸收仍保守；SE/SW 后腿第二段横向回推仍偏少。持帧期间脚会随身体平移，1×及高速还受 5 周期/s 步频上限影响。前后脚的实测支撑段总体比原生产改善，但不能宣称每条腿、每段时间都已锁定地面。

## 重现与验证

在仓库根目录运行：

```sh
mkdir -p build
xcrun swiftc -O Tools/PreparePiaoPalWalk/main.swift -o build/prepare-piaopal-walk
build/prepare-piaopal-walk artwork/piaopal/motion-v5/walk-manifest.json build/piaopiao-walk-reproduced.png
cmp build/piaopiao-walk-reproduced.png Resources/Sprites/piaopiao-walk.png
shasum -a 256 build/piaopiao-walk-reproduced.png
bash scripts/test-macos.sh
```

最终清单只保留打包器实际使用的字段和格式说明，所有源图路径均相对清单所在目录。裁切与锚点已固定，重现不需要重新搜索配准参数；本次整理已重新打包并逐字节核对生产图集一致。若制作后续素材需重新配准，可用 `-O` 编译 `Tools/PreparePiaoPalWalk/register.swift`，自行提供新素材的配准输入。

[sha256.json](sha256.json) 列出本次发布收录的素材、提示词、清单和报告校验值，路径相对本目录；不包含校验表自身，避免循环校验。接地量化的可读报告及原始表格保存在 [报告](contact-delivery-review.txt)、[JSON](contact-delivery-data.json) 和 [CSV](contact-delivery-support.csv) 中。

## 本地预览与历史证据

审核报告中的 `build/diagonal-v5/`、固定地面截图、对照 GIF、标记图及预览程序路径均指作者本地证据，不随源码发布。保留报告原文以明确当时检查的范围；不能把这些路径当作仓库附件链接。发布源码包含可以重新导出运动证据的 `Tools/ReviewPetMotion/` 工具。

2026-10-24 的本地预览使用 `PiaoPal Diagonal Preview.app`，独立 bundle `io.github.sherwinng.PiaoPal.motionreview`，正常跟随模式、2×显示、1×速度。这次美术预览只替换行走素材，沿用上一轮响应优化二进制；包内资源哈希与审核图集一致。该预览构建记录不代表 v0.0.2 发行包的构建方式。

三位最终审查均已完成。完整 macOS 检查通过，见当时的 [测试输出](final-tests.log)。上述独立预览已启动并通过原生截图确认飘飘显示；截图只证明显示正常，没有被描述为连续行走录像。

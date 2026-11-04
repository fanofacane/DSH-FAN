# 第三方声明 · iOS

本页只列 DSH Fan 的 SwiftUI iOS 发行内容。参考项目 DSH Go 的 Flutter / 安卓客户端及其依赖不属于本项目，其声明见上游 DSH Go 仓库（https://github.com/ccch1mneyyy/dsh-go）。项目自有 Swift / 桥接代码为 AGPL-3.0-or-later；以下内容保留原版权与许可，不因移动或移植而改变。

许可原文保存在 `apple/Resources/Licenses/` 并随 App 资源打包；已删除实验探针及其专用 oracle 的历史许可见 旧仓库历史（未迁入 dsh-fan）。运行时内的软件包继续携带自身许可证。最终发行物的实际文件清单与固定 lock / 构建配方共同决定依赖范围。

## 界面、协议与素材

| 来源 | 版权与许可 | 当前用途 |
|---|---|---|
| PiPilot（CikeSeven/pi_pilot） | Copyright (c) 2026 CikeSeven，MIT | SwiftUI 聊天、通用组件与主题沿用原 Flutter 版移植的结构 / 设计；`PiPilot-MIT.txt` |
| DeepSeek Harness（deepseek-ai/deepseek-harness） | Copyright (c) 2026 DeepSeek，MIT | DSH 协议、二进制结果解码和消息 / 工作区行为；捆绑引擎及固定补丁 |
| ds-harness-remote（liguobao/ds-harness-remote） | Copyright (c) 2026 DSH Remote contributors，MIT | `apple/Modules/DSHRemote/Relay/` 的协议、分帧、账号和中继载体移植，参考上游提交 `7e387df`；`ds-harness-remote-MIT.txt`。没有引入 WebRTC |
| Phosphor Icons 2.1.1 | Copyright (c) 2023 Phosphor Icons，MIT | `apple/Resources/Fonts/DshIcons.ttf` 字形子集与 `Glyphs.swift` 映射；`Phosphor-MIT.txt` |
| JetBrains Mono | Copyright 2020 The JetBrains Mono Project Authors，SIL OFL 1.1 | `apple/Resources/Fonts/JetBrainsMono-*.ttf`；`JetBrainsMono-OFL.txt` |

品牌图形、鲸鱼尾巴和 Deepy 宠物的使用条件独立于源码许可，见下方「品牌与吉祥物素材」。宠物包只兼容 Clawd on Desk 的格式，没有复制其代码。

## SSH 的 Swift Package 依赖

版本与提交以工程的 `Package.resolved` 为准，许可原文及适用 NOTICE 按包名收录在 `apple/Resources/Licenses/`。

| 包 | 固定版本 | 许可 |
|---|---|---|
| swift-asn1 | 1.7.4 | Apache-2.0（适用时含 Swift Runtime Library Exception） |
| swift-atomics | 1.3.1 | Apache-2.0（适用时含 Swift Runtime Library Exception） |
| swift-collections | 1.7.5 | Apache-2.0（适用时含 Swift Runtime Library Exception） |
| swift-crypto | 5.1.0 | Apache-2.0（适用时含 Swift Runtime Library Exception） |
| swift-nio | 2.104.0 | Apache-2.0（适用时含 Swift Runtime Library Exception） |
| swift-nio-ssh | 0.15.1 | Apache-2.0（适用时含 Swift Runtime Library Exception） |
| swift-system | 1.8.1 | Apache-2.0（适用时含 Swift Runtime Library Exception） |

swift-crypto 的原生加密组件还受其所附第三方许可约束，不能只按顶层 Apache 声明归类；其 LICENSE / NOTICE 与实际链接组件的原声明均须保留。SwiftUI、CryptoKit、UIKit、UserNotifications 等 Apple 系统框架通过公开 SDK 链接。

## iSH 内核与导入器

- OpenMinis/ish-arm64 固定提交 `c5c264da19148512167aa493d7bd4e50aae1b74e`。编译内核、解释器、fakefs 与导入工具；版权归 iSH 及分支贡献者，GPL-3.0，含上游 iOS 附加条款说明，原文见 `ish-LICENSE.md` 与 `ish-LICENSE.IOS`。
- OpenMinis/OpenMinis 参考提交 `1a71df0f381cefde80bf912b723de6f9831bc177`。`apple/Modules/DSHRuntime/Native/ISHRuntime.m` 的挂载、PID 1 / 子进程、stdio、DNS、UTF-8 locale 与客体文件适配由已验证的 RuntimeKernel 改写，保留 GPL-3.0-or-later 标记与原贡献者版权；原文见 `OpenMinis-GPL-3.0.txt`。
- 唯一补丁链在 `runtime/ios/patches/series.json`，在独立导出中应用，未修改外部上游克隆。SIMD、PTY、poll、日志隐私和 fakefs xz 改动保留原许可，修改及哈希由 series 记录。
- libarchive 固定子模块提交 `fc6563f5130d8a7ee1fc27c0e55baef35119f26c`，用于导入运行时归档，保留各文件 BSD 版权与 `libarchive-COPYING`。
- xz 公共 C API 头文件来自 tukaani-project/xz v5.8.2，提交 `3d078b52adbff566ccfc51067dfbf742ecf3ef86`，BSD 0-Clause，见 `xz-COPYING.0BSD`；链接 iOS SDK 的公开 liblzma。
- `runtime/ios/guest/wasm-polyfill.js`、`fetch-polyfill.js` 原样取自上述固定 ish-arm64 提交，保留上游注释与 GPL 声明，并随正式 rootfs 安装至 `/lib/`。`zero_free.c` 为本项目依据公开需求独立实现，AGPL-3.0-or-later。探针 oracle 和临时凭据服务不进入正式包。

## 捆绑的 Alpine / Node / DSH

正式 rootfs 由 `runtime/build-ios-runtime.sh` 调用 `runtime/ios/scripts/` 配方构建，以下版本已从当前归档的包元数据核对。各 Alpine 包的版本、签名、来源与哈希见配方及生成的 provenance；其版权文本保留在运行时内。GPL / LGPL 等内容的对应源码与修改说明应按该发行归档的实际清单提供，不能用主包许可替代。

| 组件 | 版本 | 许可 / 说明 |
|---|---|---|
| Alpine Linux / musl 及基础软件包 | 3.21 | 各包自身许可，以构建配方与 rootfs 内原文为准 |
| Node.js | 24.22.1 | MIT 及其捆绑组件许可；运行时 `/opt/node/LICENSE` |
| DeepSeek Harness | 0.2.1-rc.4 | MIT，依赖由 `runtime/locks/dsh-0.2.1-rc.4/` 固定，补丁由 pins 固定 |
| pnpm | 11.28.5 | MIT，随归档提供；App 启动禁用插件管理器，不提供联网安装入口 |
| node-pty | 1.2.0-beta.15 | MIT，按 iOS 运行时配方重新构建 |
| koffi | 3.1.1 | MIT，按同一配方重新构建 |
| sharp | 0.35.5 | Apache-2.0，按同一配方重新构建 |
| @img/sharp-libvips-linuxmusl-arm64 | 1.3.4 | LGPL-3.0-or-later 及其捆绑组件许可，保留实际包内声明与对应源码 |
| @deepseek-ai/libreoffice-kit | 0.1.5 | MPL-2.0，保留实际包内 LICENSE / NOTICE |
| tzdata | 2026e-r0 | Public Domain，构建核对固定 Alpine 包哈希与签名 |

npm 的其他直接 / 传递依赖继续保留包内许可。lock 中含未分发的可选平台包，不将其全部列为 iOS 已包含组件。原安卓的 PRoot、Shizuku、ADB、Flutter、WebRTC 和 JVM 库不再属于此 iOS 发行内容。

## 品牌与吉祥物素材

下列品牌和美术素材不在 AGPL-3.0-or-later 授权范围内。除另有说明，版权归 ccch1mneyyy（DSH-TUI）所有，保留所有权利。可为了构建、测试和运行本仓库使用；以修改版或衍生作品再发布时，请使用自己的名称与素材。

| 素材 | 当前 iOS 位置 | 来源与条件 |
|---|---|---|
| DSH Go 鱼尾 / 气泡品牌标识 | `apple/App/Assets.xcassets/BrandGlyph.imageset/` | DSH Go 的品牌图形，暂作占位；正式发布前应换成 DSH Fan 自己的标识 |
| Deepy 像素鲸鱼 | `apple/Resources/Pets/deepy-whale/` | DSH-TUI 吉祥物，宠物包只沿用 Clawd on Desk 的格式，不复制其代码 |
| 鲸鱼尾巴 | `apple/Resources/Images/whale_1.png` | 含 DeepSeek 官方标识及其衍生图形的原素材，相关版权 / 商标归原权利人，不代表官方背书 |

这些鲸鱼形象属于 DSH-TUI 的非官方形象，与 DeepSeek 无关联。原作者官网、分享页、社群二维码与历史宣传素材已从仓库删除；删除不改变这些历史素材的权利条件，旧仓库历史中的副本不能移作自己发行产品的品牌。

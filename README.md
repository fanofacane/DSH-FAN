# DSH Fan

[English](README.en.md) · [架构](docs/architecture.md) · [任务清单与硬规则](docs/design/ios-codex-tasks.md) · [功能与验收状态](docs/design/ios-native-parity.md)

DSH Fan 是一个全新的 iOS 原生（SwiftUI）项目：在 iPhone / iPad 内运行捆绑的 DeepSeek Harness（DSH）引擎，也可以通过 SSH 或自建 DSH Remote 中继连接自己的电脑 / 服务器。

它不是 DSH Go 的 iOS 移植版，而是在学习 [DSH Go](https://github.com/ccch1mneyyy/dsh-go) 与 [iSH](https://github.com/ish-app/ish) 的基础上独立开发的新项目，维护仓库为 [fanofacane/dsh-fan](https://github.com/fanofacane/dsh-fan)。

**方向**：目前功能仍比较基础；后续会朝两个方向发展——

- **手机端助手**：借助 iOS 公开系统能力（日程、提醒、闹钟、快捷指令、通知等）替你完成手机上的事情。
- **可交互的情绪伴侣**：以桌宠形象为起点，做能陪伴、能回应情绪的交互角色。

## 仓库地图

**日常 iOS 开发只需要看 `apple/App/` 和 `apple/Modules/`。**

| 目录 / 文件 | 用途 | 什么时候需要碰 |
|---|---|---|
| `apple/` | iOS App：界面、状态、四个模块、系统扩展、资源与测试（细分见下节） | 日常开发 |
| `runtime/` | App 内置引擎（Alpine + Node + DSH）的构建配方、引擎补丁、HTTP 桥；iOS 配方说明见 [runtime/ios](runtime/ios/README.md) | 改引擎版本、启动方式或打包 |
| `tooling/` | 工程生成器、iSH 框架构建、冒烟测试与模型夹具 | 改工程结构或开发工具 |
| `docs/` | 架构、任务清单、功能对照表、更新记录 | 找设计依据、更新完成记录 |
| `.agents/` | AI 代理的审查技能 | 调整自动检查 |
| `AGENTS.md`、`CLAUDE.md` | Codex / Claude Code 每次启动自动读取的工作规则 | 改协作约定 |
| `LICENSE`、`THIRD_PARTY_NOTICES.md` | 本项目许可证；第三方组件和素材的许可声明（法律要求随附） | 新增依赖或素材 |

### apple/ 目录

| 目录 | 用途 |
|---|---|
| `App/` | SwiftUI 入口与组装（`Core/`）、设计组件（`Design/`）、按功能分区的界面与 Store（`Features/`）、DEBUG 工具（`Debug/`） |
| `Modules/` | 四个框架：DSHClient（通信）、DSHRemote（SSH / 中继）、DSHRuntime（内置引擎）、DSHPhone（手机控制）；不依赖 App |
| `Modules/DSHRuntime/Native/` | iSH 的 Objective-C 桥接；由 `tooling/build-ish.sh` 编进 `ish.xcframework`，改动后需重建框架 |
| `Extensions/` | 小组件（`Widgets/`）、分享扩展（`Share/`），以及与 App 共用的类型（`Shared/`） |
| `Resources/` | 字体、图像、Deepy 桌宠、手机控制资源（含工具目录契约 `Phone/phone-ios-tools.json`）、第三方许可原文 |
| `Tests/` | Swift Testing：协议契约、Store 与依赖边界 |
| `DSH.xcodeproj/` | 生成器输出，**不要手改**，改 `tooling/generate-apple-project.rb` |
| `Vendor/`、`.build/` | 本机生成的 iSH 框架和构建缓存，不提交 |

## 能做什么

- 流式对话、Markdown、图片附件、语音输入、消息分叉 / 重答 / 编辑。
- 会话搜索、重命名、删除（主机支持时）、置顶 / 归档，工作区选择和文件预览。
- 待办与目标、工具批准与提问、Agent 预设、子任务、用量与运行信息。
- DeepSeek API Key、自定义模型服务商，以及本机 DeepSeek 账号授权流程；真实账号回跳仍待人工验收。
- 定时任务、本地通知、回复偏好、外观、语言、检查后诊断导出。
- Apple 公开系统接口提供的手机操作、快捷指令、小组件、实时活动与 Deepy 桌宠。

完整状态和限制见[功能对照表](docs/design/ios-native-parity.md)。终端和 WebRTC 直连暂缓；原作者的社区、市场、托管分享及服务器均已删除，不接入。插件安装已取消，插件管理器每次启动均禁用；未来插件只能随 App 打包（方案 A），后台开关接口尚未设计。

iOS 可能在进入后台后很快挂起 App。本机任务与定时任务需要引擎持续运行；远程主机可以继续工作，但挂起的 App 无法接收实时事件，也没有服务器推送。

## 构建

需要 Apple silicon Mac、Xcode（包含 iOS SDK 和 iPhone 18 Pro 模拟器）、Ruby 的 `xcodeproj` gem，以及构建 iSH / Alpine 运行时所需的 Meson、CMake、Ninja、Docker，以及能生成 Linux AArch64 ELF 的 LLVM / LLD 或 Zig（使用 Zig 时设置 `ISH_VDSO_COMPILER=zig`）。部署目标为 iOS 17；真机签名由使用者配置。

```bash
bash tooling/build-ish.sh
bash runtime/build-ios-runtime.sh
ruby tooling/generate-apple-project.rb
SIM=51831DA4-9348-4053-A81C-54B3C995A73A
xcodebuild -project apple/DSH.xcodeproj -scheme DSH \
  -destination "platform=iOS Simulator,id=$SIM" build
```

正式测试、Release 构建、冒烟测试与测试基线见 [任务清单第 4 节](docs/design/ios-codex-tasks.md#4-构建与验证)。模拟器命令必须显式使用上述设备 ID；所有模拟器共用 Mac 的 `127.0.0.1:3080`，不能同时运行两份 DSH；不要在 WOO UI Review 安装 / 运行 DSH，也不要关闭它。

## 开发约定

- 目前不接受外部 Pull Request，建议请用 [Issue](https://github.com/fanofacane/dsh-fan/issues/new/choose)。
- 工程文件由生成器维护；运行时补丁与 `runtime/patches/pins.json` 同步。
- 改动围绕一个问题，避免无关格式化、依赖升级和抽象；协议改动同时检查调用方与兼容性。
- 界面文案用英文 key，并在 `Localizable.xcstrings` 补齐简体中文；权限说明在 `InfoPlist.xcstrings`。README 中英同步。
- App 不下载、安装或更新可执行代码：不得恢复插件安装 / 市场入口，不得移除启动时禁用插件管理器的补丁；新增系统接口同步隐私清单。
- 第三方内容保留来源、版本、版权与许可；移动文件不改变许可。
- 涉及手机系统操作、签名、通知、后台期限的改动须真机验证，模拟器结果不能替代。
- 只暂存明确路径；不提交构建缓存、个人配置、密钥、Cookie、真实对话或设备信息。诊断包外发前人工检查。

## 安全问题

不要在公开 Issue 中提交漏洞细节、密钥或真实用户数据。请通过仓库的 [Security Advisories](https://github.com/fanofacane/dsh-fan/security/advisories) 私密报告；没有该入口时，先开一个只询问「如何私密联系维护者」的 Issue。报告中写明 App 版本、iOS 版本、连接方式（本机 / SSH / DSH Remote）、影响与最小复现，复现材料使用虚构内容或测试账号。只在自己的设备、账号和获授权的环境中复现。

## 致谢

DSH Fan 参考并学习了以下项目，感谢它们的作者与贡献者：

- [DSH Go](https://github.com/ccch1mneyyy/dsh-go)（AGPL-3.0）：Android 端 DeepSeek Harness 客户端。本项目的界面风格、桥接插件 `dsh-go-bridge`、引擎补丁与部分设计参考了它；为了与引擎兼容，`/opt/dsh-go`、`/dsh-go/v1` 等桥接路径保留原名。
- [iSH](https://github.com/ish-app/ish)（GPL-3.0）及 [OpenMinis/ish-arm64](https://github.com/OpenMinis/ish-arm64)：在 iOS 上运行 Linux 用户态的内核与解释器。
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（MIT）：捆绑运行的智能体引擎。

完整的第三方许可与素材条件见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 许可

本项目沿用传染性（copyleft）开源协议，源码以 AGPL-3.0-or-later 发布（见 [LICENSE](LICENSE)）：分发修改版或通过网络向他人提供服务时，须以相同协议公开对应源码。iSH 等第三方组件保留各自许可，品牌与吉祥物素材另有使用条件，均见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

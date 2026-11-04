# iOS 版执行清单

> 结构更新（2026-11-04）：独立实验探针已删除，历史源码见 旧仓库历史（未迁入 dsh-fan）；正式构建输入现位于 `runtime/ios/`。下文的旧探针路径仅记录当时实验，不是当前构建入口。

> 历史设计记录：其中的原 Flutter / 安卓实现已删除，可在 上游 DSH Go 仓库 查看。当前 iOS 状态以 `docs/design/ios-native-parity.md` 为准。

> 2026-11-02 起草，同日修订：iOS 必须有本地模式，远程降为可选项；手机控制只做系统框架这一档，不接 iCTRL。
>
> 执行者：编码智能体（Codex 等）。先读仓库根目录的 `AGENTS.md` 和 `README.md`，里面的硬规则（不 `git add .`、不手改生成物、中英文案同步、未经要求不 commit 或 push）对本清单所有任务继续有效。

## 0. 目标与边界

### 目标（按优先级）

1. **本地模式（必须）**：和 Android 版一样，DSH 引擎跑在 iPhone 自己身上，不依赖电脑或服务器。
2. **手机控制**：在 iOS 允许的范围内，通过系统框架和快捷指令实现。
3. **Liquid Glass**：部分页面在 iOS 26+ 上使用系统的 Liquid Glass。
4. **远程模式（可选，加分项）**：通过 SSH 或 DSH Remote 连接电脑上的 DSH。

### 技术路线

| 层 | Android 现状 | iOS 方案 |
|---|---|---|
| 界面 | Flutter（`原 Flutter 版 lib`） | 同一份 Flutter 代码 |
| DSH 客户端 | `原 Flutter 版 dsh_client` | 原样复用 |
| Linux 环境 | proot + Ubuntu arm64（`runtime/`） | **ish-arm64**：在 App 进程内解释执行 arm64 Linux 程序。参考 OpenMinis（GPL-3.0）已上架 App Store 的做法 |
| 原生层 | Kotlin | Swift，平台通道名和数据格式与 Android 一致 |
| 手机控制 | 无障碍服务 + MCP（`phone/`） | 系统框架 + 快捷指令 + MCP，桥接方式参照 Android |

**参考项目**

- `https://github.com/OpenMinis/ish-arm64`：iSH 的 ARM64 分支，GPL-3.0。
- `https://github.com/OpenMinis/OpenMinis`：其中的 `src/ios/` 展示了如何把 ish-arm64 嵌进 Swift App，GPL-3.0。
- 本仓库主体是 AGPL-3.0，可以和 GPL-3.0 代码组合（AGPL-3.0 第 13 条）。拷贝或改写的文件必须保留原版权声明，并登记到 `THIRD_PARTY_NOTICES.md`。

### 已确定的边界

| 项 | 结论 |
|---|---|
| 读屏、点击、输入其他 App | 不做，不接 iCTRL。iOS 没有可上架的实现方式 |
| 自更新 APK、桌宠系统悬浮窗、Shizuku/ADB、动态取色、小米焦点通知 | 不做，入口隐藏 |
| App 在后台时引擎继续运行 | 做不到。iOS 会挂起整个 App 进程，引擎跟着冻结。处理方式见 2.6 |

### 通用约定

- 平台判断统一用 `defaultTargetPlatform`。新建 `原 Flutter 版 lib/platform/platform_caps.dart`，集中放"本平台支持什么"的布尔量，业务代码只读这里。
- 新界面文案写进 `原 Flutter 版 lib/l10n/parts/*.arb`（中英两份），然后运行 `python3 原 Flutter 版 tool/l10n_merge.py`。
- Swift 代码放在 `原 Flutter 版 ios/Runner/<功能>/`，目录和 Kotlin 的 `dsh_app/<功能>/` 一一对应。
- 每个任务的报告都要写清实际执行的验证命令和结果。需要真机却没跑的，写"未运行"和原因。
- **基准设备**：最低 iPhone 12（A14、4 GB 内存），主力测试用 iPhone 15 Pro 或更新的机型。性能数据两台都要测。

---

## 阶段 1：iOS 工程骨架

- [ ] **1.1 生成工程**
  - 在 原 Flutter 客户端目录 下执行 `flutter create --platforms=ios --org io.github.ccch1mneyyy .`。只保留新生成的 `ios/`，不能覆盖已有的 `lib/`、`pubspec.yaml`、`test/`，执行后用 `git status` 核对。
  - 最低系统版本 iOS 16.0。iOS 26 才有的 API（Liquid Glass、AlarmKit）放进 `if #available(iOS 26, *)` 分支。
  - Bundle ID 暂用占位值 `io.github.ccch1mneyyy.dshgo.ios`。名称和图标的限制见阶段 7。
- [ ] **1.2 依赖核对**：逐个确认 `原 Flutter 版 pubspec.yaml（上游 DSH Go 仓库）` 的依赖在 iOS 上能不能用，结果写进报告。`webview_flutter_android` 的直接引用要用平台分支包住。
- [ ] **1.3 Info.plist**：补齐权限说明，包括麦克风、语音识别、相机、相册（仅添加）、本地网络、日历（仅写入）、提醒事项、AlarmKit。中英文写在 `InfoPlist.xcstrings`。`LSApplicationQueriesSchemes` 加上 `iosamap`、`baidumap`、`shortcuts`。
- [ ] **1.4 授权项**：申请 `com.apple.developer.kernel.increased-memory-limit`，它能提高 App 的内存上限，引擎会用得上。
- [ ] **1.5 验证**：`cd app && flutter pub get && flutter analyze && flutter test`，再跑 `flutter build ios --simulator --debug`，模拟器能启动到引导页。

## 阶段 2：本地运行时（核心，最高优先级）

### 2.1 技术验证（先做，交报告给用户，再进入 2.2）

目的：用数据证明 iPhone 上能跑 DSH 引擎，并且找出最快的组合。

- [ ] 做一个最小的 iOS 测试 App（可以放在 `原 Flutter 版 ios/RuntimeProbe/`，也可以单独建工程），嵌入 ish-arm64，依次测试：
  1. **rootfs 选型**，按顺序尝试：
     - **A**：复用 Android arm64 的 Ubuntu / glibc rootfs（历史候选，已放弃；源码和原构建入口见 旧仓库历史（未迁入 dsh-fan））。当前正式实现采用方案 B。
     - **B**：Alpine（musl）+ Node 24 的 musl 版本，DSH 的 npm 依赖按 `runtime/locks/dsh-<version>/package-lock.json` 安装。原生模块（`node-pty`、`koffi`、`sharp`）换成 linuxmusl-arm64 版本。OpenMinis 走的就是 Alpine。
  2. **Node 运行模式**：默认（开 JIT）和 `--jitless` 都要测。iSH 解释执行客体程序，V8 的 JIT 在模拟器里不受 iOS 限制，可能反而更快；`--jitless` 会关掉 WebAssembly，DSH 依赖里的 `@deepseek-ai/libreoffice-kit-wasm` 会不可用。
  3. 能不能跑通 `node -e "console.log(1)"` → `dsh --version` → `dsh web --host 127.0.0.1 --port 3080 --no-open`，并且 iOS 原生代码能从 `127.0.0.1:3080` 访问到它（确认 iSH 的 socket 会映射成真实的 iOS 网络）。
  4. 原生模块：用 `node-pty` 开一个终端，用 `koffi` 加载一次库，用 `node:sqlite` 做一次会话查询。
- [ ] **报告里要有这些数据**（两台基准设备都要测）：

| 指标 | 初定目标（用户可以调整） |
|---|---|
| 首次安装（解压 rootfs）耗时 | ≤ 90 秒 |
| 冷启动：点"启动引擎"到 `dsh web` 可以访问 | ≤ 30 秒 |
| 热启动：App 被挂起后回到前台 | ≤ 3 秒，不需要重启引擎 |
| 一轮对话的引擎额外开销（不算模型响应时间） | ≤ 2 秒 |
| 引擎空闲时的内存 | ≤ 1.2 GB |
| 安装后磁盘占用 | ≤ 1.5 GB |

- [ ] 达不到目标时，先按 2.5 的优化项逐个尝试，并记录每项的效果。**全部优化做完还是差很多，就停下来，把数据交给用户决定**，不要自己降低目标，也不要改成只做远程。

### 2.2 嵌入 ish-arm64

- [ ] 把 ish-arm64 编译成 `.xcframework`，放进 `原 Flutter 版 ios/Vendor/ish/`。构建脚本写在 `tooling/build-ish.sh`，源码版本在脚本里固定（commit hash）。
- [ ] 在 `原 Flutter 版 ios/Runner/Runtime/` 下用 Swift 封装这几项能力：启动内核、挂载 rootfs、按 argv 和 env 启动进程、读 stdout/stderr、发信号、等待退出。参考 OpenMinis `src/ios/` 的封装方式。
- [ ] 引擎放在后台线程运行，不能阻塞 Flutter 的 UI 线程。

### 2.3 iOS 运行环境构建

- [ ] 使用独立 `runtime/build-ios-runtime.sh`，产出 `runtime/out/ios-arm64/assets/runtime/rootfs-ios-arm64.tar.xz` 和 `manifest.json`。正式实现采用 Alpine / Node 24，原安卓构建入口已删除。
- [ ] `runtime/patches/` 的补丁和 `pins.json` 的校验照常执行，DSH 版本没有校验过就让构建失败，规则和 Android 一致。
- [ ] 桥接插件 `runtime/bridge/dsh-go-bridge` 照常安装。
- [ ] 去掉 proot 相关的 `lib*.so`（iOS 用不到）。
- [ ] 把 rootfs 打进 App 包（`Runner` 的资源）。如果包体超过 App Store 的限制，改用按需资源（On-Demand Resources）或首次启动时下载。下载的话必须校验 `manifest.json` 里的哈希。

### 2.4 实现 `dsh/runtime` 通道（与 Android 完全一致）

契约见 `docs/architecture.md` 的"平台通道约定"，Dart 侧（`原 Flutter 版 lib/runtime/`）原则上不用改。

- [ ] `MethodChannel('dsh/runtime')`：`getStatus`、`install`、`start`、`stop`、`getLogs`、`getLogSnapshot`、`reset`。
  - `RuntimeStatus.abi` 新增取值 `ios-arm64`，同时检查 Dart 侧所有 `switch` 的地方。
- [ ] `EventChannel('dsh/runtime/events')`：`progress`、`status`、`logs`。`LogEntry.seq` 的规则（单调递增，重启也不归零）和脱敏要求与 Android 一致。
- [ ] Swift 端照着 `RuntimeInstaller.kt`、`DshProcess.kt`、`RuntimeController.kt`、`RuntimeLogs.kt` 的行为实现：
  - 解压时校验哈希。
  - 从 stdout 里解析出 token。
  - 停止引擎时先停 DSH，再结束整个 iSH 进程树。
  - 保留 `SafeMode.kt` 的安全模式：不加载插件，用来救急。
- [ ] 用户数据（`/root`、会话）放在 `Application Support` 下面，不放 `Caches`，避免被系统清理。iCloud 备份默认排除 rootfs，只备份用户数据。
- [ ] 2.1 里只在测试 App 验证过的原生模块，要在正式 App 里再跑一遍。

### 2.5 性能优化（2.1 达标后也要做，提升体验）

- [ ] 打开 Node 的编译缓存（`NODE_COMPILE_CACHE` 指向持久目录），第二次启动起就不用重新编译 JS。
- [ ] 减少启动时的文件读取：iSH 里每个系统调用都很贵。统计 `dsh web` 启动时读了多少文件，评估能不能预打包，或者把默认插件改成按需加载。
- [ ] 在设置里提供"轻量模式"：只加载聊天必需的插件。
- [ ] 尝试 Node 的启动快照（`--build-snapshot` / `--snapshot-blob`）能不能用于 DSH。
- [ ] 对比 ish-arm64 不同的编译选项和解释器配置。
- [ ] 每做一项都在报告里写清优化前后的指标。

### 2.6 前后台与生命周期

iOS 会冻结后台 App 的整个进程，这一点必须在设计里正面处理：

- [ ] **挂起后恢复**：App 退到后台时，进程被冻结但不会被杀，引擎在内存里原样保留，回到前台继续运行。需要验证：
  - 冻结期间断掉的模型 API 请求，DSH 能不能重试，或者给出清楚的错误让用户重发。必要时在 `runtime/patches/` 加补丁，比如让流式请求失败后自动重试。
  - 回到前台后，Dart 客户端自动重连 `127.0.0.1:3080`，并补齐消息。
- [ ] **争取时间**：有任务在跑时退到后台，调用 `beginBackgroundTask` 争取大约 30 秒，让当前这一步尽量完成。
- [ ] **被系统杀掉之后**：内存紧张时 iOS 可能直接结束 App。会话已经保存在磁盘上，下次打开自动启动引擎并恢复，界面要提示"上次任务被系统中断"。
- [ ] **长任务**：
  - 在设置里提供"任务进行时保持屏幕常亮"（`isIdleTimerDisabled`），默认关闭。
  - 用实时活动显示进度，参照旧仓库历史中的 `live-activity.md` 设计稿。
  - 界面要说明清楚：App 留在前台时，长任务才会一直跑下去。
- [ ] **不要用后台音频、后台定位之类的手段让 App 保持活跃**，这类做法会被审核拒绝。
- [ ] 引擎的 CPU 占用要配合系统发热状态降级，复用 `dsh/performance` 通道（2.7）。

### 2.7 引导与入口

- [ ] 引导页（`原 Flutter 版 lib/ui/onboarding/`）和 Android 一致：默认推荐"本机"，"远程主机"是另一个选项。
- [ ] 本机流程：安装运行环境（显示进度）→ 登录 DeepSeek 或填写 API Key → 开始聊天。
- [ ] 存储空间不够时（用 `volumeAvailableCapacityForImportantUsage` 判断），在安装前就提示。
- [ ] 验证：真机上从全新安装开始，完整走一遍"安装 → 启动 → 聊天 → 退到后台 1 分钟 → 回来继续聊天"，报告里附上耗时。

## 阶段 3：平台通道适配

- [ ] 审计 `原 Flutter 版 lib` 里创建 `MethodChannel` 的 30 个文件。其中 24 个已经处理了 `MissingPluginException`，剩下 6 个也要补上，保证 iOS 没有对应实现时不会崩。
- [ ] 每个通道先读 Dart 调用方和 Kotlin 实现，再写 Swift，方法名和数据格式保持一致。

| 通道 | iOS 处理 | 要点 |
|---|---|---|
| `dsh/runtime`（+ events） | **实现** | 阶段 2 |
| `dsh/app` | 实现 | `getTimeZoneId` → `TimeZone.current.identifier`；`bringToFront` 为空操作 |
| `dsh/voice`（+ events） | 实现 | 先读 `原 Flutter 版 lib/voice/` 确认流程；录音用 `AVAudioRecorder`，输出格式与 `WavRecorder.kt` 一致 |
| `dsh/notify`（+ taps / actions） | 实现 | `UNUserNotificationCenter`；实时活动用 ActivityKit，要新建 Widget Extension |
| `dsh/files` | 实现 | `open` → `QLPreviewController`；`pdfPage`/`pdfClose` → PDFKit；`saveToDownloads` → `UIDocumentPickerViewController` 导出；`resolveGuest` → 把 rootfs 内的路径映射成 iOS 文件路径 |
| `dsh/native-files`、`dsh/web-files` | 实现 | 文件选择用 `UIDocumentPickerViewController` |
| `dsh/media` | 实现 | `saveImage` → `PHPhotoLibrary`（仅添加）；`openSettings` 打开本 App 的设置页 |
| `dsh/links` | 实现 | 自定义 URL Scheme 和 Universal Links |
| `dsh/shortcuts` | 实现 | `setRecent` → 主屏图标长按菜单（`shortcutItems`） |
| `dsh/launcher_icon` | 实现 | `setAlternateIconName` |
| `dsh/performance`（+ events） | 实现 | `thermalState` + 低电量模式，转换成 Dart 侧已有的等级 |
| `dsh/diagnostics` | 实现 | 设备和版本信息；脱敏沿用 Dart 侧的 `diagnostics/redact.dart` |
| `dsh/share` | 实现 | 对外分享用 `share_plus`；从其他 App 分享进来要新建 Share Extension，通过 App Group 交给主 App |
| `dsh/native-media`（+ events）、`dsh/usage` | 先读调用方再决定 | 至少要返回"不支持"，不能报错 |
| `dsh/dynamic_color` | 返回 null | — |
| `dsh/update`、`dsh/pet_overlay`、`dsh/picture_shortcut`、`dsh/launch_clip`、`dsh/launch` | 不实现，入口隐藏 | 启动页用静态的 `LaunchScreen.storyboard` |
| `dsh/islands` | 不需要 | Dart 侧已经限定只在 Android 上用 |
| `dsh/phone`（+ events） | 不实现 | iOS 用阶段 4 的新通道 `dsh/phone_ios` |

- [ ] 设置页里不支持的入口统一由 `platform_caps.dart` 控制显示。
- [ ] 验证：在模拟器上逐个点开设置页的每个入口，没有报错，也没有空白页。

## 阶段 4：手机控制（系统框架档）

### 4.1 原理

```
iSH 内：dsh web --patch /opt/dsh-app/phone/phone.patch.yml
  └ @deepseek-ai/dsh-mcp-client（stdio）→ node relay.cjs → TCP 127.0.0.1:<随机端口>
        ⇅ App 内 loopback（每次启动随机 token）
App（Dart）：PhoneIosServer → McpServer → 安全检查 → MethodChannel('dsh/phone_ios')
App（Swift）：AlarmKit / EventKit / URL Scheme / MessageUI / 快捷指令 / 通知 / 剪贴板
```

- 挂载方式照搬 Android（`PhoneGuest.kt`）：每次启动引擎时，App 把 `relay.cjs`、`phone.patch.yml`、`bridge.json`（端口 + token，权限 0600）写进 rootfs，并在 `dsh web` 的启动参数里加上 `--patch`。插入位置的规则同 `PhoneGuest.launchArg`。使用说明追加到受管理的 `$DSH_HOME/AGENTS.md`，内容参照 `PhoneGuest.AGENTS_SECTION` 改写成 iOS 版。
- `relay.cjs` 参照 Android 版，但只用 TCP（Android 的 abstract socket 在 iOS 上不存在）。连接后第一行必须是带 token 的 hello，与 `PhoneBridge.kt` 一致；token 不对立即断开。iOS 上别的 App 也可能访问 loopback 端口，所以 token 是必需的。
- 开关手机控制会重启本地引擎，让覆盖层挂上或卸下，与 Android 的 `phone_state.dart` 行为一致。
- MCP 服务端写在 Dart 里（纯 Dart，可以单测），之后远程模式（阶段 6）也能复用；Swift 只负责执行动作。

### 4.2 固定工具清单（iOS 专用）

- 服务名仍为 `phone`，模型看到的是 `mcp__phone__<name>`。
- **清单必须固定**，不能随权限状态增减，理由见 `PhoneToolCatalog.kt` 头部注释（工具定义一变，DeepSeek 的缓存就失效）。暂时不能用的能力，返回一句模型能看懂的说明。
- 新建一个 Dart 测试，锁定清单 JSON 的哈希值。

| 工具 | 参数 | 实现 |
|---|---|---|
| `open` | `url`，或 `app`（内置一张"常用 App 名称 → URL Scheme"对照表） | `UIApplication.open`。iOS 无法列出已安装的 App，所以不提供 `apps` |
| `intent` | `kind` ∈ `alarm` `timer` `calendar` `reminder` `dial` `sms_draft` `share` `navigate` `settings`，其余字段与 Android 同名 | `alarm`/`timer` → AlarmKit（iOS 26+，低于 26 返回说明）；`calendar` → EventKit（仅写入）；`reminder` → EventKit 提醒事项；`dial` → `tel:`；`sms_draft` → `MFMessageComposeViewController`；`share` → `UIActivityViewController`；`navigate` → 高德 / 百度 / Apple 地图 URL（坐标用 GCJ-02，同 Android）；`settings` → 只能打开本 App 的设置页 |
| `notify` | `title`、`text` | 本地通知 |
| `clipboard` | `set` / `get` | `UIPasteboard`。读取时系统会弹提示；App 不在前台时读不到 |
| `shortcut` | `name`（省略时列出允许运行的快捷指令）、`input` | `shortcuts://x-callback-url/run-shortcut?name=…&input=text&text=…&x-success=<本App scheme>://…`，从回调里取结果（回调的参数格式要在真机上核实） |
| `handoff` | `reason` | App 内弹出提示，等用户点"继续"或"停止"，最长 10 分钟。iOS 上很多事只能让用户亲自做，这个工具会经常用到 |

### 4.3 任务

- [ ] **4.3.1 Dart 服务端**（新建 `原 Flutter 版 lib/phone_ios/`）：
  - `mcp_server.dart`：按行分隔的 JSON-RPC 2.0，支持 `initialize`、`ping`、`tools/list`、`tools/call`，其他方法返回 method not found。行为与 `McpServer.kt` 一致，包括 `server/discover` 退回 `initialize` 的兼容逻辑。等用户确认时，连接要能继续回应 `ping`。
  - `tool_catalog.dart`：4.2 的固定清单。
  - `safety.dart`：确认规则，见 4.3.4。
  - `phone_ios_server.dart`：在 `127.0.0.1` 的随机端口上监听，校验 token，把连接交给 `McpServer`。
- [ ] **4.3.2 挂载到本地引擎**：
  - 在 `dsh/runtime` 的 `start` 流程里写入 relay、覆盖层和 `bridge.json`，并注入 `--patch`。安全模式下不挂。
  - 为 relay 写 `node --test` 测试，放在 `runtime/tests/`。
- [ ] **4.3.3 Swift 执行层**（新建 `原 Flutter 版 ios/Runner/Phone/`）：
  - 实现 `MethodChannel('dsh/phone_ios')`，每个工具一个方法，另加 `capabilities` 方法返回各项权限的状态。
  - 权限按需申请：第一次用到日历时才弹日历权限。
- [ ] **4.3.4 确认与安全**：
  - 复用 Android 的三档确认模式（`ConfirmMode`：每次询问 / 本任务免确认 / 始终免确认）。
  - 不管哪一档，`dial`、`sms_draft`、`share`、`clipboard.get`，以及第一次运行某个快捷指令，**每次都要确认**。
  - `shortcut` 只能运行用户在设置里**手动加入白名单**的快捷指令。快捷指令几乎什么都能做，这是最重要的一道防线。
  - 确认界面复用 `原 Flutter 版 lib/phone/phone_approval.dart` 的样式。
- [ ] **4.3.5 跳转到其他 App 时**：`open`、`navigate`、`shortcut` 会把用户带到别的 App，DSH Go 随之进入后台，本地引擎也会被冻结（见 2.6）。处理方式：
  - 工具在跳转前就先返回结果，比如"已打开高德地图导航"。
  - 跳转时用 `beginBackgroundTask` 争取几秒，让结果送到引擎。
  - 用户回到 DSH Go 后，任务接着往下跑。
  - 工具描述里写清楚"调用后 App 会进入后台"，让模型把这类操作放在任务的最后一步。
- [ ] **4.3.6 设置页**（`ui/phone/` 下的 iOS 版）：
  - 内容：开关、确认档位、快捷指令白名单、各项权限状态。
  - 明确写出"iOS 不支持读屏和点击其他 App"。
- [ ] 验证：
  - `mcp_server.dart`、`safety.dart`、清单哈希的 `dart test`，relay 的 `node --test`。
  - 真机上用**本地引擎**依次测试："明早 7 点叫我起床""明天下午 3 点加个会议""提醒我周五交报告""导航去最近的星巴克""运行快捷指令 X"。每一步的确认弹窗和结果都要截图。
  - 关闭手机控制后，模型看不到任何 `mcp__phone__*` 工具。

## 阶段 5：Liquid Glass

背景：Flutter 自己绘制界面，用 Xcode 26 编译也不会自动变成 Liquid Glass。现有的玻璃效果全部集中在 `原 Flutter 版 lib/ui/theme/glass.dart`（`GlassSurface` / `GlassPill` / `GlassIconButton` / `GlassSegments`），这里是唯一需要改的地方。

**首批接入页面（用户可以调整）**：聊天顶栏（`ui/chat/chat_header.dart`）、输入条（`ui/chat/composer.dart`）、会话抽屉（`ui/shell/sessions_drawer.dart`）、模型选择弹层（`ui/chat/model_sheet.dart`）。

- [ ] **5.1 系统组件**：用 Xcode 26 SDK 编译后，分享面板、系统弹窗、键盘、文件选择器、`QLPreviewController` 会自动变成 Liquid Glass。能用系统组件的地方优先用系统组件。
- [ ] **5.2 技术验证（先交短报告）**：
  - 做法：在 `GlassSurface` 下面用 `UiKitView` 嵌入一个原生 `UIVisualEffectView`，使用 iOS 26 的玻璃效果（`UIGlassEffect`，具体 API 以 Xcode 26 SDK 为准），Flutter 的子组件叠在它上面。
  - 在真机上测这几项：滚动帧率（和现有的 `BackdropFilter` 对比）、页面转场和抽屉拖动时原生层是否错位、弹出键盘时输入条是否跟得上、打开"减少透明度"后是否退回不透明样式。
  - **注意本地引擎同时在占用 CPU**，帧率要在引擎运行时测。
- [ ] **5.3a 验证通过**：给 `GlassSurface` 加一个原生后端，只在 iOS 26+ 且页面显式开启时使用。同屏最多 3 块原生玻璃，与 `glass.dart` 现有的性能约定一致。
- [ ] **5.3b 验证不通过**：改走纯 Flutter 方案（着色器模拟，用第三方包的话先查许可证），或者调整现有 `BackdropFilter` 的参数，让观感接近 iOS 26。
- [ ] **5.4（可选）**：挑一个状态简单的页面（比如"关于"页），用 `UIHostingController` 整页做成 SwiftUI，验证这种方式是否可行。
- [ ] 验证：iOS 26 和 iOS 16–18 的截图并排对比；Android 端 golden 测试不变。

## 阶段 6：远程模式（可选，放在 2–5 之后）

- [ ] **6.1** SSH 主机（`原 Flutter 版 lib/remote/ssh/`）和 DSH Remote（`原 Flutter 版 dsh_remote`、`原 Flutter 版 lib/remote/relay/`）在 iOS 上跑通。局域网直连会弹"本地网络"权限，拒绝后要能自动走中继。
- [ ] **6.2** 回到前台后自动重连，补齐消息。
- [ ] **6.3（可选）远程时的手机控制**：只支持 SSH 主机。通过 SSH 反向端口转发（先确认 `dartssh2` 的 `forwardRemote` 能用），把远程 `dsh web` 的 relay 接回手机上的 `phone_ios_server.dart`。覆盖层文件写到远程的 `~/.cache/dsh-go/phone/`，不要改远程用户的 `~/.dsh/AGENTS.md`，使用说明放在 MCP `initialize` 的 `instructions` 字段里。DSH Remote 主机不支持手机控制：它的 Host 插件有固定白名单（`tunnel_carrier.dart` 的 `harnessRemoteAllowlist`），界面要显示原因。
- [ ] 验证：`(cd 原 Flutter 版 dsh_client && dart test)`、`(cd 原 Flutter 版 dsh_remote && dart test)`；真机上两种远程方式各完成一次对话。

## 阶段 7：发布准备

- [ ] 隐私清单 `PrivacyInfo.xcprivacy`，如实声明匿名统计默认开启。
- [ ] 新建 `tooling/build-ipa.sh`（参照 `tooling/build-apk.sh` 的版本号规则），新增 CI 的 macOS job：`flutter build ios --no-codesign` 和 Dart 测试。
- [ ] `THIRD_PARTY_NOTICES.md` 补上 ish-arm64、OpenMinis 参考代码、Alpine 软件包（如果用了方案 B）的许可证。
- [ ] **交给用户决定**（Codex 只在报告里列出）：
  - **审核风险**：App 在本地运行 Linux，还会通过 pnpm 下载插件来执行，可能触及审核指南 2.5.2。iSH 和 OpenMinis 都已上架，有先例；但提交审核时要准备说明材料，比如在审核备注里讲清楚这是用户自己发起的开发和自动化工具。
  - 名称、Logo、吉祥物不在开源许可内（见 `THIRD_PARTY_NOTICES.md` 的「品牌与吉祥物素材」），需要替换或取得授权。
  - AGPL 和 App Store 条款是否兼容。
  - 原仓库不接受外部 PR（见 `AGENTS.md`），iOS 版要在你自己的 fork 或独立仓库里维护。

---

## 执行顺序

1 → **2.1 技术验证（结果交给用户）** → 2.2–2.7 → 3 → 4 → 5 → 6 → 7。

- 2.1 的报告出来之前，不要开始 2.2 以后的工作。
- 阶段 4 依赖阶段 2 的本地引擎，所以必须等 2 完成。
- 阶段 5 可以和阶段 4 并行，但 5.2 的验证报告出来之前不要动 `glass.dart`。
- 阶段 6 可以随时插队，但不能占用 2–4 的优先级。

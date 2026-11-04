# iOS 原生版：持续开发任务清单

> 交接给 Codex 的工作说明（2026-11-03）。按「任务队列」从上到下逐项做，每项做完即提交推送，不需要停下来问。
> 只有需要 API Key、Apple ID 签名、真机时才停下来问。
> 全部完成后，由用户安排另一位评审（Claude）评估是否成功交付：iOS 版功能完善，并且完全独立于 Flutter。

## 1. 背景

- 产品：**DSH Fan**，独立的 iOS 原生项目（SwiftUI），代码在 `apple/`，仓库 https://github.com/fanofacane/dsh-fan 。参考实现 DSH Go 的 Flutter / 安卓源码见上游 DSH Go 仓库。
- 本机模式：DSH 引擎 `dsh web` 跑在 App 内置的 iSH（x86 模拟 → arm64 改造版）+ Alpine + Node 24 里，监听 `127.0.0.1:3080`。
- 远程模式：通过 SSH 或 DSH Remote 中继，连接电脑 / 服务器上的 `dsh web`。
- 功能对照表：`docs/design/ios-native-parity.md`。做完一项就更新那张表。

## 2. 硬规则

1. **独立的 iOS 源码与资源**：`apple/` 与工程生成器不依赖已删除的旧客户端目录。资源放 `apple/Resources/`；Flutter 版已删除，参考实现可在 上游 DSH Go 仓库 查看，不复制 Dart 生成物。
2. **工程文件是生成物**：不要手改 `apple/DSH.xcodeproj`。改生成器后运行 `ruby tooling/generate-apple-project.rb`。`App/` 按 Core、Design、Features、Debug 分层，生成器递归收录 App 子目录中的 Swift / 文案；新建功能目录无需再改目录清单。模块源码仍放对应 `Modules/*`，测试放 `Tests/`，不改变模块依赖方向。
3. **图标**：`DshIcons.ttf` 是固定的 Phosphor 子集，`App/Design/Glyphs.swift` 里有的才能用。新图标一律用 SF Symbols。
4. **文案**：界面文案用英文 key，并在 `apple/App/Localizable.xcstrings` 补 `zh-Hans`。小组件、分享扩展各有自己的 `Localizable.xcstrings`；权限说明在 `apple/App/InfoPlist.xcstrings`。xcstrings 的 key 按字母排序，用 `json.dumps(..., ensure_ascii=False, indent=2)` 写回，保持 diff 只有新增。
5. **设计**：沿用雾蓝玻璃风格，组件在 `App/Design/Theme.swift`（`DS` 固定颜色、Environment 中的 `DesignTheme`（配色 / 阅读字号）、`Radius`、`Space`、`.type()`、`.glass()`、`GlassIconButton`、`Mono.font`；正文代码字体传 `scale: theme.readingScale`）和 `App/Design/SettingsKit.swift`（`SettingsPage`、`SettingsGroup`、`SettingsRow`、`SettingsLink`、`SettingsToggleRow`、`MistButton`）。名字、账号这类原文用 `SettingsRow(verbatim:)` 或 `Text(verbatim:)`，避免被当成 Markdown。
6. **远程兼容**：新功能调用的 DSH 接口要在 `apple/Modules/DSHRemote/Relay/RemoteTunnelCarrier.swift` 的 `allowlist` 里，中继连接才可用。只有本机才有的 HTTP 桥接口（`/dsh-fan/v1/*`，比如删除会话），遇到 `carrier != nil` 时要给出明确的「不支持」提示。
7. **凭据**：任何 API Key、令牌、Cookie、密码都不得写进代码、日志、提交或文件。提交前运行 `git diff --cached | grep -E "sk-[A-Za-z0-9]{16,}"`，确认没有输出。
8. **旧端移除（2026-11-04 用户授权）**：Flutter / 安卓客户端及专用工具已按阶段 3 删除。历史源码在 上游 DSH Go 仓库，不重新引入旧端依赖；保留 SDK 与插件示例。
9. **不做依赖原作者服务的功能**：社区 / 论坛、Star 引导、托管分享链接、分享码、DS Bot、DSH Remote 托管服务器（`dsh.r2049.cn`）等任何原作者服务，一律不做，也不要留入口。中继只支持用户自建的 ds-harness-remote 服务器。
11. **App Store 合规（2026-11-04）**：App 不得下载、安装或更新可执行代码（审核指南 2.5.2）。不做插件安装 / 插件市场 / 包管理入口；引擎的插件管理器由 `RuntimeEngine.storePatch`（`/opt/dsh-app/ios-store.patch.yml`）在每次启动时禁用，不要移除。`-dsh-feature-smoke store` 检查它仍然关闭。新增系统接口时同步更新 `apple/App/PrivacyInfo.xcprivacy`。
10. **提交**：每完成一项就提交并推送到当前分支 `ios/phase1-spike`。`git add` 只写明确的路径（不要 `git add .` / `-A`），不要提交 `.DS_Store`，也不要提交 `docs/design/ios-native-migration.md`。提交信息用中文，说明做了什么、怎么验证的。不创建 PR。

## 3. 代码结构速览

| 位置 | 内容 |
|---|---|
| `apple/Modules/DSHRuntime/`（含 Native 桥） | iSH 内核、引擎安装 / 启动 / 停止 / 重置、日志（`RuntimeEngine.swift`）。每次启动前都会清理残留的写锁，安全模式会复制 web 配置（见那里的注释） |
| `apple/Modules/DSHClient/` | DSH 协议客户端：WorkspaceAPI / ScheduleAPI / AgentAPI / ProviderAPI / AccountAPI / SettingsAPI / FilesAPI，另有 ControlAPI / CommandsAPI / CredentialsAPI；类型化记录与流在模块内解析。DSHClient 保留会话、HTTP / mux 等传输能力，App 不直接拼 RPC。JSONValue 仅用于工具 JSON、资源清单和诊断，schema 表单的动态值保留字典 |
| `apple/Modules/DSHRemote/` | SSH（swift-nio-ssh）与 `Relay/`（DSH Remote：Noise IK、中继传输、账号、隧道载体） |
| `apple/Modules/DSHPhone/` | 手机控制 MCP 服务与回环桥 |
| `apple/App/Core/` | DSHApp / RootView、AppComposition / AppSession 依赖组装与主机重置、四个可测试边界协议、AppPreferences、EngineModel 与外观注入 |
| `apple/App/Design/` | 雾蓝主题、字形、设置页基础组件 |
| `apple/App/Features/Chat/` | Connection / Transcript / SessionList / Control / HostRequest Store、ChatView、消息行、Markdown 与输入 |
| `apple/App/Features/Settings/` | 设置首页、schema 表单、引擎界面与引导 |
| `apple/App/Features/Workspace/` | 工作区、文件浏览、改动预览 |
| `apple/App/Features/Schedule/`、`Agents/` | 定时任务、Agent 预设与子任务 |
| `apple/App/Features/Account/`、`Providers/` | 本机账号授权与模型服务商 |
| `apple/App/Features/Remote/` | SSH / 自建中继主机、账号、切换与重连 |
| `apple/App/Features/Phone/`、`Pet/` | 手机公开系统操作、确认与宠物 |
| `apple/App/Features/Notifications/`、`Ecosystem/` | 本地通知、后台说明、Intents 与实时活动桥接 |
| `apple/App/Debug/` | 五组 Smoke 文件，全部由 #if DEBUG 包围 |
| `apple/Tests/` | DSHTests 的正式 Swift Testing 测试 |
| `apple/Extensions/Widgets/`、`apple/Extensions/Share/`、`apple/Extensions/Shared/` | 小组件 / 控制中心 / 实时活动、分享扩展、共享类型 |

协议参考：Dart 客户端 `Flutter 版已删除，可在 上游 DSH Go 仓库 查看（dsh_client/lib/src/）`，里面有每个接口的参数和返回格式，是移植时最准确的来源。

## 4. 构建与验证

默认测试设备为 `SIM=51831DA4-9348-4053-A81C-54B3C995A73A`（iPhone 18 Pro）。所有模拟器命令都必须显式使用这个设备 ID，不使用 `booted` 别名。

**不要同时运行两个装了 DSH 的模拟器，所有模拟器共用 Mac 的 `127.0.0.1:3080`。** WOO UI Review 不是本项目的设备，不要在上面安装或运行 DSH，也不要关闭那台模拟器。

```bash
# 固定设备；所有 simctl / xcodebuild 命令复用它
SIM=51831DA4-9348-4053-A81C-54B3C995A73A

# 依赖（只需一次）：ish.xcframework 与 iOS 运行时
bash tooling/build-ish.sh
bash runtime/build-ios-runtime.sh

# 生成工程并构建（模拟器）
ruby tooling/generate-apple-project.rb
xcodebuild -project apple/DSH.xcodeproj -scheme DSH \
  -destination "platform=iOS Simulator,id=$SIM" build

# Release（上架用的配置）也必须能编过：#if DEBUG 里的代码在这里不存在。
# 每次提交前都跑；协议要求、调用方若只在 Debug 有实现，也要包进 #if DEBUG。
xcodebuild -project apple/DSH.xcodeproj -scheme DSH -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

# 只看错误
... 2>&1 | grep -E "^/.*(error|warning):|BUILD (SUCC|FAIL)" | grep -v SourcePackages

# 正式 Swift Testing：八组客户端契约、App 状态和领域接口
# 先结束 DSH，避免复用仍在运行的测试宿主。
xcrun simctl terminate "$SIM" io.github.fanofacane.dsh
xcodebuild -project apple/DSH.xcodeproj -scheme DSH \
  -destination "platform=iOS Simulator,id=$SIM" \
  -parallel-testing-enabled NO test

# 安装、启动、截图
xcrun simctl install "$SIM" <DerivedData>/Build/Products/Debug-iphonesimulator/DSH.app
xcrun simctl launch --terminate-running-process "$SIM" io.github.fanofacane.dsh [参数]
xcrun simctl io "$SIM" screenshot /tmp/shot.png

# 运行时测试
node --test runtime/tests/*.test.mjs
```

`DSHTests` 位于 `apple/Tests/`，原八组独立 Swift 脚本已迁入，使用 `import Testing`，分别以 `@testable import DSHClient` 和 `@testable import DSH` 检查协议与 App 状态。测试宿主根据 `ProcessInfo` 环境变量中是否存在 `XCTestConfigurationFilePath` 判断，不依赖 scheme 参数一定送达；DEBUG 继续兼容 `-dsh-unit-tests`。宿主显示空白页面，跳过 `engine.prepareOnLaunch()` 和自动连接，避免测试结束时杀掉仍在启动的 iSH。正式测试可以显式调用假依赖，不启动真实引擎；普通启动与冒烟保持原行为。禁止并行克隆测试设备，继续固定上述 SIM。

**已接受的保留基线（2026-11-04）**

用户 / Claude 已在阶段 3 之前的 `3f941d9` 复现下表；阶段 3 工作区逐项比较结果一致。这些既有问题保留、不修，不再因此暂停。后续验收要求**不新增失败**：逐项比较失败 / 取消 / 跳过的测试名，不能只比较总数。名字与状态保存在 [ios-test-baselines.json](../testing/ios-test-baselines.json)。新引入的失败仍需处理；其他不在本次改动里的失败按用户的暂停规则汇报。

| 测试组与根目录命令 | 已接受结果 | 原因 |
|---|---|---|
| `node --test runtime/tests/*.test.mjs` | 209 PASS / 10 FAIL / 5 CANCELLED | 8 项缺少 DSH_PREFIX / 引擎候选依赖，2 项媒体 HTTP 响应断言在本机失败，5 项 Promise 等待时事件循环结束而取消 |
| `node --test runtime/media/dsh-media/test/*.test.js` | 168 PASS / 19 FAIL | 媒体包未装 node_modules，缺少 @deepseek-ai/schemastery、dsh-atomic-write 等依赖；保存、权限、清理测试有特定平台 / 临时路径假设 |

其余非通过项仍逐项核对名称和状态。插件开发包 sdk/ 已于 2026-11-05 删除，不再有 SDK 测试组。

其中 FAIL / CANCELLED / SKIPPED 都不记为通过。新迁移的媒体头部夹具单独运行 `node --test runtime/media/dsh-media/test/header.test.js`，120 项必须全过；iOS 的正式测试与通用冒烟仍须全部 PASS。

DEBUG 启动参数：

运行 `-dsh-feature-smoke t4` 前，先在另一个终端启动模型发现夹具，保持运行到测试结束（只监听 `127.0.0.1:38911`，无需凭据）：

```bash
python3 tooling/apple-models-fixture.py
```

统一冒烟脚本固定使用上述 `SIM`，launch 使用 `--terminate-running-process` 并每次带 `-dsh-dump-log`；启动后用 `ps` 核对设备及参数，t4 前确认 38911 模型夹具可连接。只有启动阶段失败且尚未进入用例时，先保存该次 `Documents/engine-log.txt` 到本机临时目录，再以相同参数重跑一次；第二次仍失败才暂停，重跑通过则继续并在汇报中附人工检查后的失败日志尾部。用例自身 FAIL 不因此重试或跳过，仍须等待最终 result：

```bash
caffeinate -i python3 tooling/apple-smoke.py   # 九项通用冒烟；命令结束后释放防空闲休眠
python3 tooling/apple-smoke.py t13 chat menu   # 指定用例
```

读取冒烟 JSON 时，必须等到存在 `result` 字段且值不为 `RUNNING` 才算完成；chat / menu 文件会逐步写入，中间结果不代表通过。

- 冒烟测试：结果写在 App 容器的 `Documents/*.json`，容器路径用 `xcrun simctl get_app_container "$SIM" io.github.fanofacane.dsh data` 查。

  | 参数 | 测什么 |
  |---|---|
  | `-dsh-smoke` | 引擎安装 / 启动 / 停止 |
  | `-dsh-chat-smoke` | 对话 |
  | `-dsh-menu-smoke` | 消息菜单：分叉、重答、编辑 |
  | `-dsh-phone-smoke` | 手机控制 |
  | `-dsh-remote-smoke` | 远程连接，配合下面的环境变量 |

- `-dsh-remote-smoke` 的环境变量：
  - SSH：`SIMCTL_CHILD_DSH_SSH_TARGET=user@host:port`，再加 `SIMCTL_CHILD_DSH_SSH_PASSWORD` 或 `SIMCTL_CHILD_DSH_SSH_KEYFILE`
  - 中继：`SIMCTL_CHILD_DSH_RELAY_SERVER`、`SIMCTL_CHILD_DSH_RELAY_EMAIL`、`SIMCTL_CHILD_DSH_RELAY_PASSWORD`
- `-dsh-dump-log`：每 5 秒把引擎日志尾部写到 `Documents/engine-log.txt`（令牌已脱敏）。引擎出错时先开它看日志。
- `-dsh-screen <名字>`：直接打开某个页面截图。可选：`chat`、`drawer`、`settings`、`model`、`permissions`、`phone`、`pet`、`about`、`engine`、`key`、`remote`、`welcome`、`setup` 等。新页面注册到 `DebugPageRegistry`。连接就绪后写入 `Documents/screen-ready.txt`（仅页面名）；对聊天等页面截图应等此标记，避免截到模型加载前的临时 Key 设置卡。

**测试用远程主机（Docker，可能还在运行）**

- `dsh-ssh-test`：端口 2222，用户 `dev`，密码 `devpass`，镜像 `dsh-ssh-test`，里面有 sshd 和 dsh 0.2.1。
- `dsh-relay-test`：端口 8790，上游 `apps/server` + 一台装了远程插件的 Host，账号 `e2e-owner@example.test`。
  - 密码每次启动时随机生成。不在运行时需要重建，参考 `Flutter 版已删除，可在 上游 DSH Go 仓库 查看（dsh_remote/tool/e2e/run_e2e.sh）`。

**既有测试数据限制（2026-11-04）**：这台模拟器早先安装过 T16 插件，`profiles/web` 残留 `.plugin-manager`、`node_modules`、`pnpm-lock.yaml`。因此 chat 冒烟可能记录 `deleted=false`、`deleteError=E_DELETE_UNSUPPORTED`；用户 / Claude 已确认全新模拟器删除正常，此现象不影响 chat 的 PASS 判定，不改删除代码来迁就旧数据。

**模拟器的模型 Key**：本机引擎的凭据库里已经存了测试用 DeepSeek Key，冒烟测试会直接用。如果 Key 丢了，停下来问用户，不要去别处找。

**每项任务的完成标准**

1. 构建通过，没有新的警告。
2. 有对应的冒烟测试，或者截图核对过，用真实模型跑的要说明。
3. 新增文案都有中文。
4. 更新 `docs/design/ios-native-parity.md`。
5. 提交并推送。

## 5. 任务队列（按顺序）

工作量：S ≤ 1 天，M 2–4 天，L ≥ 1 周。「参考」指 Flutter 里的对应实现。

### T1 待办 / 目标条（M）
- 输入框上方显示当前会话的待办（todos）和目标（goal）。参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/chat/dock/）`、`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/state/goal_dock_state.dart）`。
- 数据：
  - `session/control` 流：先发 `{type: baseline, value: {projections: {sessionId: {asOfSeq, values}}}}`，之后逐条发 `{sessionId, key, value, seq}`。
  - 待办是 `values.todos`，每条 `{content, status: pending|in_progress|completed}`。
  - 目标是 `values.goal`，结构 `{goal: {id, revision, objective, phase, maxGoalRounds, blockedReason}, roundsStarted}`。
  - 实现：在 `MuxConnection` 上开一个长期流，或者在 `ChatModel` 里按会话折叠。
- 目标操作：`goals/pause|resume|clear|edit|complete`，参数里带当前 `{id, revision}` 做比较后写入，参考 `Flutter 版已删除，可在 上游 DSH Go 仓库 查看（dsh_client/lib/src/goals_api.dart）`。
- 验收：让模型列一份待办（比如「分三步做…，用 todo 工具记录」），条上的进度要实时变；目标可以暂停 / 继续 / 清除。

### T2 @ 文件提及 + 斜杠命令面板（M）
- 输入 `@` 弹出文件候选，用 `fileReferences/list`。输入 `/` 弹出命令面板，用 `commands/list`，执行用 `commands/execute`，例如 `ChatModel` 里已有的 `/permission`。
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/chat/mention/）`、`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/chat/slash_palette.dart）`。
- 发送时提及的格式以 Dart 客户端为准，看 `prompt` 的 attachments / references。

### T3 消息菜单补全（S）
- 引用（把选中消息以引用格式放进输入框）、分享（`ShareLink`）、消息里的图片保存到相册。
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/chat/widgets/message_menu.dart）`。

### T4 其他模型服务商（M）
- 设置 → 模型服务商：列表、添加 OpenAI 兼容 / 自定义、填 Key、拉取模型。
- 接口：`llm/listConfigurableProviders`、`llm/listProviders`、`llm/discoverModels`、`credentials/set|unset|describe`、`settings/*`。
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/providers/）`。
- 新增服务商后，模型选择器（`ChatView` 的模型胶囊）里要能看到它的模型。

### T5 DeepSeek 账号登录（M）
- 用 DeepSeek 官方账号登录后，不填 API Key 也能用 `deepseek-account` 路由；同时显示余额。手填 Key 继续保留。
- 流程（由引擎负责 PKCE 和换取凭据）：
  1. 调 `account/startSignIn`，`callbackOrigin` 填 `http://127.0.0.1:3080`。
  2. 订阅 `account/watch` 流，状态依次是 `waiting-browser(authorizeUrl)` → `exchanging` → `succeeded`。
  3. 拿到 `authorizeUrl` 后用浏览器打开，用户在 platform.deepseek.com 授权，再回跳到 `127.0.0.1:3080/oauth/callback`。
- 账号余额：`account/getBalance`（用户于 2026-11-03 确认，授权保留在引擎）；公有 `GET https://api.deepseek.com/user/balance` 是 API Key 余额接口，本任务不导出账号授权来调用它。充值链接是 `https://platform.deepseek.com/top_up`。
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/state/account_state.dart）`、`account_api.dart`、`balance_state.dart`、`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/account/）`。
- 只支持本机引擎：`account/*` 不在中继白名单里，远程主机上要隐藏或提示。
- 回跳要回到 App 内置引擎的回环地址。可以先试 `ASWebAuthenticationSession`；如果回跳到 127.0.0.1 不行，就在应用内打开 `SFSafariViewController`，再轮询 `account/watch`。

### T6 联网搜索、图像 / 视频生成设置（S–M）
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/settings/search/）`、`media/`、`media_settings_page.dart`。接口：`settings/describe|update`。

### T7 工作区（M）
- 新对话可以选工作目录（现在固定在 `/root/work`），有工作区列表，会话列表可按工作区分组。
- 接口：`workspace/follow|create|rename|delete`、`directoryPicker/list`、`session/create` 的 `cwd`。
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/workspace/）`。远程 SSH 主机已有 `HostStore.sessionDirectory`，两者要合并。

### T8 文件浏览、产物预览、改动对比（M）
- 浏览工作区文件，预览 PDF / Office / 网页 / 图片（QuickLook 或 WKWebView），查看本轮改动的 diff。
- 接口：`workspaceFiles/list|stat|read|readBytes|changes`、`officeToPdf/render`。
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/files/）`、`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/chat/artifact_preview.dart）`、`diff_page.dart`。

### T9 终端（M）
- **本轮决定（2026-11-03）**：用户确认暂缓，记录原因后继续 T10。捆绑引擎 0.2.1-rc.4 已改用 `terminal/attach` 双向流，下列旧 write / resize / follow 接口不再提供；现有中继载体也不支持流上行。未加入 SwiftTerm 或保留不可用终端入口。
- 接口：`terminal/create|write|resize|follow|close|list|shells|environment`。终端渲染可以用 SwiftTerm（SPM，MIT），在生成器里像 swift-nio-ssh 那样加包引用。
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/terminal/）`。

### T10 子代理 / Agent 预设（M）
- **协议确认（2026-11-03）**：用户确认以 `session/control` 的 `subagentCatalog` 投影枚举子任务；捆绑引擎已移除 `subagents/list`。此次确认仅适用于 T10，后续接口冲突仍需逐项确认。
- 子代理调用要显示成可展开的子任务（`subagents/list|prompt|interruptByParent`），并支持选择 Agent 预设（`agentPresets/list|read|select`）。
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/agents/）`。

### T11 会话归档、置顶（S）
- 接口：`workspace/archiveSession|unarchiveSession|pinSession|unpinSession`。侧栏增加置顶区和「已归档」。

### T12 用量、轨迹、运行信息（M）
- 投影里的 `tokenUsage`、`contextPressure`、`turnOutline` 等。
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/chat/usage_sheet.dart）`、`trajectory_sheet.dart`、`run_info.dart`。

### T13 定时任务（M）
- 接口：`schedule/list|catalog|history|update|delete`。
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/chat/header_schedule.dart）`。

### T14 任务完成通知、后台说明（S）
- 回复完成或需要批准时，如果 App 不在前台，就发本地通知（UserNotifications）。另外加一页设置说明 iOS 的后台限制：App 在后台约 30 秒后会被挂起。

### T15 设置页补全（S–M）
- 个性化（回复偏好）、界面（字号、外观、配色）、隐私、诊断（导出日志）、语言。
- 参考：`Flutter 版已删除，可在 上游 DSH Go 仓库 查看（lib/ui/settings/）` 里的对应页面。只做在 iOS 上有意义的项。

### T16 插件与插件市场 —— 已取消（2026-11-04）
- 用户决定为上架 App Store 移除。插件安装会在引擎内用 pnpm 下载并执行外部代码，违反审核指南 2.5.2。见硬规则 11。
- 未提交的 T16 草稿（`PluginSettings.swift`、`Plugins.swift`、`apple-plugin-fixture.py`、`apple-plugin-tests.swift` 等）不要再提交。
- **以后的插件方案（用户 2026-11-04 选定方案 A）**：插件随 App 一起打包（放进内置引擎、随版本过审），由用户自己的后台决定对谁开放；App 根据后台开关在启动补丁里启用 / 停用对应的插件行。不从网络下载或安装插件，不做市场 / 搜索界面。上架提审时在审核备注里列出这些插件和开关。后台接口尚未设计，做之前先问用户。

### T17 WebRTC 直连（可选，L）—— 暂缓
- 评估结论：iOS arm64 框架约 12.0 MiB。中继只剩自建服务器一种用法，收益有限，暂不引入。
- 远程连接现在只走中继。直连需要 libwebrtc（约 10 MB），先评估体积再决定，参考 `Flutter 版已删除，可在 上游 DSH Go 仓库 查看（dsh_remote/lib/src/transport/webrtc_transport.dart）`。

### 架构重构（T18–T23，2026-11-04 用户确认）

**为什么要做**（基于 2026-11-04 的架构评估）：`apple/Modules` 下 4 个框架分层干净（依赖只朝下、`DSHCarrier` 是策略、`HostStore.makeClient` 是工厂），保持不动。问题集中在 App 层（约 1 万行）：

- `ChatModel` 791 行、65 个方法，什么都管；
- 视图直接 `chat.api("…", [...])`，全项目约 390 处 `[String: Any]`；
- 10 个 `.shared` 单例被到处直接调用；
- 只有 2 个协议；
- 设置入口、工具卡片、调试页、冒烟测试都是写死的 `switch`；
- `App/` 根目录是平的；
- 没有正式测试目标。

**通用规则**（每一项都适用）：

- 渐进重构，**不改用户可见行为**，不顺手加功能。
- 每项单独提交。每项完成后必须：
  - 构建无错误无警告；
  - 测试目标全部通过；
  - 冒烟测试全部 PASS：`store`、t1、t4（先启动 `tooling/apple-models-fixture.py`）、t7、t10、t13、t15、`-dsh-chat-smoke`、`-dsh-menu-smoke`。
- 公开 API 改名时一次改全，不留兼容层。不引入第三方依赖。
- 设计原则：会变化的地方用协议抽象，会增长的地方用注册表。不为了「用上设计模式」而加抽象。只有一个实现、也看不到第二个实现的东西，不建协议。

#### T18 正式测试目标（M）

**已完成（2026-11-04）**：正式目标 8 suite / 8 test 全 PASS，九项通用冒烟全 PASS，原八组断言完整保留。

- 在生成器里新增单元测试目标 `DSHTests`，用 Swift Testing（`import Testing`）。挂在 scheme 上，`xcodebuild test` 能跑。
- 把 `tooling/tests/apple-*-tests.swift` 的 8 组断言迁进去，删掉原脚本。
- 生成器里的模块要让测试目标能 `@testable import`。
- 验收：
  - `xcodebuild -project apple/DSH.xcodeproj -scheme DSH -destination "platform=iOS Simulator,id=$SIM" -parallel-testing-enabled NO test` 通过；
  - 8 组断言都在；
  - 文档第 4 节写明测试命令。

#### T19 按功能分目录（M）

**已完成（2026-11-04）**：42 个 Swift 文件用 git mv 移至 Core / Features / Debug，全部 45 个 App Swift 文件内容哈希不变。生成器递归收录子目录，连续生成工程无 diff；构建零错误零警告，正式测试 8/8 PASS，指定 SIM 九项通用冒烟全 PASS。

- 目标结构：
  ```
  App/Core/                     DSHApp、RootView、导航、组装、AppPreferences、通用状态
  App/Design/                   不变
  App/Features/Chat/            原 App/Chat、ChatView、ChatModel、MarkdownView
  App/Features/Settings/        SettingsView、EngineSettingsViews、EngineView、引导
  App/Features/Workspace/       含文件浏览
  App/Features/Schedule/
  App/Features/Agents/
  App/Features/Account/
  App/Features/Providers/
  App/Features/Remote/
  App/Features/Phone/
  App/Features/Pet/
  App/Features/Notifications/
  App/Features/Ecosystem/       实时活动、Intents、小组件桥接
  App/Debug/                    所有 *Smoke.swift、调试页，整体 #if DEBUG
  ```
- 生成器改为递归收录 `App/` 下的子目录，以后新建功能目录不用再改生成器。
- 这一项只移动文件，不改代码逻辑。用 `git mv` 移动，保留文件历史。
- 验收：
  - 构建通过；
  - 连续生成两次工程，无 diff；
  - 更新第 3 节「代码结构速览」。

#### T20 依赖注入，收敛单例（M–L）

**已完成（2026-11-04）**：Core 统一组装依赖，四个边界协议支持替换，功能通过初始化参数 / Environment 获取状态；配色和阅读字号作为值注入。`.shared` 由 95 处收敛到 7 处，仅 Core 组装和注明原因的 App Intent 系统入口。构建零错误零警告，正式测试 9/9 PASS（含假运行时 / 手机生命周期），指定 SIM 九项通用冒烟全 PASS。启动参数缺失曾触发暂停，获用户授权后使用 terminate-running-process 重跑剩余四项，ps 与最终 result 均通过。

- 给需要替换或测试的依赖定义协议，例如：
  - `EngineControlling`（`RuntimeEngine` 的启动、状态、回复偏好）；
  - `HostProviding`（`HostStore` 的当前主机、`makeClient`）；
  - `TaskNotifying`（`TaskNotifications`）；
  - `PhoneControlling`（`PhoneController` 中聊天层会用到的部分）。
- 组装只在 `App/Core` 里做。各功能通过初始化参数或 SwiftUI `Environment` 拿依赖。
- `.shared` 只允许出现在 `App/Core` 的组装代码，以及系统回调入口（App Intents、通知代理），并加注释说明原因。
- 验收：
  - `git grep -n "\.shared" apple/App` 的结果只在上述位置；
  - 至少给 1 个 Store 写用假依赖的单元测试，证明可以注入。

#### T21 有类型的接口层（L）

**已完成（2026-11-04）**：七个领域 API 与控制 / 命令 / 凭据接口在 DSHClient 内解析类型化记录与流，已有解析文件并入对应 API。App 原始 api 调用 61→0；动态字典仅剩 schema 表单的 33 处，逐处注明原因。构建零错误零警告，正式测试 21/21 PASS（含解析 / 参数 / 错误码 / 本机门控 / 流取消 / 资源数值），九项通用冒烟全 PASS，重复生成工程无 diff。正式测试首次宿主无参数未建立连接，用户授权退出目标 DSH 后重跑通过。

- 在 `Modules/DSHClient` 里按领域建接口，用 `Codable` 或明确的结构体代替 `[String: Any]`：
  - `WorkspaceAPI`、`ScheduleAPI`、`AgentAPI`、`ProviderAPI`、`AccountAPI`、`SettingsAPI`、`FilesAPI`；
  - 已有的 `SessionControl`、`Schedules`、`Workspaces` 等解析代码并进去。
- 方法名和参数照搬引擎协议，错误统一用 `DSHError`。
- 引擎 schema 本身就是动态的（`settings/describe` 的表单值），这类数据可以保留 `[String: Any]`，在类型注释里说明原因。
- 验收：
  - `git grep -n 'api("' apple/App` 为空，视图不再直接发 RPC；
  - `apple/App` 里的 `[String: Any]` 只剩引擎 schema 表单相关的代码，每处都有注释说明；
  - 新接口的解析都有单元测试。

#### T22 拆分 ChatModel（L）

**已完成（2026-11-04）**：原 ChatModel 787 行改为 85 行 Core/AppSession 协调器，业务分别进入八个可观察 Store；新增 Store 和扩展均不超过 165 行。跨 Store 由 Core 接线，保留 generation / epoch、权限失败采用会话及权限读取时序。构建零错误零警告，正式测试 32/32 PASS（八个 Store 均用假 client 验证，含迟到连接和权限时序），指定 SIM 九项通用冒烟全 PASS，重复生成工程无 diff。

- 按职责拆成独立的 `@Observable` Store：
  - `ConnectionStore`：连接、重连、generation；
  - `TranscriptStore`：当前会话、follow 流、发送、重试、分叉；
  - `SessionListStore`：列表、置顶、归档、重命名、删除；
  - `WorkspaceStore`、`ScheduleStore`、`AgentStore`、`ControlStore`（todo、goal、投影）、`HostRequestStore`（批准、提问）。
- `ChatModel` 改名为 `AppSession`（或类似名字），只负责协调：持有各个 Store、在切换主机时统一重置。业务逻辑不留在里面。
- 各 Store 只依赖 T20 的协议和 T21 的接口。
- 验收：
  - 每个文件不超过约 300 行；
  - 原有行为不变（冒烟测试全过）；
  - 每个 Store 至少有 1 个单元测试（用假 client）。

#### T23 扩展点注册表（M）

**已完成（2026-11-04）**：SettingsEntry / SettingsRegistry、工具族 ToolPresenter、DEBUG 页面及 15 个 feature 冒烟用例完成注册；原顺序、本机限制、摘要、参数名与逐步结果保持不变。PluginDescriptor / PluginGate 仅提供生产本地全关闭实现，空可选目录不改变既有服务；补丁保护插件管理器两行永久禁用，未接后台或添加插件界面。构建零错误零警告，正式测试 39/39 PASS、0 跳过，指定 SIM 九项通用冒烟全 PASS，重复生成工程无 diff，中文设置页截图核对。新增模块步骤已写架构文档。

把写死的 `switch` 和列表改成注册表，加一个功能只需要新增文件加一行注册：

- **设置入口**：`SettingsEntry`（标题、图标、分组、排序、是否只在本机可用、目标页面）。`SettingsView` 按注册表渲染。
- **工具卡片**：`ToolPresenter` 策略，每种工具（bash、文件编辑、手机控制、搜索……）一个实现，负责标签、图标、摘要。`ChatRows` 里不再有按工具名分支的 `switch`。
- **调试**：`-dsh-screen` 的页面和 `-dsh-feature-smoke` 的用例改成注册表（只在 DEBUG 下编译）。
- **为方案 A 预留插件描述**：`PluginDescriptor`（id、引擎插件行 id、标题、设置入口、默认关闭）加上 `PluginGate` 协议（决定是否启用）。
  - 现阶段只提供本地实现：全部关闭。不接后台，也不做界面；后台接口要先问用户。
  - 启用的插件，在启动补丁里把对应插件行设成启用；没启用的保持停用。
  - 写单元测试：给定一组开关，验证生成的补丁内容正确。
- 验收：
  - `ChatRows`、`SettingsView`、`DSHApp` 中按工具名、页面名分支的 `switch` 已移除；
  - 文档写明「新增功能模块」的步骤：新建目录、实现 Store、注册设置入口、注册冒烟用例。

新增功能模块的具体步骤见 [架构说明：功能注册与扩展](../architecture.md#功能注册与扩展)。当前插件目录为空，LocalPluginGate 固定全部关闭；仅测试目标提供给定开关的实现，生产不接后台、不增加插件界面。

## 后续收敛 B–D（2026-11-04）

2026-11-04 阶段 B：新增 SessionContext 只读入口和按 Store 源文件限制的唯一可写存储；跨 Store 动作 / 连接生命周期改为 init 必传协议，HostStore 掉线与 IntentInbox 通知不再使用构造后回调接线。AppSession 85→35 行，Store 自有可变回调闭包为 0；原有 39 个测试保留，正式测试增至 42/42，通过只读、所有权与 Observation 检查，另以 swiftc 负例确认 18 项越界写入被拒绝。Debug / Release 均零错误零警告，连续生成工程一致，指定 SIM 九项冒烟全 PASS、无启动重试。runtime / SDK 基线一致；媒体 169/18F（比基线少一项 DNS timeout 失败），无新增失败；header 120/120。

2026-11-04 阶段 C：ChatView 784→148 行，拆出文件最大 210 行；RemoteViews 522→112 行，SSHHostForm 225 行，其余远程子视图均小于 100 行，两次拆分独立提交。Features 已无超过 400 行的界面文件（HostStore 417、PhoneExecutor 397 属于状态 / 执行层）。保留父视图草稿、附件、焦点和语音生命周期，模型短名函数随顶栏迁移。使用 -dsh-screen / -dsh-dump-log 核对聊天首页、抽屉、模型选择、设置首页、远程主机页的前后截图；布局与文案一致，模型 / 设置 / 远程页像素一致，聊天 / 抽屉仅有系统遮罩、宠物帧与玻璃合成细微色差。两次提交均经 Debug / Release 零错误零警告、工程重复生成一致、正式测试 42/42、九项通用冒烟全 PASS；runtime 209/10F/5C、媒体 168/19F、SDK 75/2C/1S 逐项一致，header 120/120。聊天拆分无启动重试；远程拆分的 t4 曾连续两次启动超时，保存日志后按用户规则暂停。用户说明电脑曾睡眠，唤醒后授权原参数补跑，最终完成剩余验收。

2026-11-04 阶段 D：XCTestConfigurationFilePath 存在时禁止宿主自动准备引擎和自动连接，并保留 DEBUG 参数兼容；新增测试验证环境识别和假引擎未启动，正式测试 43/43（原测试保留）。删除本地旧空目录和仅有 .DS_Store 的旧服务目录，生成器不会重新创建。更新上下文 / 动作协议职责、所有权及新增模块步骤；Debug / Release 零错误零警告，工程重复生成一致，九项通用冒烟全 PASS，runtime / 媒体 / SDK 无新增失败，header 120/120。未新增系统 API 或改变普通启动 / 产品行为。

## 阶段 E：仓库结构整理

**范围（2026-11-04 用户确认）**：B–D 完成后按 E1→E5 顺序整理。只移动、改名、删除已确认无用的内容，不改变功能逻辑；移动使用 `git mv`。每一步独立中文提交并推送至 `ios/phase1-spike`，说明改动和实际验证，不创建 PR。拿不准的内容先保留，并在提交说明中列明。

**原定全量验收（E2–E5 本轮按后续指示不执行）**：指定 SIM 的 Debug 构建零错误零警告；generic iOS Release 构建通过（`CODE_SIGNING_ALLOWED=NO`）；连续生成两次工程无差异；先 terminate DSH 再运行正式 `xcodebuild test`，全部通过；store、t1、t4、t7、t10、t13、t15、chat、menu 九项冒烟最终 PASS；runtime / 媒体 / SDK 不新增失败，媒体 header 120/120。继续遵守第 4 节的固定 SIM、每次 `-dsh-dump-log`、ps 参数核对、t4 夹具及引擎启动失败保存日志并原参数重试一次的规则。

**执行更新（2026-11-04 用户后续指示）**：先完成结构整理，不再逐步运行全量验收。E1 已取得全量验收结果；E2–E5 本轮只做必要的工程生成和静态引用核对，不运行构建、正式测试、冒烟、Node 全套或运行时重建。下列原定验收项作为后续待补清单，提交说明如实记录未运行范围。

### E1 正式引擎构建配方独立于实验探针

- 用 `git grep` 追踪正式构建、iSH 工具和生成器实际使用的 RuntimeProbe 文件，脚本移至 `runtime/ios/scripts/`，guest 输入移至 `runtime/ios/guest/`，同步所有引用。
- 确认正式工程、构建和测试不再依赖实验 App 后删除余下 RuntimeProbe，历史保留在 git，并更新 changelog；若仍有不可替代用途，保留并移至 `tools/runtime-probe/`，在 README 说明。
- 额外验收：完整运行 `bash tooling/build-ish.sh` 和 `bash runtime/build-ios-runtime.sh`；保存移动前后 rootfs 的 `tar -tJf` 文件名 / 大小清单，要求零差异或仅构建时间戳不同，提交说明记录结论；用新运行时完成全量验收。
- 状态：已完成。17 个共享输入用 git mv 迁移，36 个探针专用文件删除，生产许可原文保留；iSH / 运行时完整重建成功。新旧 rootfs 均 41,044 项，名称 / 大小 / 类型 / 权限 / 链接目标零差异。Debug / Release 零错误零警告，重复生成一致；正式测试 43/43（14 组），首次宿主连接前挂起后按用户授权 terminate 并原命令重跑通过。九项冒烟全 PASS、无引擎启动重试，安装记录与新 manifest 一致。runtime 210/9F/5C（比基线少一个既有失败）、媒体 168/19F、SDK 75/2C/1S，无新增失败；header 120/120。无待定保留文件。

### E2 删除仅服务安卓的运行时遗留

- 删除安卓 Termux / proot 构建入口 `runtime/build-runtime.sh`。
- 逐项检查 `runtime/` 下 direct、session-deletion、boot、bridge、patches、lib、locks、media、tests：iOS 构建或测试使用的保留，仅安卓使用的删除，不确定的保留并列明。
- 谨慎删除共享 `runtime/lib/rtbuild.py` 中仅服务安卓的函数和分支，同步 `.gitignore` 及文档引用。
- 与 E1 相同，完整重建运行时并对比 rootfs 清单，再执行全量验收。
- 状态：结构整理完成。删除安卓入口、5 个 Direct / PRoot 专用文件及 2 个 Ubuntu 锁；rtbuild.py 1530→179 行，保留的 3 个补丁函数及 patch-dsh 参数原文不变。生产 patches / bridge / npm locks / media / session-deletion 与共享测试保留；direct/paths 和 boot-cache 因基线测试仍引用而保留，无待定项。工程已按新构建入口重新生成；按用户后续指示，运行时重建、rootfs 对比及全量验收本轮未运行。

### E3 收拢 Apple 扩展与桥接边界

- 已评估原 Engine 桥可归入 `Modules/DSHRuntime/Native`；保持其独立静态框架编译边界，并在 apple/README 说明原因。
- `Widgets/`、`Share/` 分别移至 `apple/Extensions/Widgets/`、`apple/Extensions/Share/`；共享扩展代码移至 `apple/Extensions/Shared/` 或同等明确的目录。
- 更新生成器，Bundle ID、App Group、entitlements 保持不变；新增 `apple/README.md`，用表格解释各目录，并注明日常开发只需看 `App/` 和 `Modules/`。
- 全量验收，并核对扩展身份与权限配置及重复生成稳定性。
- 状态：结构整理完成。原生桥源码归入 DSHRuntime/Native，仍由 build-ish 编入 ish.xcframework；三个扩展 / 共享目录移至 Extensions，10 个移动文件内容不变。新增 apple/README 目录表；生成器仅更新路径和原生桥导航引用，Bundle ID、App Group、entitlements、目标依赖及编译输入保持不变。连续两次生成产物哈希一致，8 个目标的配置与输入按移动映射一致；按用户后续指示，本轮仅生成工程与静态核对，未运行框架重建或全量验收。

### E4 归档历史设计和文档

- Flutter / 安卓时期及已取消功能的设计移至 `docs/archive/`，开头注明「历史文档，描述的是已删除的 Flutter 版或已取消的功能」。当前 iOS 任务、功能对照、移植说明，以及仍有效的媒体 / 插件资料继续保留在 `docs/design/`。
- docs 顶层保留当前入口 architecture、roadmap、release、changelog，以及 guide、plugins、testing；当前设计仍在 design，其他历史资料归档。
- 修复所有移动造成的 Markdown 失效链接；以 `git grep` 检查旧路径链接为零，再执行全量验收。
- 状态：结构整理完成。16 份历史文档、62 份早期 iOS 实验证据及 64 份旧宣传素材使用 git mv 归入 docs/archive；历史 Markdown 首行统一加注，126 个非 Markdown 文件字节不变。docs 顶层仅保留四个当前文档入口及当前资料目录；design 保留 3 份 iOS 文档和 7 份仍有效的媒体 / SDK 协议 / 方案 A 参考，文件开头说明范围。334 条既有有效本地链接按移动映射核对，git grep 旧路径引用为 0；无待定项。按用户后续指示，未运行全量验收。

### E5 中英文首页提供仓库地图

- 在 README.md / README.en.md 开头增加仓库地图表，说明根目录各文件夹用途、读者及何时修改。
- 明确日常 iOS 开发看 apple/App 和 apple/Modules，运行时看 runtime，工具看 tooling，插件开发看 sdk / examples，历史资料看 docs/archive。
- 同步 AGENTS（CLAUDE.md 是其符号链接，只编辑真身）、中英文 CONTRIBUTING 和架构文档中的目录说明，完成全量验收。
- 状态：结构整理完成。中英文 README 开头以同一张九目录地图说明用途、读者与修改时机；日常入口、引擎、工具、插件开发及历史归档位置明确。AGENTS、其 CLAUDE 符号链接、中英文 CONTRIBUTING、架构与路线图说明已同步。按用户后续指示，本轮只做静态文档 / 路径核对，未运行全量验收；新结构的运行时重建与完整验收留待后续安排。

## 6. 已确定的决定

- **原作者服务相关功能不做**：社区 / 论坛、Star 引导、托管分享链接、分享码、DS Bot。对照表里标成「不做」。
- **DSH Remote 不再有默认服务器**（2026-11-04）：去掉 `dsh.r2049.cn`，用户填写自建服务器地址后登录。
- **插件 / 插件市场不做**（2026-11-04）：上架合规，引擎层禁用插件管理器（负责联网安装的部分）。以后的插件走方案 A：随 App 打包 + 用户后台开关，见 T16。
- **Flutter / 安卓版已按用户阶段 3 授权删除**；旧实现可在 上游 DSH Go 仓库 查看。
- **品牌**（App 图标、显示名、Bundle ID `io.github.fanofacane.dsh`）暂不改，遇到需要时问用户。

## 7. 已知限制 / 待验证

- SSH 不支持 RSA 私钥和带密码的私钥，这是 swift-nio-ssh 的限制。可以在表单里提示，或者自己实现解密。
- 中继模式下不能删除会话（桥接口只在本机）。可以考虑改成用 `workspace/archiveSession` 归档。
- 语音输入只在模拟器上看过界面，还没有在真机上实际说话测试。
- 小组件、控制中心按钮、实时活动、Mac 运行、通知 / 闹钟权限弹窗，都还没在真机上测过，需要用户配合签名。
- 引擎日志只存在内存里（`RuntimeEngine.logTail`）。如果诊断需要，可以在 T15 里做落盘。

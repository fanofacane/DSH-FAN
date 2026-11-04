# DSH Fan 架构

DSH Fan 是 SwiftUI 原生 App，部署目标 iOS 17。设计参考了 DSH Go（其 Flutter / 安卓源码见上游 DSH Go 仓库）与 iSH；实际完成状态以 [iOS 功能对照](design/ios-native-parity.md) 为准。

## 代码入口

日常开发从 `apple/App/` 与 `apple/Modules/` 开始；[README 的 apple/ 目录表](../README.md#apple-目录) 说明系统扩展、共享源文件、资源和测试的职责。原生桥源码归入 `apple/Modules/DSHRuntime/Native/`，构建仍由 `tooling/build-ish.sh` 完成。

引擎配方与 guest / iSH 补丁在 `runtime/ios/`，桥、固定 npm 锁和共享 DSH 补丁留在 runtime 对应目录；`tooling/` 负责工程与开发工具。手机工具目录契约在 `apple/Resources/Phone/phone-ios-tools.json`。iOS 不提供外部插件安装能力；未来插件随 App 打包。

docs/ 只保留当前有效的架构、任务清单、功能对照与更新记录；旧端设计、用户指南、插件开发资料和早期实验记录已删除，见 旧仓库历史（未迁入 dsh-fan）。完整根目录地图见 [README](../README.md#仓库地图)。

## 分层

```text
SwiftUI App（状态、协调、界面、主机选择）
  ├─ DSHClient：HTTP / SSE / mux、会话与领域协议
  ├─ DSHRemote → DSHClient：SSH 与自建 DSH Remote 中继载体
  ├─ DSHPhone：公开系统操作的 MCP / 回环桥与确认策略
  └─ DSHRuntime：运行时安装、iSH 启停、客体文件、日志
       └─ Native/ISHRuntime → ish.xcframework：固定 iSH 内核与原生桥
```

四个模块不依赖 App。`DSHCarrier` 表示远程隧道，`HostStore.makeClient` 根据主机返回已认证客户端。本机与远程使用同一协议客户端；本机桥专有接口遇到中继时明确返回不支持。

## App 依赖组装

`App/Core/AppComposition` 创建 App 状态并选用系统服务。EngineModel / AppSession 及各 Store 通过 EngineControlling、HostProviding、PhoneControlling、TaskNotifying 使用可替换依赖；其余具体状态通过 SwiftUI Environment 传递。功能不从全局定位服务，模块不依赖这些 App 协议。只有唯一 iSH 运行时和 OS 提供的服务在 Core 组装处选用共享实例；App Intents 的 OS 入口使用同一个待处理收件箱，并注明原因。

配色与阅读字号作为 DesignTheme 值向下传递，根 ViewModifier 观察 AppPreferences 的更新；设置页、消息图像策略与通知设置使用注入的同一状态。小组件和分享扩展保留原来的默认配色 / 字号。正式测试用假运行时和假手机生命周期检查 EngineModel，不启动引擎。

## 会话状态的职责

Core/AppSession 只组装八个可观察 Store 并协调切主机时的重置。ConnectionStore 管连接、generation、模型和凭据；TranscriptStore 管当前会话、发送与 follow，其事件折叠和消息动作分置扩展。SessionListStore 管列表、置顶、归档、重命名和删除；WorkspaceStore、ScheduleStore、AgentStore、ControlStore、HostRequestStore 分别管理工作区、定时、Agent、投影 / 权限以及批准 / 问题。

`SessionContext` 是 `@MainActor @Observable` 的共享读取入口。每个 AppSession 只创建一个上下文和一份各 Store；上下文持有各 Store 的共享存储，不复制或同步第二份状态。存储的 setter 限制在拥有者所在源文件（`fileprivate(set)`），上下文对其他 Store 和视图只提供 getter，包括 `@testable import` 也不能直接越界写入。

| 唯一写入 Store | 上下文提供的共享读取 |
|---|---|
| ConnectionStore | 连接状态、generation、client、模型目录、选择与思考档位 |
| TranscriptStore | 当前会话 id、turnRunning、sending；busy 由后两项计算 |
| SessionListStore | 会话列表 |
| WorkspaceStore | 工作区投影、工作区 / 目录选择与创建目标 |
| ControlStore | 权限预设、档位目录与引擎默认档位 |
| AgentStore | Agent 预设选择 |
| HostRequestStore | 运行中会话集合；hasRunningTasks 由它与 busy 合并计算 |

Store 通过非可选的 init 参数接收上下文和需要的 `SessionActions`。后者只声明跨 Store 动作（新建对话、刷新列表、追加提示、设置加载等），由 AppSession 在 Core/SessionActions 中转发给拥有者；无默认空实现，也不在构造后赋值回调。`ConnectionLifecycle` 传递关闭会话、重置、订阅和就绪事件；HostStore 的掉线事件同样在 init 注入。动作对象弱持有以避免循环引用，初始化参数仍为必传。AppSession 的 lazy Store 在 init 返回前全部构造完成。

类型化 API 从上下文中的当前 client 构造；主机 / 手机 / 通知边界继续可以替换。权限偏好仍在 session/create 返回后重新读取；generation 与会话 epoch 丢弃迟到结果，失败的权限更新采用已创建会话，提示在初始快照之后追加。共享状态只由所属 Store 的操作修改，UI 的模型 / 权限选择也通过所属 Store 写入。

ChatView 仅组装页面与保留原有局部状态，顶栏、消息列表、输入区、会话抽屉、空状态和 Key 设置卡分文件。草稿、附件、焦点与语音生命周期保留在父视图，用绑定和动作接入子视图，避免隐藏输入区时丢失状态。远程主机首页、SSH 表单、指纹确认、主机切换器和连接卡片也分别维护。

## 类型化协议边界

`DSHClient` 内的 WorkspaceAPI、ScheduleAPI、AgentAPI、ProviderAPI、AccountAPI、SettingsAPI、FilesAPI 及控制 / 命令 / 凭据接口负责参数打包、回复解析和类型化 mux 流。App 接收领域记录，不直接拼 RPC 或解析回复字典；既有会话 / 二进制能力继续由 DSHClient 提供。AccountAPI 明确要求本机上下文，SSH 即使没有 carrier 仍受本机门控。

只有引擎 schema 定义的服务商与通用表单保留动态字典，相关声明 / 转换逐处注明原因。工具参数、宠物资源清单和 DEBUG 冒烟报告使用 Codable JSONValue，数值桥接保持 Foundation NSNumber 的原有规则；它不替代领域记录。新增接口通过内存 carrier 验证解析、请求字段、错误码、序号折叠与流取消。

## 本机引擎

`runtime/build-ios-runtime.sh` 通过 `runtime/ios/scripts/` 配方构建 Alpine、Node 24 与固定 DSH，并生成归档和 manifest。`apple/Modules/DSHRuntime/Native` 中的 Objective-C 桥由独立脚本编入 ish.xcframework，Swift target 只引用其模块，避免重复编译和泄露内核私有头。`tooling/build-ish.sh` 使用 `runtime/ios/patches/series.json` 固定的唯一补丁链构建 iSH 静态框架；工程生成器把它与归档装入 App，不依赖旧客户端目录。`runtime/lib/rtbuild.py` 仅保留固定 DSH 补丁的严格解析、哈希检查和应用；安卓 Termux / PRoot 构建入口及 Debian / ELF / JNI 组包分支已删除。`runtime/direct/paths.mjs` 和 `runtime/boot/` 仍被跨运行时基线测试使用，保留为测试支持，不进入 iOS rootfs。

安装器核对归档大小 / 哈希后导入私有 fakefs。启动 `dsh web` 监听 `127.0.0.1:3080`；客户端以启动令牌交换内存 Cookie，凭据不进入公开状态或日志。客体路径 `/etc/dsh-app`、`/opt/dsh-app`、`/var/lib/dsh-app`、`/opt/dsh-go` 和 `dsh-web.patch.yml` 属于引擎布局，继续保留。

iSH 在进程内只 boot 一次。停止时回收 PID 1 以外的客体进程并确认端口释放；已挂载 rootfs 的重装 / 重置写待处理标记并返回 `E_RESTART_REQUIRED`，用户关闭并重新打开 App 后处理，不主动退出进程。

每次启动重写 App 自有的 `/opt/dsh-app/ios-store.patch.yml`，禁用插件管理器及其工具。不得联网下载、安装或更新可执行代码。未来方案 A 插件只允许随 App 分发；后台接口未设计，当前 LocalPluginGate 固定全部关闭；PluginCatalog 尚未登记可选插件，不影响既有引擎与手机服务。Core 组合原手机启动钩子与打包插件补丁钩子：非空目录的补丁通过客体 VFS 在每次启动重写，目录为空时清理旧补丁；安全模式全部关闭。插件管理器两行不受开关影响，始终禁用。

## 会话与远程

聊天状态根据持久日志、流式草稿和待提交消息折叠。连接 generation 与会话 epoch 用来丢弃旧连接 / 旧会话的回调；切主机统一释放流和客户端。权限预设更新失败保留已经创建的会话并提示，避免重复创建孤儿会话。

SSH 负责登录、远端启动 / 复用引擎和回环端口转发；中继通过 Noise IK 与自建服务器传输 RPC 和流。中继无默认托管地址，不支持的接口以白名单和主机能力为准。RSA / 加密私钥、WebRTC 直连与终端的限制见任务清单。

## 系统集成与资源

`apple/Extensions/Widgets`、`apple/Extensions/Share`、`apple/Extensions/Shared` 提供小组件、实时活动、分享输入与共享类型。通知只在 scenePhase 为 background 时允许投递，inactive 仍抑制通知。后台执行受 iOS 挂起约束，没有服务器推送。

资源由 `apple/Resources` 自持。隐私清单维护在 `apple/App/PrivacyInfo.xcprivacy`，界面文案使用中英 xcstrings。引擎日志在内存中限长且脱敏；诊断必须经用户人工检查再导出。

## 功能注册与扩展

SettingsRegistry 记录设置入口的标题、图标、分组、顺序、本机限制及延迟创建的目标页面；SettingsView 保留原来的卡片样式，从注册表生成列表。SettingsContext 提供当前状态下的副标题，原有设置的顺序、分隔线和远程账号隐藏规则保持不变。

ToolPresenter 按终端、读文件、写入 / 编辑、搜索、网页、手机等工具族提供标签、图标和摘要，ToolPresenterRegistry 选择策略；未知工具保留原名与通用参数摘要。ChatRows 只渲染返回的展示值。DebugPageRegistry 与 FeatureSmokeRegistry 仅在 DEBUG 下编译，原参数名、未知页面回退、未知冒烟错误码和逐步写入结果的方式保持不变。

新增功能模块按以下步骤：

1. 在 `apple/App/Features/<功能>/` 新建目录，实现对应 View 和有状态职责需要的 Store；仅在确实需要替换依赖时加协议。模块接口放 DSHClient，模块不得依赖 App。
2. 在 Core/AppComposition 或 AppSession 组装依赖。跨 Store 读取时必须在 Store 的 init 注入 SessionContext，动作通过必传 SessionActions 或相应窄协议注入，不添加构造后赋值的 var 回调。新增共享状态时，把唯一可写存储放在拥有它的 Store 源文件中，在上下文只读暴露，并补所有权测试；视图通过 Store / Environment 读取，局部界面状态使用绑定。
3. 在 SettingsRegistry 的 entries 增加一行 SettingsEntry，指定目标页与展示元数据；新文案同步中英 xcstrings。需要调试入口时，在 DebugPageRegistry 增加一行工厂。
4. 在 Debug 新文件实现冒烟用例，在 FeatureSmokeRegistry.cases 增加一行注册；保留清理步骤和 RUNNING / 最终 result，正式测试使用假 client 验证状态与协议。
5. 若新增工具展示，实现 ToolPresenter 并在 ToolPresenterRegistry 增加一行；重新生成工程，执行构建、正式测试和九项通用冒烟。

可选插件只能随 App 打包。登记 PluginDescriptor 及其引擎行 id 后，由 PluginPatch 生成启停行；设置入口字段仅引用注册 id，当前不创建任何插件界面。生产仅有固定关闭的 LocalPluginGate，测试用开关只存在于测试目标。不得借此新增下载、安装、更新、市场或后台接口。

## 工程与验证

只修改 `tooling/generate-apple-project.rb` 后重新生成工程；分组、构建文件和临时 UUID 保持确定性。模拟器固定使用 iPhone 18 Pro 的显式设备 ID；多个模拟器共享 Mac 的回环端口，不在 WOO UI Review 上运行 DSH。

验证命令、已接受的运行时基线与真机限制见 [README 开发约定](../README.md#开发约定) 和 [iOS 任务清单第 4 节](design/ios-codex-tasks.md#4-构建与验证)。T18–T23 及后续会话接线、大界面拆分已完成，保持用户可见行为与模块依赖方向。XCTest 宿主以 XCTestConfigurationFilePath 的存在判断，DEBUG 仍兼容 -dsh-unit-tests；宿主显示空白页面，禁止自动准备引擎和自动连接，正式测试仍可显式使用假依赖调用 Store。

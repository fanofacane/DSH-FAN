# 原生 iOS 版与 Flutter 安卓版功能对照

> Flutter 版已删除，可在 上游 DSH Go 仓库 查看；表内旧版名称仅用于功能对照。

> 2026-11-03。原生版位于 `apple/`，对照对象为 `原 Flutter 版 lib`（Flutter，安卓为主）。
> 状态：✅ 已有 · 🟡 部分 · ❌ 缺失 · ⛔ iOS 不适用。工作量：S（≤1 天）· M（2–4 天）· L（1 周以上）。

## 1. 核心（已对齐）

| 功能 | 状态 | 说明 |
|---|---|---|
| 本机引擎：安装、启动、停止、重启、重置、安全模式、日志 | ✅ | 冷启动待处理标记、保留 PID 1 与 Flutter iOS 版一致 |
| 聊天：流式回复、思考、Markdown、代码块、图片附件 | ✅ | |
| 会话：列表、搜索、重命名、删除、恢复历史 | ✅ | T7 工作区分组；T11 置顶区、归档 / 恢复、运行会话停止后归档。归档与置顶均以引擎返回为准 |
| 工具调用展示与批准、模型提问 | ✅ | 「本对话都允许」❌（协议只有 allowed-once） |
| 模型与思考强度、权限档位、API Key | ✅ | iOS 默认完全访问（无命令沙箱） |
| 手机控制（系统框架档）、Siri / 快捷指令 | ✅ | 安卓的无障碍读屏 / 点击 ⛔ |
| 桌宠 Deepy、雾蓝玻璃风格 | ✅ | T15 增加青绿 / 浅紫强调色；换宠物未做 |

## 2. 缺失的功能

| 功能 | Flutter 代码量 | 状态 | 工作量 | 说明 |
|---|---|---|---|---|
| **远程连接 · SSH**（连电脑上的 DSH） | ssh/* + ui/remote 约 2.5k 行 | ✅ | — | `DSHRemote`（swift-nio-ssh）：密码 / Ed25519·ECDSA 私钥登录、首次核对指纹（TOFU）、远端启动或复用 `dsh web`（脚本与 Android 一致，共用 `~/.dsh-app-remote`）、本机回环端口转发；主机列表、切换、断线重连卡片。暂不支持 RSA 和带密码的私钥（NIO SSH 限制） |
| **远程连接 · DSH Remote 中继** | dsh_remote 6k 行 | ✅（仅中继） | — | `DSHRemote/Relay`：Noise IK（CryptoKit，过上游向量）、控制帧/DSHF、中继节点 attach、安全通道+RPC、隧道载体（调用/流/分块传输/健康探测）；只连用户自建的 ds-harness-remote 服务器（2026-11-04 去掉原作者托管的默认服务器 dsh.r2049.cn），浏览器登录与邮箱登录、主机列表、身份指纹首用确认。**未做 WebRTC 直连**（LAN/P2P/TURN，需 libwebrtc ≈10 MB），全部走中继 |
| **DeepSeek 账号登录**（余额、用量） | ui/account 0.9k | 🟡 | M | T5：本机状态订阅、Safari 授权、取消 / 退出、账号资料与钱包余额界面已实现；按用户确认走 `account/getBalance`，授权保留在引擎。授权准备 / 取消测试通过；实际授权回跳、余额与无 Key 对话未人工登录验证 |
| **其他模型服务商**（OpenAI 兼容、自定义） | ui/providers 3.5k | ✅ | — | T4：服务商列表、协议 / 端点 / Key / 模型配置与发现；设置变更携带 revision，内置路由可保留引擎默认；新模型进入聊天选择器。未逐一验证第三方付费服务 |
| **插件与市场** | ui/plugins 11k | 不做 | — | 上架合规（审核指南 2.5.2：不下载执行代码），2026-11-04 取消；引擎插件管理器由 `RuntimeEngine.storePatch` 禁用。以后插件随 App 打包、由后台开关（方案 A） |
| **工作区**（目录、文件浏览） | workspace 1.4k + files 1.5k | ✅ | — | T7：注册 / 重命名 / 移除、目录选择与会话分组；T8：文件浏览、实时失效更新、版本一致的分窗读取与预览 |
| **终端** | ui/terminal 2k | ❌ 暂缓 | M | T9 用户确认暂缓：捆绑 0.2.1-rc.4 已改用 terminal/attach 双向流，清单中的旧 write / resize / follow 不存在；中继不支持流上行。本轮未引入渲染依赖、未添加不可用入口 |
| **子代理 / 团队 / Agent 预设** | agents 1.4k | 🟡 | M | T10：可展开子任务、按父子地址读记录、可继续子代理追问 / 中断、预设读取 / 选择；一次性子代理只读。团队任务板未在 T10 范围，长历史仅显示跟随窗口 |
| **Bot**（DS Bot） | ui/bots 6.3k | ⛔ 不做 | — | 依赖原作者服务 |
| **待办 / 目标条、计划审阅** | chat/dock 1.5k | 🟡 | M | T1：实时待办、目标进度及暂停 / 继续 / 编辑 / 完成 / 清除已完成；计划审阅未在 T1 范围 |
| **@ 提及文件、斜杠命令面板** | chat/mention 1.3k + slash_palette | ✅ | — | T2：输入末尾 @ 补全（含空格路径、目录），命令目录与执行；原作者服务命令隐藏。光标位于文本中间时不提供补全 |
| **语音输入** | chat/voice 1k | ✅ | — | Speech 框架，支持时走设备端识别；输入框为空时显示麦克风 |
| **消息菜单**（复制、重试、分支、编辑） | message_menu | ✅ | — | T3：增加引用（保留输入草稿）、系统 ShareLink、会话附件图片预览 / 保存相册；独立一行的 HTTPS Markdown 图片支持预览 / 保存。主机文件图片留给 T8 |
| **产物预览**（PDF / Office / 网页）、diff 页 | artifact_preview 1.7k、diff_page | 🟡 | M | T8：Quick Look 文档预览、关闭脚本的网页预览、Markdown 文件 / 图片路径、工具改动片段页；Office 优先原生预览，不支持时尝试主机转换。真实 Office 文件未验证；仅显示 edit / write 报告的差异，不声称覆盖 bash 改动或完整仓库 diff |
| **定时任务** | header_schedule | ✅ | — | T13：全主机 / 当前对话列表、指令 / 标题 / 执行规则编辑、分页历史、删除确认；创建交给模型工具，更新携带原记录做比较。iOS 本机需持续运行引擎 |
| **用量 / 轨迹 / 运行信息** | usage_sheet、trajectory_sheet、run_info | ✅ 基础轨迹 | — | T12：上下文占用 / 下次请求估计、未缓存与缓存 token、模型 / 工具耗时、主机 / 模型与最近持久事件时间线；缺失数据标为未报告，不推算费用。未复刻瀑布图与首 token 分解 |
| **联网搜索、图像与视频生成设置** | settings/web_search、media | 🟡 | S–M | T6：按引擎 schema 提供搜索 / 媒体设置、目录预设、集合与凭据引用表单；带 revision 保存。搜索往返验证通过；测试引擎未安装媒体插件，未验证真实图像 / 视频调用，复杂非枚举 union 明确提示不支持 |
| **引擎参数**（子代理、Agent 循环、命令执行） | engine_settings | ✅ | — | T15：列出当前主机可用的子代理、模型选择、循环、命令沙箱设置，复用 schema / revision 表单 |
| **分享链接**（托管分享、分享码） | share_hosted、share_code | ⛔ 不做 | — | 依赖原作者服务 |
| **社区 / 论坛、Star 引导** | community、forum、star | ⛔ 不做 | — | 依赖原作者服务 |
| **个性化、界面、隐私、诊断、语言** | settings/* | ✅ | — | T15：本机共享 AGENTS.md 回复偏好（含冲突检查）、正文 / 代码字号、外观与强调色、外部图片手动加载、检查后日志导出、英语 / 简中 / 跟随系统（重开生效）。远程偏好文件不提供本机代写；不自动上传诊断 |
| **外观**（配色、壁纸、深浅色切换） | settings/appearance | 🟡 | S | T15：系统 / 浅色 / 深色与雾蓝 / 青绿 / 浅紫强调色；未做壁纸。小组件 / 分享扩展继续雾蓝配色 |
| **通知设置**、后台引导 | notification_settings、background_guide | ✅ | — | T14：后台回复完成、等待批准 / 提问、非当前会话结束的本地通知；默认关闭，点击返回来源主机 / 会话；有限后台延长与 iOS 挂起说明。没有服务端推送 |

## 3. iOS 不适用（不做）

安卓无障碍读屏 / 点击、悬浮窗桌宠、Shizuku / ADB、厂商后台白名单、APK 自更新、动态取色、小米焦点通知、桌面图标切换、灵动岛插件（安卓）。

## 4. 建议顺序

1. **远程连接**：SSH 与 DSH Remote 中继已完成；WebRTC 直连暂缓（体积大，中继已可用）。
2. 小而高频：消息菜单、语音输入、待办 / 目标条、@ 文件与斜杠命令。
3. 账号登录与其他服务商。
4. 工作区 + 文件 + 终端。
5. Bot、分享：不做（原作者服务）。插件与市场：不做（上架合规）。

## 5. 本轮任务验证记录

2026-11-04 阶段 1：丢弃未提交的 T16 草稿，合并 App Store 整改；插件管理器每次启动保持禁用，无默认托管中继，回复偏好空白值归一化，App 隐私清单随包。模拟器构建无错误无警告；`-dsh-feature-smoke store` PASS，插件管理器查询 / 安装接口均返回错误，Agent 预设仍可读。

2026-11-04 阶段 2：四项修复完成；模拟器构建无错误无警告，连续两次工程生成的 pbxproj / scheme 逐字节一致，模型夹具只监听回环地址且发现 / 404 检查通过。Codex 运行 `store`、T1、T4、T7、T10 全部 PASS；用户确认 Claude 在同一未提交代码及指定 iPhone 18 Pro 上复核 T13、T15、chat、menu 全部 PASS，通用冒烟验收通过。此前等待不到 T13 结果由多模拟器测试环境引起；WOO UI Review 的旧 DSH 已由 Claude 退出。后续命令与冒烟脚本固定 SIM，并用 ps 校验启动参数。旧 T16 插件数据造成的删除不支持记录按用户确认保留，不改删除代码。

2026-11-04 阶段 3：移除旧客户端、约 9.5G 本地构建产物及安卓 / Flutter 专用工具，原生资源、许可和文档独立；媒体 / 插件 schema / 回放共 11 份夹具迁出后字节一致，SDK 文案与技能打包不再依赖旧目录。重新生成工程稳定，iPhone 18 Pro 构建无错误无警告，八组 Swift 断言全部 PASS，媒体头部夹具 120/120 PASS，分享站点回放测试 PASS。runtime 209/10F/5C、媒体 168/19F、SDK 75/2C/1S 与原始提交逐项比较无新增失败，按用户决定保留；基线与原因已写任务清单第 4 节。指定 SIM 的 store、T1、T4、T7、T10、T13、T15、chat、menu 冒烟全部 PASS（包含真实模型）。旧测试数据导致的 chat 删除不支持记录继续保留。当时保留的混合构建输入已在阶段 E2 收敛：安卓入口删除，`runtime/lib/rtbuild.py` 仅保留共享补丁工具；原入口见 旧仓库历史（未迁入 dsh-fan），7 处路径命中均为上游源码引用，详见提交说明。

2026-11-04 T18：生成器新增 DSHTests / 宿主关联、Debug testability 和 scheme 测试 action，八组脚本迁入 apple/Tests 并改为 Swift Testing，保留全部断言。正式 xcodebuild test 与结果包均确认 8 suite / 8 test PASS、0 FAIL、0 SKIP；独立构建无错误无警告，工程再生成无 diff，指定 SIM 九项通用冒烟全 PASS。测试 action 用专用 DEBUG 参数加载空白宿主，不启动产品生命周期服务，普通启动保持原行为。规模：ChatModel 801→801、ChatView 777→777、Glyphs 578→578、RemoteViews 517→517、HostStore 412→412 行；App 中 .shared 匹配 95→95 行、原始 api 调用匹配 61→61 行。没有待定文件，未新增第三方依赖。

| 任务 | 交付状态 | 验证与限制 |
|---|---|---|
| T1 待办 / 目标条 | ✅ | iPhone 18 Pro（iOS 27.2）构建通过，无新增源码警告；`-dsh-feature-smoke t1` PASS（真实 DeepSeek 模型），观察到待办和进度、目标暂停 / 编辑 / 继续 / 完成 / 清除及过期 revision 拒绝；模拟器中文截图核对。`swiftc apple/Modules/DSHClient/SessionControl.swift tooling/tests/apple-control-tests.swift -o /tmp/dsh-control-tests && /tmp/dsh-control-tests` PASS。当前引擎将过期版本包装成 `gateway/internal`，界面保留实际错误码。工程生成器使用稳定 UUID，后续增量生成减少无关差异。 |
| T2 文件提及 / 命令 | ✅ | 构建通过，无新增源码警告；`-dsh-feature-smoke t2` PASS：引擎返回 6 个命令、16 个文件候选，`/permission` 成功；Swift 提及语法 / 边界测试 PASS；中文命令面板截图。提及按 DSH 文本语法发送，不附加伪附件。补全作用于输入末尾。 |
| T3 消息菜单 | ✅ | 构建通过，无新增源码警告；`-dsh-feature-smoke t3` PASS（真实模型图片请求、历史附件读取、PNG 数据写入模拟器相册、引用格式）；中文图片 / 引用截图核对。相册权限仅添加照片；拒绝及保存失败保留稳定错误码。系统分享菜单和真机权限体验待手动确认。 |
| T4 模型服务商 | ✅ | 构建通过，无新增源码警告；`-dsh-feature-smoke t4` PASS：无凭据本地 HTTP 模型端点发现、自定义配置写入、模型进入选择器、临时配置移除；服务商页中文截图。未使用新 API Key，第三方真实付费模型调用未验证。 |
| T5 DeepSeek 账号 | 🟡 已实现，待真实授权验收 | 构建通过，无新增源码警告；`-dsh-feature-smoke t5` PASS：观察 account/watch、准备官方授权地址、取消授权；中文账号页截图。用户已确认改用 `account/getBalance`。未替用户登录：Safari 回跳、真实账号余额、无 Key 模型调用、退出授权需人工确认。远程连接隐藏入口，客户端拒绝 account/*。 |
| T6 搜索 / 媒体设置 | 🟡 媒体未装 | 构建通过，无新增源码警告；`-dsh-feature-smoke t6` PASS：搜索次数修改与恢复；`apple-settings-tests.swift` PASS（引用、可空字段、secret 包装、默认值）。中文设置列表截图。媒体插件缺席，目录预设和媒体表单尚未在真实插件上验证；不会把 secret 字段作为普通设置写入，只通过其凭据引用设置 Key。 |
| T7 工作区 | ✅ | 构建通过，无新增源码警告；`-dsh-feature-smoke t7` PASS：创建测试目录、浏览、注册 / 重命名 / 移除工作区、新会话 cwd 与引擎成员列表归属、移除后目录仍存在。Swift 工作区流折叠测试 PASS。SSH 默认目录在未选择工作区 / 目录时继续生效；跨 SSH / 中继的实际主机未在此项重测。 |
| T8 文件 / 产物 / diff | 🟡 部分 diff | 构建通过，无新增源码警告；`-dsh-feature-smoke t8` PASS（真实模型 write / edit、文件列表 / 文本 / multipart 字节读取、工具 diff、原生 PDF 预览检查）；Swift 二进制解码 / 差异测试 PASS。预览最多 50 MiB，关闭时清理临时文件；网页预览不执行脚本。真实 Office / 远程大文件、bash 产生的差异未验证或未覆盖。 |
| T9 终端 | ❌ 用户确认暂缓 | 已检查捆绑运行时的 terminal controller README 与 typert.remote-client.d.ts，以及 Dart terminal_api.dart 和 Swift 中继载体；旧接口已移除，现行协议需双向流。用户选择暂缓后继续 T10。本项仅文档变更，沿用 T8 已通过的构建，未新增依赖或入口。 |
| T10 子代理 / 预设 | ✅ | 构建通过，无新增源码警告；`-dsh-feature-smoke t10` PASS（真实模型创建 continuable 子代理，按父地址读回复、追问、中断，预设读取 / 选择）；Swift 路由测试 PASS（父子地址、一次性只读、外部任务不可打开）。按用户确认使用 subagentCatalog 投影，后续冲突仍逐项确认。团队任务板与长历史分页未覆盖。 |
| T11 会话归档 / 置顶 | ✅ | 构建通过，无新增源码警告；`-dsh-feature-smoke t11` PASS（真实短回复后置顶、归档自动清除置顶、恢复、再次置顶 / 取消）。侧栏置顶与归档列表依据 workspace/follow 和操作返回；运行中的会话归档前明确确认停止。中继删除仍不支持，可使用归档。 |
| T12 用量 / 轨迹 | ✅ 基础轨迹 | 构建通过，无新增源码警告；`-dsh-feature-smoke t12` PASS（真实模型 token、contextPressure、sessionStats、持久事件时间线）；Swift 缓存计数、缺失值、溢出与事件时间测试 PASS。轨迹为真实事件时间列表，未实现瀑布图 / 首 token 分解；未知价格不计算费用。 |
| T13 定时任务 | ✅ | 构建通过，无新增源码警告；`-dsh-feature-smoke t13` PASS：真实模型创建远期测试任务，catalog / history / 标题与指令编辑 / every 规则更新 / 删除并确认清理；Swift expected 记录与日期测试 PASS。未等待真实定时投递，后台执行限制在 T14 说明；创建入口追加到现有输入草稿。 |
| T14 通知 / 后台 | ✅ 模拟器验证 | 构建通过，无新增源码警告；`-dsh-feature-smoke t14` PASS：允许系统通知后真实投递、前台抑制、事件去重、通用文案检查，测试后恢复开关并清理通知；中文设置页截图。冒烟模拟后台门控，没有模拟真实系统挂起；真机锁屏、后台期限、点击返回与冷启动仍需人工确认。 |
| T15 设置补全 | ✅ | 构建通过，无新增源码警告；`-dsh-feature-smoke t15` PASS：真实模型在新会话读取回复偏好、过期版本拒绝并恢复原文件、外观持久化与恢复、未检查日志拒绝导出、合成日志导出 / 清理。中文深色 / 青绿即时切换截图核对后恢复。正文 / 代码缩放不改变导航控件；语言需重开；日志导出必须手动检查，不把自动脱敏当保证。 |

2026-11-04 T19：42 个 Swift 文件用 git mv 按 Core / Features / Debug 整理，45 个 App Swift 文件 SHA-256 全部不变。生成器递归建立目录分组，连续两次生成工程 / scheme 无 diff；独立构建无错误无警告，正式测试 8 suite / 8 test PASS，指定 SIM 九项通用冒烟全 PASS（真实模型）。规模：ChatModel 801→801、ChatView 777→777、Glyphs 578→578、RemoteViews 517→517、HostStore 412→412 行；App 中 .shared 匹配 95→95 行、原始 api 调用匹配 61→61 行。没有待定文件，未新增第三方依赖。

2026-11-04 T20：新增 Core/AppComposition 组装，EngineControlling / HostProviding / TaskNotifying / PhoneControlling 四个可测试边界，功能改用初始化参数或 Environment。DesignTheme 传递配色 / 阅读字号，根 ViewModifier 观察偏好；系统媒体服务也从 Core 注入。保留 RuntimeEngine 唯一内核与 App Intent OS 收件箱的必要共享入口并注明原因。构建零错误零警告，正式测试 9 suite / 9 test PASS，新增 EngineModel 假依赖生命周期 / busy / 错误测试；工程连续生成无 diff。九项通用冒烟全 PASS，后四项获用户授权后重跑，均以 ps 核对参数并等待最终 result。驱动 launch 添加 terminate-running-process，避免复用无测试参数实例。规模：ChatModel 801→809、ChatView 777→784、Glyphs 578→578、RemoteViews 517→522、HostStore 412→416 行；App 中 .shared 95→7、原始 api 调用匹配 61→61。没有待定文件，没有新增第三方依赖或改变模块依赖方向；真机系统权限验证未运行（本项为保持行为的依赖重构，只有指定模拟器条件）。

2026-11-04 T21：DSHClient 新增七个领域 API 及控制 / 命令 / 凭据接口，原解析并入对应文件；App 改用类型化记录与流。原始 api 调用 61→0，动态字典只保留 schema 表单的 33 处，每处注明原因。工具参数、宠物清单和 DEBUG 报告改用 Codable JSONValue，NSNumber 数值桥接经验证保持一致。构建零错误零警告，正式测试 21 test / 10 suite PASS，覆盖解析、请求字段、错误码、本机门控、流序号与取消、资源数值。首次测试宿主未收到参数，用户授权退出目标 DSH 后重跑通过。指定 SIM 九项通用冒烟全 PASS，工程重复生成无 diff。规模：ChatModel 809→787、ChatView 784→784、Glyphs 578→578、RemoteViews 522→522、HostStore 416→416；.shared 7→7、api 调用 61→0。没有待定文件，没有新增第三方依赖或反向模块依赖；清除了本项框架构建生成的 apple/build。

2026-11-04 T22：ChatModel 按职责拆为八个可观察 Store，Core/AppSession 仅组装、接线并协调主机重置；所有视图直接读取对应 Store，不留旧名兼容层。保留原连接 generation、会话 epoch、失败权限更新采用会话和 create 后读取最新权限的时序。构建零错误零警告，正式测试 32 test / 11 suite 全 PASS（每个 Store 均有假 client 测试），指定 SIM 九项通用冒烟全 PASS，连续生成工程无 diff。规模：ChatModel 787→AppSession 85、ChatView 784→784、Glyphs 578→578、RemoteViews 522→522、HostStore 416→416、PhoneExecutor 397→397 行；新 Store / 扩展最多 165 行。App 中 .shared 匹配 7→7 行、原始 api 调用匹配 0→0 行。没有待定文件，未新增第三方依赖。

2026-11-04 T23：设置入口、工具展示、DEBUG 页面与 feature 冒烟改为注册表，15 个用例主体与 T22 逐行比较一致（仅缩进、上下文别名和 save 载体变化）。本地 PluginGate 固定全关闭，当前可选目录为空，Core 组合原手机钩子与客体补丁钩子；测试开关能生成正确启停行，但永远不能启用插件管理器。没有后台接口或插件界面。构建零错误零警告，正式测试 39 test / 13 suite 全 PASS、0 FAIL、0 SKIP；指定 SIM 九项通用冒烟全 PASS，ps 核对参数并等待最终 result，设置页中文截图核对，连续生成工程无 diff。规模：AppSession 85→85、ChatView 784→784、Glyphs 578→578、RemoteViews 522→522、HostStore 416→416、PhoneExecutor 397→397；FeatureSmoke 370→74、DSHApp 212→171、ChatRows 326→282、SettingsView 268→240 行。App 中 .shared 匹配 7→7 行、原始 api 调用匹配 0→0 行。没有待定文件或新增依赖，指定保留目录未删除；新增模块步骤见架构说明。

2026-11-04 阶段 B：新增 SessionContext 只读入口和按 Store 源文件限制的唯一可写存储；跨 Store 动作 / 连接生命周期改为 init 必传协议，HostStore 掉线与 IntentInbox 通知不再使用构造后回调接线。AppSession 85→35 行，Store 自有可变回调闭包为 0；原有 39 个测试保留，正式测试增至 42/42，通过只读、所有权与 Observation 检查，另以 swiftc 负例确认 18 项越界写入被拒绝。Debug / Release 均零错误零警告，连续生成工程一致，指定 SIM 九项冒烟全 PASS、无启动重试。runtime / SDK 基线一致；媒体 169/18F（比基线少一项 DNS timeout 失败），无新增失败；header 120/120。

2026-11-04 阶段 C：ChatView 784→148 行，拆出文件最大 210 行；RemoteViews 522→112 行，SSHHostForm 225 行，其余远程子视图均小于 100 行，两次拆分独立提交。Features 已无超过 400 行的界面文件（HostStore 417、PhoneExecutor 397 属于状态 / 执行层）。保留父视图草稿、附件、焦点和语音生命周期，模型短名函数随顶栏迁移。使用 -dsh-screen / -dsh-dump-log 核对聊天首页、抽屉、模型选择、设置首页、远程主机页的前后截图；布局与文案一致，模型 / 设置 / 远程页像素一致，聊天 / 抽屉仅有系统遮罩、宠物帧与玻璃合成细微色差。两次提交均经 Debug / Release 零错误零警告、工程重复生成一致、正式测试 42/42、九项通用冒烟全 PASS；runtime 209/10F/5C、媒体 168/19F、SDK 75/2C/1S 逐项一致，header 120/120。聊天拆分无启动重试；远程拆分的 t4 曾连续两次启动超时，保存日志后按用户规则暂停。用户说明电脑曾睡眠，唤醒后授权原参数补跑，最终完成剩余验收。

2026-11-04 阶段 D：XCTestConfigurationFilePath 存在时禁止宿主自动准备引擎和自动连接，并保留 DEBUG 参数兼容；新增测试验证环境识别和假引擎未启动，正式测试 43/43（原测试保留）。删除本地旧空目录和仅有 .DS_Store 的旧服务目录，生成器不会重新创建。更新上下文 / 动作协议职责、所有权及新增模块步骤；Debug / Release 零错误零警告，工程重复生成一致，九项通用冒烟全 PASS，runtime / 媒体 / SDK 无新增失败，header 120/120。未新增系统 API 或改变普通启动 / 产品行为。

2026-11-04 阶段 E：正式 iOS 构建输入独立至 runtime/ios，安卓组包遗留删除，原生桥归入 Modules/DSHRuntime/Native，扩展集中到 Extensions；旧设计、实验记录和素材归档，首页提供中英文仓库地图。E1 重建、rootfs 清单对比、43 项测试和九项冒烟通过；E2–E5 按用户后续指示未运行构建、测试、冒烟、Node 基线或运行时重建，仅记录移动内容一致、工程配置保持和静态链接核对结果。

# 任务：引擎升级到 DSH 0.2.2-rc.1，并把 DSH Fan 补齐到 DSH Go 1.0.11 的全部功能

> 给 Codex 的执行提示词。按步骤连续执行到全部完成，**中途不要停下来等用户验收**。这次的要求是**完全补齐**：不允许遗漏、不允许「简化版」「部分实现」「基础版」作为结束状态。完成与否由第 2 节的清点门槛机械判定，不由自述判定。

## 0. 开工前

1. 完整阅读 `AGENTS.md`（硬规则优先于本文）、`README.md`、`docs/architecture.md`、`docs/design/ios-codex-tasks.md` 第 4 节（构建、测试、冒烟、固定模拟器 `SIM=51831DA4-9348-4053-A81C-54B3C995A73A`）、`docs/design/ios-native-parity.md`（含第 6 节设置与宠物迁移记录），以及此前两份提示词 `docs/design/settings-port-codex-prompt.md`、`docs/design/chat-run-info-codex-prompt.md`（其中的决策继续有效：宠物美术为占位、鲸娘只放 `apple/Resources/PetsLocal/` 不提交、安卓专属能力做 iOS 等价替代）。
2. **前置条件**：`chat-run-info-codex-prompt.md` 的任务必须先全部完成并提交（`git status` 中不应残留它的未提交改动）。如果还没做完，先按那份提示词做完，再开始本任务。
3. 参考仓库（只读，不改、不提交）：`~/Documents/ChatGPT/dsh-go`，DSH Go 1.0.11（`main` 63e255fa）。版本标签有 `v1.0.8`、`v1.0.9`，1.0.10 / 1.0.11 用提交 `5e3b5498` / `8ccb43ca`。用 `git -C ~/Documents/ChatGPT/dsh-go log -p v1.0.8..HEAD -- app/lib packages runtime` 逐条阅读 1.0.9–1.0.11 的改动，每条改动都要在清单里有归宿。
4. 记录基线：开工前跑一次 `xcodebuild test`、`python3 tooling/apple-smoke.py`、`node --test runtime/tests/*.test.mjs`，把失败 / 取消用例名记下（runtime 当前基线 207 通过 / 10 失败 / 5 取消，名单见 `ios-native-parity.md` 第 6 节）。

## 1. 范围

**除下列封闭排除清单外，DSH Go `app/lib/`、`packages/dsh_client/lib/` 的全部用户可见功能和行为都在范围内。** 不在清单里的东西不能以任何理由跳过。

排除清单（只有这些可以不做）：

| 类别 | Dart 路径 / 功能 | 原因 |
|---|---|---|
| 用户指定不做 | `ui/web/`（网页版界面、`local_web_screen`、界面「原生 / 网页」切换）、`ui/terminal/` | 用户决定 |
| App Store 合规（AGENTS.md） | `ui/plugins/` 中插件市场、安装、卸载、更新与插件管理页；`lib/plugins/` 中下载 / 安装逻辑；`links/plugin_links.dart`；`ui/bots/`；`ui/community/`、`ui/forum/`、`lib/forum`；`ui/share_hosted/`、`lib/share_hosted`、`ui/share_code/`、`lib/share_code`、`ui/replay/`（托管链接与回放）；`ui/star/`；`ui/update/`、`lib/update/`（自更新）；`lib/usage/` 与 `settings/usage_stats_section.dart`（向原作者服务器发匿名统计） | 硬规则：不下载执行代码，不接原作者服务 |
| 安卓专属且 iOS 无等价物 | 不打扰模式与后台屏（`phone/dnd_mode_page`、ADB / Root / Sui 授权）、无障碍读屏 / 点击与恢复（`a11y_restore_sheet`、`restricted_settings_guide`、`screen_text_sheet`）、手机操控解除限制（`phone_unlock_page`、`hold_to_confirm` 用于解锁的部分）、悬浮窗与悬浮条、厂商后台白名单、刷新率设置、小米焦点通知、图片桌面快捷方式、`MethodChannel` 原生桥本身 | 平台不存在 |

注意：

- 安卓能力**有** iOS 等价物的不在排除清单，必须做等价实现，例如：启动器长按快捷入口 → 主屏幕快捷操作（`UIApplicationShortcutItem`：新对话、语音输入、最近三个对话）；系统分享接收文本 / 图片 / 文件 → 分享扩展支持文件；快速设置磁贴 → 控制中心控件；悬浮窗宠物 → 实时活动 / 灵动岛（已有，补齐行为）。
- `ui/plugins/` 里**不属于**市场 / 安装 / 管理的部分（例如聊天中插件产出的 DSH UI 渲染、`cordis` 只读的引擎插件清单、随 App 打包插件的设置页）在范围内，按方案 A（插件随 App 打包、不能联网安装）实现。插件管理器保持禁用，`RuntimeEngine.storePatch` 不得移除，store 冒烟必须 PASS。
- 名称：界面里的「DSH Go」写成「DSH Fan」；`dshgo://` 链接写成 DSH Fan 现有的 `DSHLink.scheme`；资源与技能名中的 `dsh-go` 改成 `dsh-fan`（不要误改 `dsh-goal` 这类上游包名）。

## 2. 防遗漏机制：逐文件清点与完成门槛（第一步就做，最后用它判定完成）

1. 新增 `tooling/parity-inventory.py`，生成并校验 `docs/design/parity-inventory.json`（机器可读）与 `docs/design/parity-inventory.md`（人读表格）。清单行来源：
   - `~/Documents/ChatGPT/dsh-go/app/lib/**/*.dart` 与 `packages/dsh_client/lib/**/*.dart` 的**每一个文件**（不含生成文件 `*.g.dart`、`l10n/gen/`）；
   - `app/test/**/goldens/*_light.png` 的**每一张**金图；
   - `app/lib/l10n/app_zh.arb` 及 `l10n/parts/*_zh.arb` 的**每一个**文案 key；
   - v1.0.8..HEAD 的每一条 changelog 条目（`docs/changelog.md` 1.0.9–1.0.11 中文部分逐条）。
2. 每行必须有：`status`（只能是 `done` / `excluded` / `infra`）、Swift 对应文件与符号、证据（单元测试名、冒烟用例、金图比对图路径或截图路径）、`excluded` 时引用第 1 节排除清单的哪一行、`infra` 时说明它是哪种不需要单独界面的内部实现（例如 Flutter 专用的布局缓存）并指明 Swift 侧由什么承担。**不允许 `partial`、`todo`、`basic` 之类的状态。**
3. 对每个 `done` 的 Dart 文件，在 JSON 中附「行为清单」：从源码逐条抽取该文件的用户可见状态、交互、错误 / 空状态、文案、动画与数据来源，每条对应 Swift 证据。行数显著少于 Dart（例如 Swift 不足 Dart 的 40%）时，必须在行为清单里逐条说明 Dart 的每块逻辑在 Swift 里由什么覆盖，否则视为未完成。
4. `python3 tooling/parity-inventory.py --check` 在任何一行缺字段、状态不合法、证据文件不存在、排除引用不在第 1 节、或金图没有比对图时返回非零。**这个检查通过是本任务完成的必要条件。**
5. 先用这个清单**重新审计已经标为完成的部分**（设置、宠物、聊天运行信息，以及 `ios-native-parity.md` 中所有 ✅ 行）。已知不完整、必须补齐的例子：`FeatureCatalogPage.swift` 中的技能页与后台任务页是简化版（对照 `features/skills_page.dart`、`jobs_page.dart`、`skill_use.dart`）；侧栏搜索只做了本地标题过滤，没有 `session/search` 全文搜索与 `shell/session_search_page.dart`；外观页对照表仍为 🟡；DSH UI 只移植了 8 种基础块。审计中发现的所有不一致都按第 4 节补齐。

## 3. 第一步：引擎升级到 DSH 0.2.2-rc.1

所有依赖新引擎的功能（定时任务授权与手动新建、新对话默认、提示词准入等）都在引擎升级完成后实现。

1. **锁文件**：从参考仓库复制 `runtime/locks/dsh-0.2.2-rc.1/`；与 `runtime/locks/dsh-0.2.1-rc.4/` 比较，列出新增 / 升级的包，尤其原生模块（sharp、koffi、node-pty、libvips 等）在 Alpine / musl / Node 24 下的兼容性。`runtime/ios/scripts/build-alpine-container.sh`、`runtime/build-ios-runtime.sh`（输入清单、`runtimeVersion`、`dshVersion`、launch argv）、`runtime/lib/rtbuild.py`、App 侧任何写死 `0.2.1-rc.4` 的地方、文档与 `THIRD_PARTY_NOTICES.md` 一并更新。旧锁目录在新版验证通过后删除。
2. **补丁**：参考仓库 `runtime/patches/` 有 57 个补丁，DSH Fan 只有 12 个。逐个阅读上游补丁与它针对的 0.2.2-rc.1 源文件，全部引入（对 iOS 不适用的必须写明原因，例如只服务 PRoot / Ubuntu 的部分）。引入时把标识按 DSH Fan 规则改名：`dsh-go(?![a-z])` → `dsh-fan`、`dshGo(?![a-z])` → `dshFan`、`DSH_GO(?![A-Z])` → `DSH_FAN`、`Dsh-Go-` → `Dsh-Fan-`，不要改到 `dsh-goal`。
3. **固定哈希**：用 `npm pack --registry=https://registry.npmmirror.com @deepseek-ai/<包>@0.2.2-rc.1` 下载补丁涉及的原始包，用锁文件中的 `integrity` 校验 tarball；先用**上游未改名的补丁和上游 `pins.json`** 在原始树上跑 `python3 -I runtime/lib/rtbuild.py patch-dsh --dsh-version 0.2.2-rc.1`，全部 `before` 哈希必须一致（证明拿到的是原件）；再用改名后的补丁 `--record` 记录 DSH Fan 的 0.2.2-rc.1 pins。确认补丁链可应用且幂等、打完的树中没有残留 `dsh-go` 标识。0.2.1-rc.4 / rc.2 的旧 pins 在删除旧锁时一并清理。
4. **桥与运行时组件**：逐文件对比参考仓库的 `runtime/bridge/dsh-go-bridge/`、`runtime/session-deletion/`、`runtime/boot/`、`runtime/media/`、`runtime/tests/` 与 DSH Fan 的 `runtime/bridge/dsh-fan-bridge/` 等，把上游 1.0.9–1.0.11 的改动（新路由、定时任务授权、插件挂载位、ui.json 读取等）按改名规则合入。`runtime/tests` 中上游新增的测试一并引入。
5. **迁移**：阅读 `docs/maintenance/dsh022-saved-preset-migration.md`、`schedule-remote-origin-contract.md`、`w17-*.md`，在 DSH Fan 中实现同等处理：运行时替换时 `/root` 之外被清空的提示（与上游 1.0.10 / 1.0.11 更新说明一致，在 App 内说明）、保存过旧预设时的迁移或明确报错与指引、升级前已存在的定时任务需要重新确认授权的提示。
6. **客户端协议**：对比参考仓库 `packages/dsh_client/lib/` 与 DSH Fan `apple/Modules/DSHClient/`，把 0.2.2 相关的协议变化（定时任务新规则格式与授权确认、新对话默认、提示词准入与排队恢复、会话事件准入、文件上传流式接口等）全部适配；远程主机仍是旧引擎时按上游的兼容处理（例如官方远程插件 0.6.2 不支持修改 / 立即运行定时任务时只读展示）。
7. **重建与验证**：`bash runtime/build-ios-runtime.sh` 重建；新运行时安装到模拟器后，旧数据（会话、设置、`/root`）保留；跑 runtime 测试并逐项比较基线（新增失败必须修，或写明与上游一致的原因）；store、chat、phone 冒烟 PASS；用真实模型完成一次对话、一次定时任务新建并确认、一次新对话默认模型生效。

## 4. 补齐功能（按步骤连续执行）

下列是本次审查已确认缺失或不完整的项目，是**最低要求**，不是全部；第 2 节清单发现的其他差异同样必须补齐。每一项都先完整读对应 Dart 源码（含 1.0.9–1.0.11 的改动），移植实现而不是外观；每个 Swift 文件头注释写明 Dart 来源。

### 步骤 1：聊天页

- **DSH UI 完整实现**：`ui/chat/dsh_ui/` 全部 26 个文件 —— 两种写法（`dsh_ui_dialect_card`、`dsh_ui_dialect_genui`）、全部块类型、图表、公式、配图、选择与控件状态、样式与色调、回复快捷按钮（`dsh_ui_reply*`）、骨架屏、绑定与作用域、插件块渲染（只渲染随 App 打包插件的产出）。现有 `VisualReplyView.swift` 只有 8 种基础块，以 Dart 为准重写。
- **Markdown 与渲染**：`ui/chat/render/` 全部 —— 数学公式（`markdown_math`、`math_syntax`）、Mermaid（`mermaid_preview`）、表格、代码块与高亮（`highlight_theme`）、diff、ANSI 色彩、流式修复（`stream_repair`）、图片。不能为此私自引入第三方依赖：优先按 Dart 的实现方式原生实现；确实需要依赖时按 AGENTS.md 先问用户，期间先做其他项。
- **聊天组件**：`ui/chat/widgets/` 全部 32 个文件逐一对照，已确认缺失：`plus_panel`（`+` 面板与工具位）、`auto_approve_pill`（本会话自动允许，常显且一点即关）、`permission_pill`、`thinking_pill`、`background_task_notice`、`turn_failure_text`、`artifact_card` 与会话产物、`image_actions`（存相册、分享、复制）、`notice_row`、`read_only_bar`、`quote_chip`（与 tray）、`command_row` / `command_result_text`、`tool_images`、`stream_motion` / `stream_pacer`（匀速吐字与淡入）、`whale_tail`、`secret_mask`（含 `ui/chat/secret_mask.dart`）。已有的 `approval_card`、`question_card`、`message_menu`、`message_actions`、`user_bubble`、`assistant_message`、`tool_row`、`chat_card`、`attachments` 逐条核对行为补齐。
- **输入框与顶栏（1.0.11 布局）**：顶栏只放标题，第二行放状态与工作区；输入框点入后展开为两行，换模型按钮在其中；生成中可插话；`composer.dart`、`chat_header.dart`、`model_sheet.dart`、`composer_toast.dart`、`empty_state.dart`、`empty_actions.dart`、`header_schedule*.dart` 全部对照。
- **附件与上传**：`chat_screen.dart` 的附件来源（相册、相机、文件），单文件 200 MiB、单条 400 MiB、走引擎流式上传；远程主机把文件上传到当前会话工作目录（1.0.10），旧主机按上游限额；`ui/files/` 全部对照。
- **计划审阅**：plan mode 下 `exit_plan_mode` 的审阅、批准、修改与退出流程（读 `ui/chat/` 与 `packages/dsh_client` 中相关实现）。
- **聊天内图像 / 视频生成**：`ui/chat/media/` 与 `lib/media/` 全部 —— 生成入口（胶囊 / 面板）、进度、媒体卡片（竖图、横图、窄屏）、查看器、不可用状态。
- **步骤详情与 diff**：`step_detail_page.dart`、`diff_page.dart` 与运行信息任务的产出衔接。

### 步骤 2：会话、导航与外部入口

- **全文会话搜索**：`shell/session_search_page.dart` 与 `session/search` 接口；跟随当前连接，不用旧连接结果。
- **会话详情与右侧面板**：`ui/session/` 全部（概览、产物、工作区文件、标签页）；1.0.9 的聊天区左滑打开右侧快捷入口面板（`shell/quick_panel.dart`，与已做的「快捷入口」设置联动），1.0.11 中开着对话时面板显示该对话的信息和插件位。
- **抽屉**：`shell/drawer/`、`sessions_drawer.dart`、`drawer_drag.dart` 对照；1.0.10 抽屉底部主机图标打开连接详情、本机图标打开引擎页。
- **导出与分享**：`features/session_export_page.dart`、`ui/share/` 中不依赖托管链接的部分（把回复 / 选中消息 / 整段对话导出为图片、文件、文字；导出时隐藏 `Authorization` 等凭据）。
- **链接与入口**：`links/page_links.dart`（`<scheme>://open/<page>` 打开每个设置页与功能页，内置指南技能里的链接可直接打开）、`links/app_links.dart`、`links/share_intake.dart`（分享扩展接收文本 / 图片 / 文件并路由到聊天）、`links/launcher_entries.dart` → 主屏幕快捷操作。
- **iPad 与横屏**：`shell/adaptive/` 与 `test/shell/adaptive`、`test/landscape` 金图 —— 平板与横屏的分栏布局。
- **壳层**：`shell/home_shell.dart`、`root_gate.dart`、`page_frame.dart`、`system_entry_host.dart`、`usage_upgrade_notice.dart` 对照。

### 步骤 3：功能页

- **Agent 预设编辑器**：`features/preset_editor/`（新建、编辑工具组合、保存与校验），现在只能读取和选择。
- **技能、后台任务、全部功能**：`skills_page.dart`、`skill_use.dart`、`jobs_page.dart`、`all_features_page.dart`、`feature_catalog.dart`、`feature_kit.dart`、`feature_widgets.dart`、`feature_format.dart` 全量对照（现有为简化版）。
- **定时任务**：`features/schedules_page.dart`、`schedule_editor/`（`cron.dart`、`time_zones.dart`、`schedule_pickers.dart`、`schedule_draft.dart`、`schedule_authorization.dart`）—— 手动新建与修改（用户自己操作不二次确认）、助手用工具新建 / 修改时的授权确认卡（展示完整指令、规则、时区、实际触发时间；拒绝或两分钟未确认不保存）、新规则格式显示「自定义」、只读兼容旧远程插件。
- **团队与子代理**：`ui/agents/` 全部，含团队任务板（实验性 agent team）与长历史分页。
- **ui.json 声明式界面配置**：`lib/ui_config/` 全部 12 个文件 —— 每台主机一份 `$DSH_HOME/dsh-fan/ui.json`，严格解析、逐项生效、错误定位、「恢复默认」记录、本机直接读 rootfs 并跟随变化、远程经 `workspaceFiles/read`；随 App 内置 `dsh-fan-ui` 技能（由参考仓库 `app/assets/skills/dsh-go-ui/` 改名改写，含 `schema.json` 与 `check.mjs`），让智能体能修改界面配置。它只是数据，不执行代码，符合 2.5.2。
- **内置技能**：`app/assets/skills/` 中 `dsh-go-guide`、`dsh-go-support` 改写为 `dsh-fan-guide`、`dsh-fan-support`（内容改为 DSH Fan 的 iOS 功能与页面链接），随 App 安装到引擎；`dsh-go-plugin`（插件开发）不随 App 内置。设置里「使用帮助 · 问 AI」接入。
- **cordis 引擎插件清单**：`ui/cordis/` 与 `engine_settings/goldens/plugin_inventory*` —— 只读查看引擎当前加载的插件与随 App 打包插件的设置，不提供安装 / 卸载。

### 步骤 4：引导、权限、安全模式、动效与其余模块

- **引导与权限**：`ui/onboarding/` 全部、`ui/access/` 全部（按功能选择要开的权限，逐项带去系统设置并回来确认）的 iOS 等价实现。
- **安全模式**：`ui/safe_mode/` 全部（进入原因、可疑文件、恢复路径、横幅）。
- **灵动动效**：`theme/motion.dart`、`page_transitions.dart`、`theme_reveal.dart`、`common/pressable.dart`、`fluid_bits.dart`、`smooth_size.dart`、`expand_reveal.dart`、`fade_in.dart` 以及 1.0.10 / 1.0.11 changelog 中的全部动效（按压弹簧、卡片展开成页面、跟手返回与弹层、思考扫光、输入框平滑长高、文字匀速淡入），在性能设置中可关闭，遵守系统「减弱动态效果」与低电量模式。
- **其余 lib 模块**：`lib/launch/`（启动动画与首帧）、`lib/wallpaper/`（壁纸与启动画面的全部能力，含图片、动图与 3 秒内短视频，在 iOS 上能做的部分全部实现）、`lib/notify/`、`lib/diagnostics/`、`lib/voice/`、`lib/performance/`、`lib/remote/`、`lib/runtime/`、`lib/phone/`、`lib/pets/`、`lib/state/`（32k 行，状态与持久化逻辑逐文件对照）全部进清单并补齐。

## 5. 视觉与行为验证

- 复用 `tooling/compare-golden.py`：第 2 节清单中每一张 `done` 的金图都必须有比对图（浅色与深色），写在 `~/.local/share/dsh-fan-compare/full-parity/`。比对前读金图测试文件确认尺寸、状态与夹具；用 DEBUG 夹具页面渲染，不连真实服务。标准：几何、颜色、图标、文字与数字格式一致，只允许字体族差异和已登记的平台差异。
- 为新增的状态逻辑写 Swift Testing，并把对应 Dart 测试（`app/test/**`、`packages/dsh_client/test/**`）中的关键断言移植过来；在清单的证据栏写测试名。
- 为聊天、会话、定时任务、ui.json、导出新增或扩展 `-dsh-feature-smoke` 用例，用真实模型跑通端到端流程。

## 6. 执行规则

- 按第 3 节、第 4 节步骤 1–4 的顺序连续执行，每完成一步：构建与单元测试通过 → 更新清单 → 只暂存明确路径、中文提交信息提交。不要在步骤之间等待用户。
- 只有 AGENTS.md 规定必须先问用户的事（新增第三方依赖、后台接口设计、签名 / 发布、替换品牌图标）才发消息询问；问的同时继续做其他不受影响的项，得到答复后回来补完。
- 不 push，由用户推送。

## 7. 最终统一验收（全部完成后）

1. `python3 tooling/parity-inventory.py --check` 通过：所有行为 `done` / `excluded` / `infra`，0 个缺失证据。
2. `ruby tooling/generate-apple-project.rb` 连续两次无差异；指定 SIM 的 Debug 与 `generic/platform=iOS` Release 构建零错误零警告。
3. `xcodebuild test` 全部通过。
4. 九项通用冒烟、phone 冒烟和本任务新增的冒烟全部 PASS（store 必须 PASS）；runtime 测试与开工基线逐项比较，无新增失败；媒体 header 测试 120/120。
5. 删除 `apple/Resources/PetsLocal/` 后构建运行正常。
6. 一次性汇报：每步提交号；清单统计（done / excluded / infra 数量，按目录汇总）；排除项与原因；引擎升级细节（补丁数、pins、运行时版本、迁移）；金图比对目录；验证结果。用清单重写 `docs/design/ios-native-parity.md`（不再保留与清单矛盾的旧状态），更新 `docs/changelog.md`（中英）、`README.md` / `README.en.md` 的功能描述与 `THIRD_PARTY_NOTICES.md`。

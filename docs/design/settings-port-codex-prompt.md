# 任务：把 DSH Go 的设置模块与宠物模块重构为 DSH Fan 的 SwiftUI 原生实现

> 给 Codex 的执行提示词。按阶段连续执行到全部完成，**中途不要停下来等用户验收**；每个阶段结束只做自检和提交，最终统一验收、统一汇报。

## 0. 背景与必读

- 工作仓库：`~/Documents/ChatGPT/dsh-fan`（DSH Fan，SwiftUI iOS App，代码在 `apple/`）。开工前完整阅读 `AGENTS.md`（硬规则优先于本文）、`README.md`、`docs/architecture.md`、`docs/design/ios-codex-tasks.md` 第 4 节（构建、测试、冒烟命令与固定模拟器）。
- 参考仓库（只读，不要改、不要提交进 dsh-fan）：`~/Documents/ChatGPT/dsh-go`，DSH Go 1.0.11 的 Flutter 源码。设置相关代码在 `app/lib/ui/settings/`、`app/lib/ui/engine_settings/`、`app/lib/ui/common/`、`app/lib/ui/theme/`；宠物在 `app/lib/pets/` 与 `app/lib/ui/pets/`。
- 视觉基准：`app/test/**/goldens/*.png`（真实字体渲染的金图）。每张金图的逻辑宽度、像素比、状态和数据夹具写在同目录对应的 `*_test.dart` 里（有的 390 宽 @2x，有的 360 宽 @1x / @3x），**比对前先读测试文件确认尺寸和状态**。
- 现有 iOS 实现：设置在 `apple/App/Design/SettingsKit.swift`、`apple/App/Design/Theme.swift`、`apple/App/Features/Settings/`；宠物在 `apple/App/Features/Pet/`；调试页面入口 `apple/App/Debug/DebugPageRegistry.swift`（`-dsh-screen <名字>`，就绪后写 `Documents/screen-ready.txt`）。

## 1. 核心要求：读实现，不是抄功能

每做一个页面或组件，先完整读对应 Dart 源码，再写 Swift。必须移植的是**实现**，包括：

- 组件树与布局：每个 padding、间距、行高、圆角、对齐、换行/折行规则（例如 `SettingsSegmentTile` 放不下时把分段控件挪到标题下方，`SettingsTile` 单行 52 / 双行 64，`SheetGroup` 行间 2pt 间隙而不是分隔线）。
- 设计令牌：颜色（`theme/semantic_colors.dart` 的 8 组 identity 色、textTertiary、warning/danger/success 及容器色，浅色和深色两套）、`theme/palette.dart` / `accent.dart` 的配色与中性色、`typography.dart` 字号与行高、`shapes.dart` 圆角、`glass.dart` 玻璃层级、`motion.dart` 动效时长与曲线。把这些令牌移到 Swift 的 `Theme.swift`，不要在页面里写魔法数。
- 状态与交互：数据从哪来、何时刷新、开关/分段的乐观更新与回滚、错误与空状态、触感反馈（`HapticFeedback.selectionClick` 对应 iOS `sensoryFeedback(.selection)`）、动画（展开收起、主题切换揭示 `theme_reveal.dart` 等）。
- 文案：中文以 Dart 的 l10n（`app/lib/l10n/`）为准；在 `Localizable.xcstrings` 用英文 key + 简体中文，名称把 DSH Go 换成 DSH Fan。
- 设置索引与搜索：`settings/index/spots.dart`、`spot_anchor.dart`、`search/` 是完整的「可搜索设置项 + 跳转高亮」机制，要原样实现，不是做一个静态列表。

每个 Swift 文件头部注释写明移植来源（Dart 文件路径），便于以后对照。Dart 代码中「因为 Flutter/安卓才需要」的部分（平台通道、MethodChannel、Material 主题怪癖）用 iOS 原生等价物实现并注释原因。

## 2. 视觉比对流程（每个页面都做，属于自检，不需要用户确认）

1. 新增 `tooling/compare-golden.py`：输入金图路径、模拟器截图路径和金图的逻辑宽度，把两图缩放到同一逻辑宽度后左右拼接（中间加分隔线和标签），并输出一张叠加差异图，结果写到 `~/.local/share/dsh-fan-compare/<阶段>/<页面>.png`（不进仓库）。
2. 为每个页面在 `DebugPageRegistry` 注册 `-dsh-screen` 名字，并支持与金图测试相同的夹具状态（例如已登录/仅远程、引擎运行中、语音模型下载中、宠物选中鲸娘），用 DEBUG 启动参数注入假数据，不连真实服务。长页面需要整页截图：在 DEBUG 下提供 `-dsh-screen-scroll <n>` 或渲染到 `ImageRenderer` 输出整页 PNG，保证能和长金图对齐。
3. 截图用固定模拟器 `SIM=51831DA4-9348-4053-A81C-54B3C995A73A`，浅色和深色各比一次（`xcrun simctl ui $SIM appearance light|dark`）。
4. 比对标准：布局几何（位置、尺寸、间距、圆角）、颜色、图标、文字内容与层级一致；字体族不同（金图是打包的无衬线体，iOS 用系统字体）造成的字形差异可以接受，但字号、字重、行高要一致。逐页记录剩余差异和原因，修到只剩字体差异或已记录的平台差异为止。

## 3. 已定决策

- **宠物美术**：代码按宠物包加载（Clawd on Desk 主题包格式，与 `pets/pet_pack.dart` 一致）。Deepy 与鲸娘都只是占位，美术不在 AGPL 授权内：
  - Deepy 已在 `apple/Resources/Pets/deepy-whale/`，保留。
  - 鲸娘从 `~/Documents/ChatGPT/dsh-go/app/assets/pets/whale-girl/` 复制到 `apple/Resources/PetsLocal/whale-girl/`，并把 `apple/Resources/PetsLocal/` 加入 `.gitignore`，**绝不提交**。生成器只在该目录存在时把它加进资源；目录不存在时构建和运行都必须正常（选择器里不出现鲸娘）。
  - 上架前会换成 DSH Fan 自己的角色，宠物系统不能写死任何一个角色。
- **安卓专属能力做 iOS 等价替代**：
  - 宠物「App 外显示」（悬浮窗 overlay）→ 实时活动 / 灵动岛上的宠物（项目已有 Live Activity，扩展它），设置页对应 `overlay_settings_tile.dart` 的位置与交互。
  - 「后台运行」厂商引导 `background_guide_page.dart` → iOS 后台说明页（后台挂起、本机引擎需前台、通知），保留页面结构。
  - 「系统权限」`system_access_page.dart` → iOS 权限总览（通知、日历、提醒事项、照片、麦克风、语音识别等，显示状态并可跳到系统设置）。
  - 桌面图标选择 `app_icon_picker.dart` → iOS 备用图标（`setAlternateIconName`）；启动画面 `launch_screen_section.dart` → App 内首帧启动动画（系统启动图不可自定义）；`icon_shortcut_sheet.dart` 的「图片快捷方式」iOS 不能实现，改为主屏幕快捷操作说明或不显示，并在差异表注明。
  - 手机操控里依赖 ADB / Root / Sui / 无障碍 / 勿扰权限的页面（`dnd_mode_page`、`a11y_restore_sheet`、`restricted_settings_guide` 等）iOS 不存在，不做；手机操控主页、确认模式、应用规则、操作记录按 iOS 现有能力（公开系统接口 + 快捷指令白名单）移植。
- **不做的模块（硬规则）**：社区、论坛、托管分享（`share_hosted`）、插件市场与插件安装（`plugins_screen`、市场相关）、求 Star、DS Bot（`bots`）、App 自更新（`update`）。设置首页对应行直接不出现。插件管理器保持禁用，`RuntimeEngine.storePatch` 不得移除。

## 4. 阶段（连续执行，不停顿）

每个阶段：读源码 → 移植 → 视觉比对自检 → 构建与单元测试通过 → 按 AGENTS.md 只暂存明确路径、中文提交信息提交。**不要在阶段之间等待用户。** 只有遇到 AGENTS.md 要求先问用户的事（新增第三方依赖、后台接口设计、签名/发布、品牌图标替换）才停下来，用一条消息说明需要什么。

### 阶段 1：设计令牌与通用组件

- 来源：`ui/theme/`（semantic_colors、palette、accent、typography、shapes、glass、motion、surfaces、backdrop）、`ui/settings/settings_widgets.dart`（SettingsMetrics、SettingsIcon、SettingsLineIcon、SettingsTile、SettingsSwitchTile、InfoRow、SettingsSection、SettingsSegmentTile）、`ui/common/`（app_sheet 的 SheetGroup / showAppSheet / groupTitleStyle、segmented_pill、overview_card 的 OverviewChevron 与概览卡、list_page_row、page_hero、search_capsule、status_chip、status_dot、capsule_chip、risk_notice、app_dialog、pressable、expand_reveal、smooth_size、brief_notice）、`ui/theme/app_theme.dart` 中开关等控件主题。
- 产出：重写 `SettingsKit.swift`（保持现有调用方可迁移，迁移所有现有设置页到新组件）、扩充 `Theme.swift` 令牌，深浅色都对。
- 自检金图：用阶段 2/3 的页面间接验证；本阶段至少比对 `settings/goldens/personalization_light.png`、`privacy_light.png` 的行与分组几何。

### 阶段 2：设置首页、设置索引与搜索

- 来源：`ui/settings/settings_screen.dart`、`settings/index/`（spots、spot_anchor、settings_pages）、`settings/search/`、`ui/account/`（首页顶部账号/余额卡）、`ui/engine/engine_status.dart`（首页引擎状态行）、`settings/quick_panel_items_sheet.dart`、`settings/usage_stats_section.dart`。
- 首页分组与行以金图为准：AI（模型、权限、个性化）、能力（手机操控、联网搜索、图像与视频）、外观（主题、对话字号分段、完成后收起过程、宠物）、通用（界面、语言分段、通知、语音输入、性能、后台运行、系统权限、隐私与分享）、主机（本机引擎、远程主机、引擎参数）、帮助与关于（使用帮助、诊断、关于 DSH Fan）。被硬规则排除的行（插件、社区）不出现。DSH Fan 已有但 DSH Go 没有的入口（工作区、定时任务、Agent 预设、回复偏好、DeepSeek 账号、模型服务商等）按 DSH Go 的信息架构归入相应分组或二级页，不要丢功能。
- 金图：`settings/goldens/settings_hub_full_*`、`settings_signed_in_*`、`settings_remote_only_*`、`en_settings_signed_in_light`、`settings/search/goldens/*`。

### 阶段 3：宠物模块

- 来源：`lib/pets/`（pet_pack、pet_prefs、pet_state、pet_mood、pet_signals、pet_sheets、pet_voice_dialog、pet_overlay_*、overlay_channel 仅作行为参考）、`lib/ui/pets/`（pet_settings_page、pet_picker、pet_stage、pet_perch、pet_sprite、pet_bubble、pet_menu、overlay_settings_tile）。
- 要完整实现情绪/信号状态机（智能体状态、用户交互、空闲、时间等如何驱动表情与气泡）、帧动画与逐帧时长、栖息位置（输入框上方）、拿起/拖动（held）、气泡、长按菜单、安静模式、大小三档、选择器卡片（含「不显示」）。与现有 `PetPack.swift` / `PetStage.swift` 对照，缺的补齐、不一致的以 Dart 为准。
- App 外显示 → 实时活动/灵动岛宠物（见第 3 节）。
- 金图：`pets/goldens/*`（pet_settings、en_pet_settings、pet_bubble、pet_composer_{deepy,girl}_{small,medium,large}、pet_held_*、pet_strip）、`pets/overlay/goldens/overlay_settings_*`。鲸娘相关金图在本地有 PetsLocal 时比对。

### 阶段 4：通用二级页

- 来源：`settings/appearance/`（appearance_page、tile_style_picker、wallpaper_section、app_icon_picker、launch_screen_section、icon_shortcut_sheet）、`lib/wallpaper/` 与 `ui/wallpaper/`、`settings/personalization_page.dart`、`interface_page.dart`、`reply_prefs_page.dart`、`notification_settings.dart`、`voice_settings_page.dart`、`performance_page.dart`、`privacy_page.dart`、`about_page.dart`、`font_licenses.dart`、`diagnostics_page.dart`、`ui/engine/diagnostics_export_card.dart`、`background_guide_page.dart`、`system_access_page.dart`、`ui/safe_mode/safe_mode_settings.dart`。
- 金图：`settings/goldens/` 中 appearance*、app_icon_picker、launch_section_*、wallpaper_section_*、icon_shortcut_sheet、personalization、interface、privacy、about、diagnostics、background_guide、voice_model_*；`notify/goldens/notify_settings*`、`background_net_*`；`performance/goldens/*`；`diagnostics/goldens/*`；`wallpaper/goldens/*`；`safe_mode/goldens/*`。
- 关于页注明 DSH Fan 参考了 DSH Go 与 iSH、AGPL-3.0 开源及仓库地址；第三方许可列表沿用现有 `Resources/Licenses`。

### 阶段 5：AI、引擎与手机操控相关页

- 来源：`ui/providers/`（providers_page、provider_detail/form/model、subscription_*、new_chat_defaults_card、model_context_page）、`ui/account/account_page.dart`、`ui/features/`（permission_page、agent_presets_page、preset_editor、all_features_page、schedules/skills/jobs 中设置相关部分）、`ui/engine/engine_screen.dart` 与 `log_view.dart`、`ui/engine_settings/`（engine_settings_hub、engine_settings_page、schema_form、schema_fields、field_row、field_sheets、sequence_field、bitset_field、schema_collapsed_groups、schema_documentation、namespace_copy、web_search_page、subagent_settings_page、runtime_settings_pages、general_settings_page）、`settings/media_settings_page.dart` 与 `settings/media/`、`ui/phone/`（phone_control_screen、app_rules_page、action_log_page、phone_widgets、hold_to_confirm、phone_disclosure_sheet）。
- 引擎参数的 schema 表单要按 Dart 的字段类型、折叠分组、编辑弹层、校验与保存流程实现，接 DSH Fan 现有的引擎设置接口（`EngineSettingsViews.swift` 现有逻辑保留语义）。媒体目录键已改名为 `dsh-fan/media/catalog`，读取时保留对旧键 `dsh-go/media/catalog` 的兜底。
- 金图：`engine_settings/goldens/*`、`providers/goldens/*`、`features/goldens/`（permission、agent_presets、preset_*、all_features）、`phone/goldens/` 中 phone_main、phone_off、phone_confirm_mode、phone_app_rules、phone_disclosure、phone_floating_bar（iOS 无悬浮条则记录差异），其余 dnd/a11y/unlock 等安卓专属不做。

## 5. 最终统一验收（全部阶段完成后才做）

1. `ruby tooling/generate-apple-project.rb` 连续两次无差异；指定 SIM 的 Debug 构建与 `generic/platform=iOS` Release 构建零错误零警告。
2. `xcodebuild test` 全部通过（为新状态逻辑补 Swift Testing：设置索引搜索、分段折行判断、宠物情绪状态机、偏好持久化）。
3. `python3 tooling/apple-smoke.py` 九项通用冒烟全部 PASS（store 必须 PASS）；按 `PhoneSmoke.swift` 说明跑 `-dsh-phone-smoke` PASS；`node --test runtime/tests/*.test.mjs` 与任务清单第 4 节「已接受的保留基线」逐项一致（开工前先跑一次记下失败用例名）。
4. 删除 PetsLocal 目录后重新构建运行仍正常。
5. 最终汇报一次，包含：每阶段提交号；页面对照表（Dart 源 → Swift 文件 → 金图 → 比对图路径 → 剩余差异及原因）；未实现项与原因（安卓专属/硬规则排除）；验证结果。更新 `docs/design/ios-native-parity.md` 与 `docs/changelog.md`（中英）。不要 push，由用户推送。

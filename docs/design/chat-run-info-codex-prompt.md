# 任务：把 DSH Go 聊天页的「运行信息」各层重构为 DSH Fan 的 SwiftUI 原生实现

> 给 Codex 的执行提示词。按阶段连续执行到全部完成，**中途不要停下来等用户验收**；每个阶段结束只做自检和提交，最后统一验收、统一汇报。

## 0. 背景与必读

- 工作仓库：`~/Documents/ChatGPT/dsh-fan`（DSH Fan，SwiftUI iOS App）。开工前完整阅读 `AGENTS.md`（硬规则优先于本文）、`docs/architecture.md`、`docs/design/ios-codex-tasks.md` 第 4 节（构建、测试、冒烟、固定模拟器 `SIM=51831DA4-9348-4053-A81C-54B3C995A73A`）、`docs/design/ios-native-parity.md` 中 T1 / T12 两行（现状）。
- 参考仓库（只读，不改、不提交）：`~/Documents/ChatGPT/dsh-go`（DSH Go 1.0.11，Flutter）。
- 与 `docs/design/settings-port-codex-prompt.md` 的关系：两份任务可以独立执行。若设置任务的阶段 1（设计令牌与通用组件）已经完成，复用它产出的 `Theme.swift` 令牌和组件；若还没做，本任务需要的令牌（颜色、字号、圆角、动效）也必须从 Dart 的 `ui/theme/` 移植到 `Theme.swift`，不要在页面里写魔法数，后续两边共用。

### 现状（缺什么）

DSH Fan 目前只有：右上角菜单里的整页「用量与运行信息」（`apple/App/Features/Chat/RunInsightsPage.swift`，数据来自 `apple/Modules/DSHClient/RunInsights.swift` 的 `RunFact` / `SessionMetrics`），以及输入框上方的待办 / 目标条（`TaskDock.swift`）。DSH Go 聊天页内的以下几层全部缺失：

1. 每条回复下方的脚注：`1 分 23 秒 · 5 步 · 80.1K tokens ›`，点开是本轮轨迹。
2. 回复上方的过程摘要：`已完成 · 7 次工具调用 · 1 条消息`（可折叠），以及同一步里连续工具调用折成一组的摘要（「执行 2 条命令 · 读了 3 个文件」）。
3. 回复下方的改动文件卡片：「改动了 2 个文件 +22 -3」、每个文件增删行数、「查看改动」→ diff 页。
4. 生成中输入框上方的活动条：当前在做什么（跑 / 读 / 改 / 搜 / 找……）+ 走动的计时，输入框占位文字变为「生成中 · 可直接插话」。
5. 输入框里的上下文圆环（22pt；60% 以下强调色、85% 以下警告色、以上危险色），点开是用量面板（底部弹层）：上下文占比与构成（系统 / 工具 / 消息）、本对话输入 / 输出 / 缓存命中率与轮数、DeepSeek 余额与低余额提醒。
6. 本轮轨迹的瀑布时间线：每段按真实开始时间排布，模型段拆成「等首字 + 输出」，进行中的段没有虚构的结束时间；单步详情页。
7. 花费估算：模型单价已知时显示「约 ¥0.03」/「不到 ¥0.01」，未知时不显示金额。

## 1. 核心要求：读实现，不是抄功能

每一层先完整读 Dart 源码再写 Swift，移植的是实现：数据如何从会话事件折叠出来、计时语义、文案与数字格式、布局几何、颜色、动画、交互（展开收起、点击进入、长按）、空状态与缺失数据的处理。每个 Swift 文件头部注释写明移植来源（Dart 路径）。

需要读的源码：

| 层 | Dart 源码 |
|---|---|
| 数据模型：轮次追踪、计时片段、用量合计 | `packages/dsh_client/lib/src/transcript.dart` 中 `TraceKind`、`TraceUsage`、`TraceSpan`、`TurnTrace` 及把持久事件折叠成 `TurnTrace` 的函数（约 650–1000 行）；`ChatTranscript` 中相关部分 |
| 文字与数字：时长、计时、金额、K/M 单位、活动动词、工具分组摘要 | `app/lib/ui/chat/run_info.dart`、`activity_copy.dart` |
| 过程摘要、工具分组、改动文件与 diff 对位 | `app/lib/ui/chat/turn_summary.dart`、`widgets/turn_process.dart`、`widgets/tool_row.dart`、`widgets/change_card.dart`、`diff_page.dart`、`render/diff_view.dart` |
| 回复脚注 | `app/lib/ui/chat/widgets/turn_footnote.dart`、`widgets/message_actions.dart`（脚注与复制 / 分享 / 更多同一行） |
| 活动条 | `app/lib/ui/chat/widgets/activity_strip.dart`、`widgets/live_clock.dart`、`run_info.dart` 的 `RunActivity` 及「生成中这一刻在做什么」的优先级（正在停止 > 等你 > 正在跑的工具 > 正在流的回复 / 推理 > 重试 > 等首字；压缩上下文时的内容） |
| 上下文圆环与用量面板 | `app/lib/ui/chat/usage_sheet.dart`、`composer.dart`（圆环位置与占位文字）、`balance_widgets.dart`、低余额提醒 |
| 本轮轨迹与单步详情 | `app/lib/ui/chat/trajectory_sheet.dart`、`step_detail_page.dart` |
| 在列表中的组装 | `app/lib/ui/chat/chat_rows.dart`、`chat_list.dart`、`chat_screen.dart`（各层插在哪里、何时出现 / 消失） |
| 底部条堆叠 | `app/lib/ui/chat/dock/`（`chat_dock.dart`、`dock_stack.dart`、`dock_pill.dart`、`todo_bar.dart`、`goal_bar.dart`）：活动条与现有待办 / 目标条如何上下堆叠、折叠展开 |
| 文案 | `app/lib/l10n/parts/chat_zh.arb`、`chat_en.arb` |

DSH Fan 侧要接上的代码：`TranscriptStore.swift`（已有 `runFacts`、会话持久事件）、`ControlStore.swift`（`projection.metrics`）、`RunInsights.swift`、`ChatRows.swift` / `ChatMessageList.swift`、`ChatComposerView.swift`、`TaskDock.swift`、`ToolPresenters.swift`，以及余额已有的 `account/getBalance`（`AccountAPI.swift`）。把 `TurnTrace` 折叠逻辑放进 `DSHClient` 模块（纯数据、可测试），界面放在 `App/Features/Chat/`。现有 `RunInsightsPage` 的内容并入新的用量面板与轨迹，菜单入口改为打开用量面板，不保留两套。

## 2. 已定规则

- 计时只用主机持久事件的时间戳，进行中的工作没有结束时间，不编造；缺失数据显示「未报告」而不是 0。
- 花费估算按 `run_info.dart` 的已知单价路由实现，单价未知就不显示金额（这替代 T12 里「不推算费用」的做法）。单价表集中在一处并注明来源和日期。
- 余额与低余额提醒只在本机 DeepSeek 账号可用时出现；远程主机 / 中继上没有余额就不显示该组。
- 「查看改动」的 diff 页只读；行号按 `turn_summary.dart` 的对位规则（旧文本在已知内容里唯一出现才编号）。
- 文案中文以 Dart l10n 为准，在 `Localizable.xcstrings` 用英文 key + 简体中文；「DSH Go」写成「DSH Fan」。
- iOS 可以做得到的交互一律照做（例如脚注点击打开轨迹、圆环点击打开面板、过程摘要折叠动画）；触感反馈用 `sensoryFeedback`。

## 3. 视觉比对（每层都做，属于自检）

- 金图：`app/test/chat/goldens/` 中 `run_running_*`、`run_finished_*`、`run_finished_open_*`、`run_trajectory_*`、`run_trajectory_live_*`、`run_step_model_*`、`run_step_tool_*`、`run_diff_*`、`changes_*`、`diff_page_*`、`activity_strip_levels_*`、`activity_strip_states_*`、`usage_sheet_*`、`low_balance_*`、`conversation_*`、`streaming_*`；`app/test/chat/dock/goldens/*`。每张金图的尺寸、状态、夹具写在同目录对应的 `*_test.dart`，比对前先读。
- 新增或复用 `tooling/compare-golden.py`（若设置任务已建则复用）：金图与模拟器截图缩放到同一逻辑宽度后左右拼接并输出差异图，结果写到 `~/.local/share/dsh-fan-compare/run-info/`（不进仓库）。
- 在 `DebugPageRegistry` 增加 DEBUG 夹具页面，按金图测试里的事件夹具构造一段会话（已完成、进行中、含工具组与改动、含审批等待、压缩中、低余额），不连真实服务即可渲染。浅色和深色都比。
- 标准：几何、颜色、图标、文字与数字格式一致；字体族差异可接受，字号 / 字重 / 行高要一致。逐层记录剩余差异和原因。

## 4. 阶段（连续执行，不停顿）

每阶段：读源码 → 移植 → 视觉比对自检 → 构建与单元测试通过 → 只暂存明确路径、中文提交信息提交。只有遇到 AGENTS.md 要求先问用户的事才停下。

1. **数据层**：在 `DSHClient` 实现 `TurnTrace` / `TraceSpan` / `TraceUsage` 折叠、工具分组摘要计数（文件按路径去重、失败 / 被拒 / 取消不计、沙箱拦截后重试只算一次）、每轮改动汇总与 diff 对位、时长 / 计时 / K-M / 金额格式化、单价表。用 Swift Testing 覆盖 Dart 测试里的同类用例（读 `app/test/chat/` 与 `packages/dsh_client/test/` 中相应测试，把关键断言移植过来）。
2. **回合内各层**：过程摘要（折叠 / 展开）、工具分组行、回复脚注（与复制 / 分享 / 更多同行）、改动文件卡片、diff 页。
3. **生成中的底部**：活动条（状态优先级、动词、走动计时、压缩中）、与待办 / 目标条的堆叠与折叠（按 `dock/`）、输入框「生成中 · 可直接插话」占位与停止键。
4. **用量面板与轨迹**：输入框上下文圆环、用量面板（上下文构成、本对话统计、余额与低余额提醒）、本轮轨迹瀑布时间线（含进行中实时更新）、单步详情页；替换现有 `RunInsightsPage` 并调整菜单入口。

## 5. 最终统一验收（全部阶段完成后）

1. `ruby tooling/generate-apple-project.rb` 连续两次无差异；指定 SIM 的 Debug 与 `generic/platform=iOS` Release 构建零错误零警告。
2. `xcodebuild test` 全部通过（含新增数据层测试）。
3. `python3 tooling/apple-smoke.py` 九项通用冒烟全部 PASS（store 必须 PASS）；`-dsh-feature-smoke t12` 更新为检查新的数据层（真实模型一轮：脚注 tokens 与 `sessionStats` 一致、轨迹片段闭合、圆环比例与 `contextPressure` 一致）并 PASS；chat 冒烟 PASS。
4. 用真实模型在模拟器跑一轮带工具调用和文件改动的对话，截图：生成中（活动条 + 待办条）、完成后（过程摘要 + 脚注 + 改动卡片）、用量面板、轨迹，与金图并排附在汇报里。
5. 最终汇报一次：每阶段提交号；层级对照表（Dart 源 → Swift 文件 → 金图 → 比对图路径 → 剩余差异及原因）；验证结果。更新 `docs/design/ios-native-parity.md`（T12 行）与 `docs/changelog.md`（中英）。不要 push，由用户推送。

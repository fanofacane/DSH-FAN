# 更新日志 · Changelog

每个版本先中文、后英文。发版时把对应版本的正文（不含版本标题）作为 Release 正文，见 `docs/release.md`。

DSH Fan 是参考 DSH Go 与 iSH 独立开发的新项目，版本从这里开始记录。DSH Go 自己的安卓版更新记录（0.9.0–1.0.8）见上游仓库 https://github.com/ccch1mneyyy/dsh-go 。

DSH Fan is a new project built after studying DSH Go and iSH; its history starts here. DSH Go's own Android release notes (0.9.0–1.0.8) live in the upstream repository https://github.com/ccch1mneyyy/dsh-go .

## 未发布 · 2026-11-05

- 项目命名为 DSH Fan，迁入新仓库 https://github.com/fanofacane/dsh-fan ，继续以 AGPL-3.0-or-later 开源；README 说明参考了 DSH Go 与 iSH，并写明后续方向：手机端助手与可交互的情绪伴侣。
- The project is now DSH Fan, maintained at https://github.com/fanofacane/dsh-fan and still open source under AGPL-3.0-or-later. The README credits DSH Go and iSH and sets the direction: a phone assistant and an interactive emotional companion.

- 显示名改为 DSH Fan：主屏幕、分享与小组件扩展、关于页、侧栏标题、引导页、小组件和通知默认标题。端口 3080 被占用时，提示改为说明可能是旧版 DSH 并给出处理办法。
- The display name is now DSH Fan: the Home Screen, the share and widget extensions, About, the sidebar title, onboarding, widgets and the default notification title. When port 3080 is taken, the message now names a likely culprit (an older DSH app) and says what to do.

- 内置引擎桥接改名：`dsh-go-bridge` → `dsh-fan-bridge`，客体路径 `/opt/dsh-go` → `/opt/dsh-fan`，接口 `/dsh-go/v1` → `/dsh-fan/v1`，媒体目录键 `dsh-fan/media/catalog`；引擎补丁重新固定哈希，运行时重新构建。旧版手机说明标记会被自动清理；远程主机上的旧媒体目录键仍可读取。
- Renamed the bundled engine bridge: `dsh-go-bridge` → `dsh-fan-bridge`, guest path `/opt/dsh-go` → `/opt/dsh-fan`, routes `/dsh-go/v1` → `/dsh-fan/v1`, media catalog key `dsh-fan/media/catalog`. Engine patch pins were re-recorded and the runtime rebuilt. Old phone-instruction markers are cleaned up automatically, and remote hosts' old media catalog key is still read.

- 修复手机控制失效：本机引擎进入安全模式后再也回不到正常模式，安全模式不挂载手机工具，模型因此看不到 `mcp__phone__*`。引擎页和手机控制页现在会提示安全模式，并提供「以正常模式启动」。
- Fixed phone control: once the local engine entered safe mode it never returned to normal mode, and safe mode leaves out the phone tools, so the model could not see `mcp__phone__*`. The Engine page and Phone control page now show when safe mode is on and offer "Start normally".

- 当前功能：流式对话、会话管理、本机 DSH 引擎（iSH）、SSH 与自建 DSH Remote 远程连接、手机系统操作、快捷指令、小组件、实时活动与 Deepy 桌宠。
- Current features: streaming chat, session management, the local DSH engine (iSH), SSH and self-hosted DSH Remote connections, phone actions, Shortcuts, widgets, Live Activities and the Deepy desktop pet.

# AGENTS.md

DSH Fan 是独立的 iOS 原生项目（参考学习了 DSH Go 与 iSH，不是 DSH Go 的 iOS 移植），唯一客户端为 `apple/` 下的 SwiftUI App，维护仓库 https://github.com/fanofacane/dsh-fan 。改动前先读 [README](README.md)（仓库地图与开发约定）、[docs/architecture.md](docs/architecture.md) 和 [iOS 任务清单](docs/design/ios-codex-tasks.md)。作为参考的 DSH Go Flutter / 安卓实现见上游 DSH Go 仓库（https://github.com/ccch1mneyyy/dsh-go）。

## 仓库布局与验证

日常 iOS 开发先看 `apple/App/` 和 `apple/Modules/`。根目录与 apple/ 子目录的说明都在 [README](README.md#仓库地图)。

- `apple/App/`：Core（入口与通用状态）、Design、Features（按功能）、Debug（仅调试）；`apple/Modules/`：DSHClient、DSHRemote、DSHRuntime、DSHPhone 四个框架，依赖不能反向指向 App。
- `apple/Modules/DSHRuntime/Native/`：iSH 原生桥，由 `tooling/build-ish.sh` 编入静态框架；`apple/Extensions/`：Widgets、Share 及与 App 共用的 Shared 类型。
- `apple/Resources/`：App 自有资源与许可（手机工具目录契约在 `Phone/phone-ios-tools.json`）；`apple/Tests/`：正式 Swift Testing 契约与状态测试。
- `runtime/ios/`：正式 Alpine 配方、guest 输入及唯一 iSH 补丁链；`runtime/bridge/`、`runtime/patches/`、`runtime/locks/`、`runtime/media/`：共享引擎输入；`runtime/lib/rtbuild.py` 仅保留固定 DSH 补丁工具。
- `tooling/`：iSH / Xcode 工程生成、模型夹具和冒烟。
- `docs/`：架构、任务清单、功能对照表与更新记录；旧端设计、用户指南和插件开发资料已删除，见旧仓库历史（未迁入 dsh-fan）。
- `.agents/skills/`：维护者技能。运行时归档、Vendor 框架和本机缓存不提交。

常用检查以任务清单第 4 节为准。实际执行并记录 `ruby tooling/generate-apple-project.rb`、指定设备的 `xcodebuild build` / `xcodebuild test` 正式测试目标和 `node --test runtime/tests/*.test.mjs`；冒烟先启动模型夹具，等待 JSON 最终 result，不能把 RUNNING 或跳过写成通过。

## 硬规则

### 不接受外部 PR（最高优先级）

- 本仓库暂不接受任何外部 Pull Request（代码、文档、配置、模板都不收）。
- 禁止用 merge、rebase、cherry-pick、GitHub API 或网页把外部 PR 提交带进 main。
- 除非用户在当次对话明确要求，不替用户创建 PR，也不因为 issue 有实现就自动包装 PR。
- 外部 PR 关闭并回复“暂不接受外部 PR，请改用 issue 提供建议”；发送回复仍须当前会话授权。

### 源码、生成物与补丁

- 不手改 `apple/DSH.xcodeproj`，改 `tooling/generate-apple-project.rb` 后重新生成；不提交 Vendor、运行时归档或构建缓存。
- 界面用英文 key，在对应 `Localizable.xcstrings` 同步简体中文；权限说明维护 `InfoPlist.xcstrings`，key 按字母排序。
- `runtime/patches/` 补丁与 `pins.json` 保持同步，不手改补丁覆盖的上游产物。只使用现有 iSH 补丁链，不修改外部源码克隆。
- README 中英文同步。历史文档明确标记，不把旧端功能写成 iOS 已实现。

### 行为、分层与上架约束

- 以最小必要改动防止回归。协议变化同时检查客户端、桥、传输和调用方的兼容性；模块不得依赖 App。
- 删除会话、权限、凭据等操作以主机实际回答为准；未知不能当作不支持，失败保留稳定错误码，不静默吞掉。
- App 不下载、安装或更新可执行代码；不做插件安装 / 市场 / 包管理入口。每次启动禁用插件管理器的 `RuntimeEngine.storePatch` 必须保留，store 冒烟必须通过；新增系统 API 同步 `PrivacyInfo.xcprivacy`。
- 方案 A 仅允许随 App 打包的插件。后台接口设计前先问用户；当前插件门控只做本地全部关闭，不接后台、不做界面。
- 不添加社区、论坛、原作者托管分享、DS Bot、Star 引导或默认托管中继入口；远程服务器由用户自建。

### 凭据与隐私

- 不记录、回显、持久化或提交完整 API key、token、Cookie、密码和登录态；不向日志、测试输出和诊断文件写凭据。
- 诊断外发前人工检查，自动脱敏不能当保证。不提交个人对话、设备配置、设备序列号和私有运维资料。

### Git 安全

- 只暂存明确路径，不用 `git add .` / `git add -A`。不提交 `.DS_Store` 或 `docs/design/ios-native-migration.md`，不覆盖用户的无关改动。
- 未经当次会话要求，不 commit、push、打 tag、发布或重写共享历史。不 force push main；获准重写后重建受影响分支与 PR。

### 模拟器与真机

- 默认设备固定为 `SIM=51831DA4-9348-4053-A81C-54B3C995A73A`（iPhone 18 Pro）。所有 simctl 命令显式指定 SIM，启动后用 ps 核对设备和参数。
- 不在 WOO UI Review 安装或运行 DSH，也不关闭它。所有模拟器共用 Mac 的 `127.0.0.1:3080`，不同时运行两份 DSH。
- 手机系统操作、签名、通知、后台期限与安装更新须真机验证；模拟器结果不能替代。缺少条件时写“未运行”及原因。

## 审查与流程

审查只报告本次改动引入且有触发条件和实际影响的问题，优先最小修复；关注竞态、生命周期、资源泄漏、兼容性、无效抽象和无关变更，不推测贡献者动机。

内部 PR 用 `.agents/skills/pr`；具体改动审查用 `.agents/skills/review`；缺陷记录用 bug；安全检查用 vuln-check；广泛审计用 audit。`CLAUDE.md` 是本文件的符号链接，只编辑真身。

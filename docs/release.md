# iOS 构建与发布

当前只维护 SwiftUI iOS 版。DSH Go 的 APK 发布、内测通道与差分更新流程不属于本项目；不向 App 添加自更新或联网安装代码的入口。

1. 按 README 准备固定 iSH 框架和 `runtime/build-ios-runtime.sh` 产物，运行工程生成器。
2. 更新生成器中的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`；不手改工程。变更日志中英文同步。
3. 执行 README 开发约定与 iOS 任务清单要求的构建、单元测试、完整冒烟；记录实际设备、版本和未验证范围。检查隐私清单与随包许可证。
4. 真机验证签名、权限、后台限制、系统集成与安装更新。模拟器通过不能替代。
5. 用户明确授权后，使用自己的 Apple 签名与 App Store Connect / TestFlight 发布；不借用他人 Apple ID，不自行创建发行、tag 或上传。

每次启动禁用插件管理器的补丁必须保留；store 冒烟须证明查询 / 安装接口报错。未来随 App 打包的插件及开关须在提审资料中说明；后台接口设计仍需先问用户。

模拟器只使用 `51831DA4-9348-4053-A81C-54B3C995A73A`，不操作 WOO UI Review；所有模拟器共用 Mac 的回环端口。完整命令见 `docs/design/ios-codex-tasks.md` 第 4 节。

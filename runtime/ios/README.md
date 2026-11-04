# iOS 引擎构建输入

正式入口为仓库根目录的 `bash tooling/build-ish.sh` 与 `bash runtime/build-ios-runtime.sh`。日常界面开发无需修改这里。

iSH 构建需要 Xcode、Meson、Ninja、CMake，以及能生成 Linux AArch64 ELF 的 LLVM / LLD。使用已安装 `ziglang` 的 Python 工具环境时，先把该环境的 bin 放到 PATH，再以 `ISH_VDSO_COMPILER=zig bash tooling/build-ish.sh` 构建客体 VDSO；iOS 宿主代码仍使用 Xcode 的 Apple Clang。

| 目录 | 用途 |
|---|---|
| `scripts/` | 固定 Alpine / Node 与原生模块的编译、校验和生产 rootfs 组装 |
| `guest/` | rootfs 使用的 allocator 与 polyfill，以及构建时运行的 allocator / 原生模块校验；测试 observer 和测试程序不进入生产包 |
| `patches/` | iSH 唯一补丁链，`series.json` 记录固定上游版本、补丁及输入 / 输出散列；只修改隔离导出，不修改外部克隆 |

配方从早期实验探针迁移，生产分支与版本固定保持不变。正式入口选择 Node 24 与 production；Node 22 APK 仍用于构建工具和签名校验，不是 App 最终使用的 Node。下载、编译缓存和归档位于 `runtime/.work/`、`runtime/out/` 与 `apple/.build/`，不提交到 git。运行时软件包的锁与 DSH 补丁继续分别由 `runtime/locks/`、`runtime/patches/pins.json` 管理。

独立 RuntimeProbe App、它的资源 staging 和硬件 oracle 已删除；需要追溯实验时查看 旧仓库历史（未迁入 dsh-fan）。正式 App 的 iSH、OpenMinis、libarchive、xz 许可继续在 `apple/Resources/Licenses/`，来源说明见 [第三方声明](../../THIRD_PARTY_NOTICES.md)。

## 共享输入与测试支持

`runtime/lib/rtbuild.py` 只保留 `patch-dsh` 及其严格解析 / 应用函数；原安卓 Debian、ELF、PRoot、JNI 组包逻辑和 Ubuntu 锁已删除。`runtime/patches/`、`session-deletion/`、`bridge/`、npm `locks/`、`media/` 仍是生产输入或共享协议 / 测试资料，保留。`direct/paths.mjs` 与 `boot/boot-cache.mjs` 被现有跨运行时基线测试直接使用，作为测试支持保留，不随 iOS 归档分发；其余仅服务旧安卓 Direct / PRoot 启动的文件已删除。Linux Host 回归脚本检查的引擎 / 桥协议仍共享，不按文件中的 Android 历史字样删除。

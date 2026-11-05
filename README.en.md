# DSH Fan

[中文](README.md) · [Architecture](docs/architecture.md) · [Task list and hard rules](docs/design/ios-codex-tasks.md) · [Feature and validation status](docs/design/ios-native-parity.md)

DSH Fan is a new native iOS (SwiftUI) project. It runs the bundled DeepSeek Harness (DSH) engine on an iPhone / iPad, or connects to your own computer / server through SSH or a self-hosted DSH Remote relay.

**Direction**: the features are still basic. Development will head two ways:

- **Phone assistant**: get things done on your phone through public iOS capabilities (calendar, reminders, alarms, Shortcuts, notifications and more).
- **Interactive emotional companion**: starting from the desktop pet, an interactive character that keeps you company and responds to how you feel.

## Repository map

**Everyday iOS development only needs `apple/App/` and `apple/Modules/`.**

| Directory / file | Purpose | When to touch it |
|---|---|---|
| `apple/` | The iOS app: UI, state, four modules, system extensions, resources and tests (see below) | Everyday development |
| `runtime/` | Build recipe for the bundled engine (Alpine + Node + DSH), engine patches and the HTTP bridge; iOS recipe notes in [runtime/ios](runtime/ios/README.md) | Changing the engine version, launch or packaging |
| `tooling/` | Project generator, iSH framework build, smoke tests and the model fixture | Changing the project or developer tools |
| `docs/` | Architecture, task list, feature matrix, changelog | Design background and completion records |
| `.agents/` | Review skills for coding agents | Adjusting automated checks |
| `AGENTS.md`, `CLAUDE.md` | Working rules that Codex / Claude Code read on every start | Changing collaboration rules |
| `LICENSE`, `THIRD_PARTY_NOTICES.md` | Project license; licenses of third-party components and assets (required to ship) | Adding dependencies or assets |

### apple/

| Directory | Purpose |
|---|---|
| `App/` | SwiftUI entry and composition (`Core/`), design components (`Design/`), feature UI and stores (`Features/`), DEBUG tools (`Debug/`) |
| `Modules/` | Four frameworks: DSHClient (protocol), DSHRemote (SSH / relay), DSHRuntime (bundled engine), DSHPhone (phone control); none depends on the app |
| `Modules/DSHRuntime/Native/` | Objective-C bridge to iSH; compiled into `ish.xcframework` by `tooling/build-ish.sh`, rebuild after changes |
| `Extensions/` | Widgets (`Widgets/`), share extension (`Share/`) and types shared with the app (`Shared/`) |
| `Resources/` | Fonts, images, the Deepy pet, phone-control resources (including the tool catalog contract `Phone/phone-ios-tools.json`), third-party license texts |
| `Tests/` | Swift Testing: protocol contracts, stores and dependency boundaries |
| `DSH.xcodeproj/` | Generator output, **do not edit by hand**; change `tooling/generate-apple-project.rb` |
| `Vendor/`, `.build/` | Locally built iSH framework and caches, not committed |

## Features

- Streaming chat, Markdown, image attachments, dictation, branching, retrying and editing messages.
- Session search, renaming, deletion where supported by the host, pinning / archiving, workspaces and file previews.
- Todos and goals, tool approvals and questions, agent presets, subtasks, usage and run details.
- DeepSeek API keys, custom model providers, and local DeepSeek account authorization; real account callback verification is still pending.
- Schedules, local notifications, reply preferences, appearance, language, and diagnostic export after manual review.
- Phone actions through public Apple APIs, Shortcuts, widgets, Live Activities and the Deepy pet.

See the [feature matrix](docs/design/ios-native-parity.md) for exact coverage and limitations. Terminal and direct WebRTC are deferred. The original author's community, marketplace, hosted sharing and servers have been removed and are not connected. Plugin installation is cancelled and the plugin manager is disabled on every launch. Future plugins must ship with the app (plan A); the backend toggle API has not been designed.

iOS may suspend the app shortly after it enters the background. Local tasks and schedules require a running engine. A remote host can keep working, but a suspended app cannot receive live events and has no server push notifications.

## Build

Use an Apple silicon Mac, Xcode with an iOS SDK and the iPhone 18 Pro simulator, Ruby's `xcodeproj` gem, plus Meson, CMake, Ninja, Docker and LLVM / LLD or Zig capable of producing Linux AArch64 ELF for the iSH / Alpine runtime (with Zig, set `ISH_VDSO_COMPILER=zig`). The deployment target is iOS 17. Configure device signing yourself.

```bash
bash tooling/build-ish.sh
bash runtime/build-ios-runtime.sh
ruby tooling/generate-apple-project.rb
SIM=51831DA4-9348-4053-A81C-54B3C995A73A
xcodebuild -project apple/DSH.xcodeproj -scheme DSH \
  -destination "platform=iOS Simulator,id=$SIM" build
```

Tests, the Release build, smoke tests and test baselines are described in [section 4 of the task list](docs/design/ios-codex-tasks.md#4-构建与验证). Always pass the simulator ID above; all simulators share the Mac's `127.0.0.1:3080`, so never run two copies of DSH. Do not install or run DSH on the WOO UI Review simulator, and do not shut it down.

## Development rules

- External pull requests are not accepted for now; please use [Issues](https://github.com/fanofacane/dsh-fan/issues/new/choose).
- The Xcode project is generated; keep runtime patches in sync with `runtime/patches/pins.json`.
- Keep each change to one problem; avoid unrelated formatting, dependency bumps and abstractions. Protocol changes must check callers and compatibility.
- UI strings use English keys with Simplified Chinese in `Localizable.xcstrings`; permission texts are in `InfoPlist.xcstrings`. Keep both READMEs in sync.
- The app never downloads, installs or updates executable code: do not restore plugin installation / marketplace entries or remove the launch patch that disables the plugin manager. Update the privacy manifest with new system APIs.
- Keep the source, version, copyright and license of third-party content; moving a file does not change its license.
- Changes to phone system actions, signing, notifications or background limits need device testing; simulator results are not a substitute.
- Stage explicit paths only; never commit build caches, personal configuration, keys, cookies, real conversations or device data. Review diagnostic bundles before sharing them.

## Security

Do not post vulnerability details, keys or real user data in public issues. Report privately through the repository's [Security Advisories](https://github.com/fanofacane/dsh-fan/security/advisories); if that is unavailable, open an issue asking only how to contact the maintainer privately. Include the app version, iOS version, connection type (local / SSH / DSH Remote), impact and a minimal reproduction using fictional content or test accounts. Only reproduce on devices, accounts and environments you are authorized to use.

## Acknowledgements

DSH Fan learned from and builds on these projects. Thanks to their authors and contributors:

- [DSH Go](https://github.com/ccch1mneyyy/dsh-go) (AGPL-3.0): an Android client for DeepSeek Harness. This project's visual style, engine patches and parts of the design come from studying it; the bundled engine's bridge plugin `dsh-fan-bridge` (`/opt/dsh-fan`, `/dsh-fan/v1`) is renamed from DSH Go's `dsh-go-bridge`.
- [iSH](https://github.com/ish-app/ish) (GPL-3.0) and [OpenMinis/ish-arm64](https://github.com/OpenMinis/ish-arm64): the kernel and interpreter that run Linux userland on iOS.
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (MIT): the bundled agent engine.

Full third-party licenses and asset conditions are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

This project keeps a copyleft license: source is released under AGPL-3.0-or-later (see [LICENSE](LICENSE)). If you distribute a modified version or offer it to others over a network, you must publish the corresponding source under the same license. iSH and other third-party components keep their own licenses, and brand / mascot assets have separate conditions; both are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

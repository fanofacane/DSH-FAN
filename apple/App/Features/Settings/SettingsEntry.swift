// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/{settings_screen,index/spots,index/settings_pages}.dart.
import SwiftUI

struct SettingsContext {
    var isRemote = false
    var hostName: String?
    var savedHostCount = 0
    var presetName: String?
    var presetRisk = false
    var personalPreferencesSet: Bool?
    var phoneEnabled = false
    var petName: String?
    var appearanceName: String?
    var notificationsEnabled = false
    var version: String?
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case ai = "AI"
    case abilities = "Capabilities"
    case appearance = "Appearance"
    case general = "General"
    case hosts = "Hosts"
    case help = "Help and about"

    var id: Self { self }
    var tone: TileTone {
        switch self {
        case .ai: .identity(0)
        case .abilities: .identity(4)
        case .appearance: .identity(1)
        case .general: .identity(5)
        case .hosts: .identity(6)
        case .help: .identity(7)
        }
    }
}

@MainActor struct SettingsEntry: Identifiable {
    let id: String
    let key: String
    let glyph: DshGlyph?
    let group: SettingsSection?
    let parent: String?
    let localOnly: Bool
    let terms: SearchTerms
    let value: (SettingsContext) -> String?
    let destination: () -> AnyView

    var title: LocalizedStringKey { LocalizedStringKey(key) }

    init<Destination: View>(_ id: String, _ key: String, glyph: DshGlyph? = nil,
                           group: SettingsSection? = nil, parent: String? = nil, localOnly: Bool = false,
                           terms: SearchTerms = SearchTerms(), value: @escaping (SettingsContext) -> String? = { _ in nil },
                           @ViewBuilder destination: @escaping () -> Destination) {
        self.id = id
        self.key = key
        self.glyph = glyph
        self.group = group
        self.parent = parent
        self.localOnly = localOnly
        self.terms = terms
        self.value = value
        self.destination = { AnyView(destination()) }
    }
}

@MainActor enum SettingsRegistry {
    static let entries: [SettingsEntry] = [
        SettingsEntry("providers", "Models", glyph: AppIcon.providers, group: .ai,
                      terms: .init("model providers,providers,switch model,OpenRouter,ChatGPT,Claude", "模型渠道,渠道,供应商,换模型,OpenRouter,ChatGPT,Claude", bonus: 2)) {
            ProviderSettingsPage()
        },
        SettingsEntry("permissions", "Permissions", glyph: AppIcon.permissions, group: .ai,
                      terms: .init("permissions,approval,don't ask,read only,full access,auto-run commands", "别问我,确认,审批,自动允许,只读,完全权限,自动执行命令", bonus: 2),
                      value: { $0.presetName }) { PermissionSettingsPage() },
        SettingsEntry("personalization", "Personalization", glyph: AppIcon.profile, group: .ai,
                      terms: .init("preferences,style", "偏好,风格,习惯"), value: {
            $0.personalPreferencesSet.map { $0 ? String(localized: "Set") : String(localized: "Not set") }
        }) { PersonalizationPage() },
        SettingsEntry("phone", "Phone control", glyph: AppIcon.phoneControl, group: .abilities,
                      terms: .init("automation,control phone", "操作手机,代操作", bonus: 2),
                      value: { $0.phoneEnabled ? String(localized: "On") : String(localized: "Off") }) { PhoneSettingsView() },
        SettingsEntry("web-search", "Web search", glyph: AppIcon.webSearch, group: .abilities,
                      terms: .init("search,internet,browse,api key", "搜索,上网,联网,API Key")) {
            CapabilitySettingsPage(kind: .search)
        },
        SettingsEntry("media", "Images and video", glyph: AppIcon.generateMedia, group: .abilities,
                      terms: .init("image generation,text to image,video generation,AI art,generate images,generate video",
                                   "生图,画图,文生图,视频生成,AI 绘画,生成图片,生成视频")) {
            CapabilitySettingsPage(kind: .media)
        },
        SettingsEntry("appearance", "Theme", glyph: AppIcon.theme, group: .appearance,
                      terms: .init("appearance,colors,colours,accent,icons", "外观,配色,颜色,主题色,强调色,图标", bonus: 2),
                      value: { $0.appearanceName }) { AppearanceSettingsPage() },
        SettingsEntry("pet", "Pet", glyph: AppIcon.pet, group: .appearance,
                      terms: .init("pets,companion,whale,live activity", "宠物,小鲸,桌宠,鲸鱼,灵动岛"),
                      value: { $0.petName ?? String(localized: "Off") }) { PetSettingsPage() },
        SettingsEntry("interface", "Interface", glyph: AppIcon.swap, group: .general,
                      terms: .init("native,interface,general", "原生,界面,通用设置"),
                      value: { _ in String(localized: "Native") }) { InterfaceSettingsPage() },
        SettingsEntry("notifications", "Notifications", glyph: .bell, group: .general,
                      terms: .init("alerts,push,banner,sound", "提醒,推送,横幅,消息,铃声"),
                      value: { $0.notificationsEnabled ? String(localized: "On") : String(localized: "Off") }) {
            TaskNotificationSettingsPage()
        },
        SettingsEntry("voice", "Voice input", glyph: AppIcon.voice, group: .general,
                      terms: .init("speech recognition,dictation,microphone,mic,voice", "语音识别,麦克风,听写,说话,语音")) {
            VoiceSettingsPage()
        },
        SettingsEntry("performance", "Performance", glyph: .lightning, group: .general,
                      terms: .init("battery,smooth,lag,lite,full,speed", "省电,流畅,卡顿,发热,轻量,完整")) { PerformanceSettingsPage() },
        SettingsEntry("background", "Background activity", glyph: AppIcon.keepAlive, group: .general,
                      terms: .init("keep alive,background activity,autostart,killed", "后台保活,保活,后台,自启动,被杀,杀后台,省电")) {
            BackgroundSettingsPage()
        },
        SettingsEntry("system-access", "System permissions", glyph: AppIcon.systemAccess, group: .general,
                      terms: .init("permissions,grant,microphone,notification permission", "权限一览,授权,麦克风,通知权限,补开权限")) {
            SystemAccessPage()
        },
        SettingsEntry("privacy", "Privacy and sharing", glyph: AppIcon.privacy, group: .general,
                      terms: .init("privacy,data,logs,sharing,statistics", "隐私,数据,日志,分享,统计")) { PrivacySettingsPage() },
        SettingsEntry("engine", "Local engine", glyph: AppIcon.engine, group: .hosts,
                      terms: .init("engine,runtime,start,stop,restart,DSH", "引擎,运行环境,启动,停止,重启,DSH")) {
            EngineView(embedded: true)
        },
        SettingsEntry("remote", "Remote hosts", glyph: AppIcon.remoteHosts, group: .hosts,
                      terms: .init("remote,ssh,computer,server,DSH Remote,connect", "远程,SSH,电脑,服务器,DSH Remote,连接电脑"),
                      value: { $0.savedHostCount == 0 ? nil : String(localized: "\($0.savedHostCount) host(s)") }) { RemoteHostsPage() },
        SettingsEntry("engine-parameters", "Engine parameters", glyph: AppIcon.configure, group: .hosts,
                      terms: .init("engine settings,advanced,parameters,subagent,commands", "引擎设置,高级,参数,子代理,命令执行"),
                      value: { $0.hostName ?? String(localized: "This phone") }) { EngineParametersPage() },
        SettingsEntry("help", "Help", glyph: AppIcon.askAi, group: .help,
                      terms: .init("help,guide,ask ai,how to", "帮助,教程,问 AI,怎么用,说明")) { HelpSettingsPage() },
        SettingsEntry("diagnostics", "Diagnostics", glyph: AppIcon.diagnostics, group: .help,
                      terms: .init("logs,troubleshoot,report,bug,errors", "日志,排障,诊断包,问题反馈,报错")) { DiagnosticsSettingsPage() },
        SettingsEntry("about", "About DSH Fan", glyph: AppIcon.info, group: .help, terms: .init("about,version,licenses", "关于,版本,许可"),
                      value: { $0.version }) { AboutPage() },
        SettingsEntry("reply-preferences", "Personal preferences", parent: "personalization", localOnly: true,
                      terms: .init("about me,style,tone,instructions,AGENTS.md", "偏好,关于我,自我介绍,回答风格,称呼,AGENTS.md")) {
            ReplyPreferencesPage()
        },
        SettingsEntry("agents", "Agent presets", parent: "personalization",
                      terms: .init("presets,mode,agent mode", "预设,模式,工作方式")) { AgentPresetsPage() },
        SettingsEntry("account", "DeepSeek account", localOnly: true,
                      terms: .init("account,balance,top up,sign in,sign out,api key,usage,DeepSeek", "账号,余额,充值,登录,退出登录,API Key,用量,DeepSeek")) {
            DeepSeekAccountPage()
        },
        SettingsEntry("key", "API key", parent: "account", terms: .init("credential,DeepSeek", "密钥,凭据,DeepSeek")) { KeySettingsPage() },
        SettingsEntry("model", "Default model", parent: "providers", terms: .init("thinking,model,reasoning", "默认模型,思考,推理")) { ModelSettingsPage() },
        SettingsEntry("features", "All features", parent: "help",
                      terms: .init("features,catalog,everything", "功能,目录,所有功能")) { AllSettingsFeaturesPage() },
        SettingsEntry("workspaces", "Workspaces", parent: "features", terms: .init("directories,files", "目录,文件")) { WorkspacesPage() },
        SettingsEntry("schedules", "Scheduled tasks", parent: "features", terms: .init("cron,automation,reminder", "计划,定时,提醒")) { SchedulesPage() },
        SettingsEntry("usage", "Run insights", parent: "features", terms: .init("tokens,usage", "令牌,用量,运行信息")) { RunInsightsPage() },
    ]

    static func entry(_ id: String) -> SettingsEntry? { entries.first { $0.id == id } }
    static func entries(in group: SettingsSection) -> [SettingsEntry] { entries.filter { $0.group == group } }
    static func destination(_ location: SettingsLocation) -> some View {
        Group {
            if let entry = entry(location.page) {
                entry.destination()
            }
        }
        .environment(\.settingsTarget, location.anchor)
    }

    static func path(for page: String?, group: SettingsSection? = nil) -> [String] {
        guard let page, let entry = entry(page) else { return ["Settings"] + (group.map { [$0.rawValue] } ?? []) }
        return path(for: entry.parent, group: entry.group) + [entry.key]
    }
}

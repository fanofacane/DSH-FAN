// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/{index/spots,search/settings_search}.dart.
import Foundation

struct SettingsLocation: Hashable, Identifiable {
    let page: String
    var anchor: String?
    var id: Self { self }

    init(_ page: String, anchor: String? = nil) {
        self.page = page
        self.anchor = anchor
    }
}

struct SearchTerms {
    let english: [String]
    let chinese: [String]
    let bonus: Int

    init(_ english: String = "", _ chinese: String = "", bonus: Int = 0) {
        self.english = english.split(separator: ",").map(String.init)
        self.chinese = chinese.split(separator: ",").map(String.init)
        self.bonus = bonus
    }
}

struct SettingSpot: Identifiable {
    let id: String
    let key: String
    let location: SettingsLocation
    let path: [String]
    var terms: SearchTerms
    var localOnly = false
    var feature = false
}

enum SettingsIndex {
    static let limit = 20
    private static let chinese = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj").flatMap(Bundle.init(path:))

    static func translated(_ key: String, chinese useChinese: Bool) -> String {
        useChinese ? chinese?.localizedString(forKey: key, value: key, table: nil) ?? key : key
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .filter { !$0.isWhitespace }
    }

    struct Hit: Identifiable {
        let spot: SettingSpot
        let score: Int
        let synonym: String?
        var id: String { spot.id }
    }

    static func search(_ query: String, in spots: [SettingSpot]) -> [Hit] {
        let query = normalize(query)
        guard !query.isEmpty else { return [] }
        return spots.enumerated().compactMap { offset, spot -> (Int, Hit)? in
            var score = 0
            var synonym: String?
            func take(_ candidate: Int, synonym term: String? = nil) {
                if candidate > score { score = candidate; synonym = term }
            }
            for chinese in [true, false] {
                let title = normalize(translated(spot.key, chinese: chinese))
                if title == query { take(100) }
                else if title.hasPrefix(query) { take(80) }
                else if title.contains(query) { take(60) }
                for term in chinese ? spot.terms.chinese : spot.terms.english {
                    let normalized = normalize(term)
                    if normalized == query { take(50, synonym: term) }
                    else if normalized.contains(query) { take(40, synonym: term) }
                }
                let path = normalize(spot.path.map { translated($0, chinese: chinese) }.joined(separator: " "))
                if path.contains(query) { take(20) }
            }
            guard score > 0 else { return nil }
            return (offset, Hit(spot: spot, score: score + spot.terms.bonus, synonym: synonym))
        }
        .sorted { $0.1.score == $1.1.score ? $0.0 < $1.0 : $0.1.score > $1.1.score }
        .prefix(limit)
        .map(\.1)
    }

    @MainActor static var spots: [SettingSpot] {
        let pages = SettingsRegistry.entries.map { entry in
            SettingSpot(id: entry.id, key: entry.key, location: SettingsLocation(entry.id),
                        path: SettingsRegistry.path(for: entry.id), terms: entry.terms, localOnly: entry.localOnly,
                        feature: entry.parent == "features")
        }
        return pages + [
            row("chat-text-size", "Chat text size", group: .appearance, "font,font size,text size,larger text", "字号,字体,文字大小,大字,字体大小", bonus: 5),
            row("fold-turns", "Collapse steps when done", group: .appearance, "collapse,fold,steps", "收起,折叠,过程,步骤"),
            row("language", "Language", group: .general, "chinese,english,locale", "中文,英文,简体,English"),
            row("theme-mode", "Color mode", page: "appearance", "dark,light,dark mode,night,system,appearance", "深色,浅色,暗色,夜间,深色模式,跟随系统,外观", bonus: 5),
            row("accent", "Accent color", page: "appearance", "color,colour,accent,palette,wallpaper", "颜色,主题色,强调色,壁纸,取色"),
            row("remote-images", "Load external message images", page: "privacy", "images,privacy", "图片,隐私"),
            row("notifications-enabled", "Task notifications", page: "notifications", "notifications on,turn off notifications", "通知开关,关闭通知"),
            row("default-permission", "New chat default", page: "permissions",
                "default permission,read only,workspace,full access,auto-run commands,don't ask",
                "默认权限,只读,工作区内修改,完全权限,自动执行命令,别问我", bonus: 2),
            row("phone-confirm", "Confirmation mode", page: "phone", "confirmation,don't ask,ask every time",
                "确认模式,别问我,每次询问,在任务内允许", bonus: 1),
            row("command-timeout", "Command timeout", page: "shell", "command timeout,execution limit", "命令超时,执行超时"),
            row("agent-loop.maxParallelToolCalls", "Max parallel tool calls", page: "agent-loop", "tool limit,parallel tool calls", "工具并行,并行调用"),
            row("subagent.maxDepth", "Maximum recursion depth", page: "subagent", "recursion depth,subagent limit", "递归深度,子代理深度"),
            row("pet-pack", "Choose a pet", page: "pet", "pet,whale,companion", "宠物,鲸鱼,鲸娘"),
            row("pet-size", "Pet size", page: "pet", "pet size", "宠物大小,宠物尺寸"),
            row("pet-quiet", "Quiet mode", page: "pet", "quiet,pet quiet", "安静,宠物安静"),
            row("pet-outside", "Show outside the app", page: "pet", "overlay,floating pet,outside app,live activity",
                "悬浮窗,桌面宠物,宠物悬浮,灵动岛,实时活动"),
            row("pet-outside-when", "When to show", page: "pet", "pet display,when to show", "宠物显示,显示时机"),
            row("quick-panel", "Swipe-left shortcuts", page: "interface", "swipe,shortcuts,gesture", "左滑,快捷入口,手势,滑动"),
            row("voice-enabled", "Dictation", page: "voice", "speech,microphone", "语音识别,麦克风,听写"),
            row("glass-blur", "Glass blur", page: "performance", "blur,glass,frosted", "模糊,毛玻璃,玻璃"),
            row("reduce-motion", "Reduce motion", page: "performance", "animation,motion", "动画,动效,减少动画"),
            row("tile-style", "Feature icons", page: "appearance", "icon style,tiles", "图标风格,磁贴"),
            row("app-icon", "App icon", page: "appearance", "launcher icon,icon", "启动图标,App 图标,图标"),
            row("launch-screen", "Launch screen", page: "appearance", "splash,startup,launch animation,opening screen", "开屏,启动动画,闪屏,开机画面,欢迎画面"),
            row("wallpaper", "Wallpaper", page: "appearance", "background,background image,chat background,backdrop,blur,photo",
                "背景,背景图,聊天背景,自定义背景,换背景,模糊,壁纸图片"),
            row("visual-replies", "Visual replies", page: "personalization", "charts,cards,visual,options", "图表,卡片,可视化,选项", localOnly: true),
            row("share-configuration", "Share configuration", page: "privacy", "share,export,config", "分享,导出配置,配置"),
            row("chat-log-upload", "Upload chat logs to DeepSeek", page: "privacy", "logs,upload,telemetry", "日志,上传日志,对话日志"),
            row("voice-language", "Speech recognition language", page: "voice", "dictation,locale", "语音语言,听写"),
            row("voice-offline", "On-device recognition only", page: "voice", "offline,voice model", "离线,语音模型"),
            row("performance-mode", "Performance mode", page: "performance", "battery,lite,full", "省电,轻量,完整"),
            row("notify-done", "Reply finished", page: "notifications", "reply done,finished", "完成提醒,回复完成"),
            row("notify-failed", "Error or stopped", page: "notifications", "error,failed,stopped", "出错提醒,失败"),
            row("notify-approval", "Approval needed", page: "notifications", "approval,waiting for you", "审批提醒,确认提醒"),
            row("notify-question", "Question asked", page: "notifications", "question,asks you", "提问提醒"),
            row("notify-live", "Show live progress", page: "notifications", "dynamic island,live update,live activity", "灵动岛,实时活动,锁屏进度"),
            row("notify-system", "System settings", page: "notifications", "sound,banner,lock screen,system", "声音,横幅,锁屏,系统通知"),
            row("diagnostics-export", "Export diagnostics", page: "diagnostics", "report,logs,export", "诊断包,导出,日志"),
            row("app-version", "Version", page: "about", "version,about,build", "版本号,关于"),
            row("open-source-licenses", "Open-source licenses", page: "about", "license,open source", "许可证,开源,License"),
            row("engine-safe", "Safe mode", page: "engine", "safe mode,leave safe mode,troubleshoot", "安全模式,恢复正常模式,排障"),
        ]
    }

    @MainActor static func row(_ id: String, _ key: String, page: String = "settings", group: SettingsSection? = nil,
                               _ english: String, _ chinese: String, bonus: Int = 0, localOnly: Bool = false) -> SettingSpot {
        SettingSpot(id: id, key: key, location: SettingsLocation(page, anchor: id),
                    path: SettingsRegistry.path(for: page, group: group), terms: SearchTerms(english, chinese, bonus: bonus),
                    localOnly: localOnly)
    }

    @MainActor static func location(forLink link: String) -> SettingsLocation? {
        let aliases = ["models": "providers", "permission": "permissions", "pets": "pet", "agent-presets": "agents",
                       "engine-settings": "engine-parameters", "system-access": "system-access"]
        if link == "settings" { return SettingsLocation("settings") }
        return spots.first { $0.id == (aliases[link] ?? link) }?.location
    }
}

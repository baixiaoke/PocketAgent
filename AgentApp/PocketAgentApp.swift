import SwiftUI

@main
struct PocketAgentApp: App {
    @StateObject private var runtime = AgentRuntime()
    @StateObject private var lock = AppLock.shared
    @StateObject private var themeMgr = ThemeManager.shared

    @AppStorage("pa.theme") private var themeRaw = "dark"
    @AppStorage("pa.fontScale") private var fontRaw = FontScale.normal.rawValue

    private var scheme: ColorScheme? {
        switch themeRaw {
        case "light": return .light
        case "auto":  return nil
        default:      return .dark
        }
    }

    private var typeSize: DynamicTypeSize {
        (FontScale(rawValue: fontRaw) ?? .normal).dynamicType
    }

    init() {
        NotificationBridge.shared.install()
        let s = Store.shared.settings
        if s.careEnabled {
            Task { await CareScheduler.ensureScheduled(settings: s) }
        }
    }

    var body: some Scene {
        WindowGroup {
            LockGate {
                ChatView()
                    .environmentObject(runtime)
            }
            .environmentObject(lock)
            .preferredColorScheme(scheme)
            .dynamicTypeSize(typeSize)
            .tint(Theme.cyan)                 // 开关、链接、按钮全部跟主题
            .id(themeMgr.paletteID)           // 换配色时整棵树重建，颜色立刻生效
        }
    }
}

import SwiftUI

@main
struct PocketAgentApp: App {
    @StateObject private var runtime = AgentRuntime()
    @StateObject private var lock = AppLock.shared

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

    var body: some Scene {
        WindowGroup {
            LockGate {
                ChatView()
                    .environmentObject(runtime)
            }
            .environmentObject(lock)
            .preferredColorScheme(scheme)
            .dynamicTypeSize(typeSize)
        }
    }
}

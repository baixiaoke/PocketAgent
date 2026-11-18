import SwiftUI

@main
struct PocketAgentApp: App {
    @StateObject private var runtime = AgentRuntime()
    @StateObject private var lock = AppLock.shared

    var body: some Scene {
        WindowGroup {
            LockGate {
                ChatView()
                    .environmentObject(runtime)
            }
            .environmentObject(lock)
            .preferredColorScheme(.dark)
        }
    }
}

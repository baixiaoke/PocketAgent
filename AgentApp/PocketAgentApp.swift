import SwiftUI

@main
struct PocketAgentApp: App {
    @StateObject private var runtime = AgentRuntime()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(runtime)
        }
    }
}

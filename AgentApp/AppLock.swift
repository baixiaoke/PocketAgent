import SwiftUI
import LocalAuthentication

/// 启动锁：Face ID / Touch ID / 密码
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    @Published var unlocked = false
    @Published var failed = false

    private init() {}

    var isAvailable: Bool {
        let ctx = LAContext()
        var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
    }

    func unlock() async {
        let ctx = LAContext()
        ctx.localizedReason = "解锁 PocketAgent"
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: "解锁 PocketAgent")
            unlocked = ok
            failed = !ok
        } catch {
            failed = true
        }
    }
}

/// 盖在内容上的锁屏
struct LockGate<Content: View>: View {
    @EnvironmentObject private var lock: AppLock
    @AppStorage("pa.requireBiometric") private var requireBiometric = false
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .blur(radius: needsLock ? 22 : 0)
                .allowsHitTesting(!needsLock)

            if needsLock {
                TechBackground()
                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(Theme.cyan.opacity(0.10))
                            .frame(width: 132, height: 132)
                            .blur(radius: 24)
                        Image(systemName: "faceid")
                            .font(.system(size: 58, weight: .light))
                            .foregroundStyle(Theme.cyan)
                            .neonGlow(Theme.cyan, radius: 16, opacity: 0.6)
                    }

                    Text("已锁定")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(lock.failed ? "没通过，再试一次" : "用 Face ID 或密码解锁")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))

                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Text("解锁")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(width: 150, height: 44)
                            .background(Theme.cyan, in: Capsule())
                            .neonGlow(Theme.cyan, radius: 14, opacity: 0.55)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .onAppear {
            if needsLock { Task { await lock.unlock() } }
        }
        .onChange(of: requireBiometric) { on in
            if !on { lock.unlocked = true }
        }
    }

    private var needsLock: Bool {
        requireBiometric && !lock.unlocked
    }
}

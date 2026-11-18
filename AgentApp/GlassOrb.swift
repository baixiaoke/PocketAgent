import SwiftUI

/// 通话页头像：玻璃球 + 旋转光弧 + 呼吸光晕
struct GlassOrb: View {
    let letter: String
    let level: Float          // 0…1 麦克风音量
    let active: Bool          // 是否在听/说

    @State private var spin: Double = 0
    @State private var breathe: CGFloat = 0
    @State private var ripple: CGFloat = 0

    private let size: CGFloat = 150

    var body: some View {
        ZStack {
            // 外层呼吸光晕
            Circle()
                .fill(
                    RadialGradient(colors: [Theme.cyan.opacity(0.55), Theme.violet.opacity(0.18), .clear],
                                   center: .center, startRadius: 10, endRadius: size * 0.78)
                )
                .frame(width: size * 1.5, height: size * 1.5)
                .blur(radius: 26)
                .opacity(0.55 + Double(breathe) * 0.35)
                .scaleEffect(1 + breathe * 0.05 + CGFloat(level) * 0.08)

            // 涟漪（在听的时候扩散）
            if active {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(Theme.cyan.opacity(0.35 - Double(i) * 0.12), lineWidth: 1)
                        .frame(width: size, height: size)
                        .scaleEffect(1 + (ripple + CGFloat(i) * 0.5) * 0.55)
                        .opacity(max(0, 1 - (ripple + CGFloat(i) * 0.5)))
                }
            }

            // 旋转光弧
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            Theme.cyan.opacity(0.95),
                            .clear,
                            Theme.violet.opacity(0.95),
                            .clear,
                            Theme.cyan.opacity(0.5),
                            .clear
                        ]),
                        center: .center),
                    lineWidth: 2.2)
                .frame(width: size + 12, height: size + 12)
                .rotationEffect(.degrees(spin))
                .blur(radius: 1.4)

            // 玻璃主体
            Circle()
                .fill(.ultraThinMaterial)
                .opacity(0.78)
                .frame(width: size, height: size)

            // 顶部内高光
            Circle()
                .fill(
                    RadialGradient(colors: [Color.white.opacity(0.42), .clear],
                                   center: UnitPoint(x: 0.32, y: 0.26),
                                   startRadius: 1, endRadius: size * 0.62)
                )
                .frame(width: size, height: size)

            // 一圈细描边
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.55),
                                            Color.white.opacity(0.05),
                                            Theme.cyan.opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
                .frame(width: size, height: size)

            // 字
            Text(letter)
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: Theme.cyan.opacity(0.55), radius: 10)

            // 左上那一点高光
            Ellipse()
                .fill(Color.white.opacity(0.5))
                .frame(width: 30, height: 18)
                .blur(radius: 7)
                .offset(x: -size * 0.22, y: -size * 0.24)
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .scaleEffect(1 + CGFloat(level) * 0.07)
        .animation(.easeOut(duration: 0.12), value: level)
        .onAppear {
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                spin = 360
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathe = 1
            }
            withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) {
                ripple = 1
            }
        }
    }
}

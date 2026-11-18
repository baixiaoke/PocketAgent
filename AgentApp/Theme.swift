import SwiftUI

/// 统一视觉语言：所有颜色都从当前调色板取，换主题即全局生效
enum Theme {
    private static var p: Palette { ThemeManager.shared.palette }

    static var void: Color { Color(uiColor: p.voidColor) }
    static var deep: Color { Color(uiColor: p.deepColor) }
    static var panel: Color { Color(uiColor: p.panelColor) }
    static var line: Color { Color.white.opacity(0.08) }

    static var cyan: Color { Color(uiColor: p.accent) }
    static var violet: Color { Color(uiColor: p.secondary) }
    static var mint: Color { Color(uiColor: p.mint) }
    static var amber: Color { Color(uiColor: p.amber) }
    static var danger: Color { Color(uiColor: p.danger) }

    static var userBubble: LinearGradient {
        LinearGradient(colors: [Color(uiColor: p.bubbleTop), Color(uiColor: p.bubbleBottom)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var accentBar: LinearGradient {
        LinearGradient(colors: [cyan.opacity(0.9), violet.opacity(0.85)],
                       startPoint: .leading, endPoint: .trailing)
    }
}

/// 深空背景：渐变 + 两团辉光 + 细网格
struct TechBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.void, Theme.deep, Theme.void.opacity(0.9)],
                startPoint: .top, endPoint: .bottom)

            Circle()
                .fill(Theme.cyan.opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -120, y: -260)

            Circle()
                .fill(Theme.violet.opacity(0.13))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: 140, y: 220)

            GridOverlay()
                .stroke(Theme.cyan.opacity(0.06), lineWidth: 0.5)
        }
        .ignoresSafeArea()
    }
}

/// 页面背景：有自定义图就用图（加暗化层保证文字可读），没有就用科技底
struct PageBackground: View {
    let page: ThemeManager.Page
    @ObservedObject private var tm = ThemeManager.shared

    var body: some View {
        ZStack {
            TechBackground()

            if let img = tm.backgroundImage(for: page) {
                GeometryReader { geo in
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .ignoresSafeArea()

                LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.35), .black.opacity(0.72)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
        .id(tm.backgroundRevision)
    }
}

/// 每 26pt 一根的极细网格
struct GridOverlay: Shape {
    var step: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = 0
        while x <= rect.width {
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: rect.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= rect.height {
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: rect.width, y: y))
            y += step
        }
        return p
    }
}

/// 玻璃卡片：半透明底 + 一圈渐变描边
struct GlassCard: ViewModifier {
    var radius: CGFloat = 18
    var tint: Color = Theme.cyan

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [tint.opacity(0.45), Color.white.opacity(0.06), tint.opacity(0.18)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8)
            )
            .shadow(color: tint.opacity(0.18), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func glassCard(radius: CGFloat = 18, tint: Color = Theme.cyan) -> some View {
        modifier(GlassCard(radius: radius, tint: tint))
    }

    func neonGlow(_ color: Color, radius: CGFloat = 10, opacity: Double = 0.5) -> some View {
        shadow(color: color.opacity(opacity), radius: radius)
    }
}

/// 顶部状态条：一条会呼吸的光带
struct PulseBar: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, Theme.cyan.opacity(0.9), Theme.violet.opacity(0.9), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.45)
                .offset(x: phase * geo.size.width)
                .onAppear {
                    withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                        phase = 1.2
                    }
                }
        }
        .frame(height: 1.6)
        .clipped()
    }
}

extension View {
    /// 让 List/Form 也吃主题：透明背景 + 统一底色
    func themedScroll(_ page: ThemeManager.Page) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(PageBackground(page: page))
    }
}

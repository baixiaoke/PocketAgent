import SwiftUI

/// 通话页头像：玻璃球 + 旋转光弧 + 呼吸光晕
struct GlassOrb: View {
    let letter: String
    let level: Float
    let active: Bool

    @State private var spin: Double = 0
    @State private var breathe: CGFloat = 0
    @State private var ripple: CGFloat = 0

    private var size: CGFloat { 150 }

    var body: some View {
        ZStack {
            glowView
            if active {
                rippleView
            }
            arcView
            bodyView
            coreView
            letterView
            highlightView
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .scaleEffect(1.0 + CGFloat(level) * 0.07)
        .animation(.easeOut(duration: 0.12), value: level)
        .onAppear(perform: startAnimations)
    }

    // MARK: 光晕
    private var glowView: some View {
        let c1: Color = Theme.cyan.opacity(0.55)
        let c2: Color = Theme.violet.opacity(0.18)
        let c3: Color = Color.clear
        let stops: [Color] = [c1, c2, c3]
        let grad: RadialGradient = RadialGradient(colors: stops,
                                                 center: UnitPoint.center,
                                                 startRadius: 10,
                                                 endRadius: size * 0.78)
        let side: CGFloat = size * 1.5
        let op: Double = 0.55 + Double(breathe) * 0.35
        let sc: CGFloat = 1.0 + breathe * 0.05 + CGFloat(level) * 0.08

        return Circle()
            .fill(grad)
            .frame(width: side, height: side)
            .blur(radius: 26)
            .opacity(op)
            .scaleEffect(sc)
    }

    // MARK: 涟漪
    private var rippleView: some View {
        ZStack {
            ringView(index: 0)
            ringView(index: 1)
        }
    }

    private func ringView(index: Int) -> some View {
        let phase: CGFloat = ripple + CGFloat(index) * 0.5
        let scale: CGFloat = 1.0 + phase * 0.55
        let raw: CGFloat = 1.0 - phase
        let clamped: CGFloat = raw < 0 ? 0 : raw
        let opacity: Double = Double(clamped)
        let base: Double = 0.35 - Double(index) * 0.12
        let strokeColor: Color = Theme.cyan.opacity(base)

        return Circle()
            .stroke(strokeColor, lineWidth: 1)
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .opacity(opacity)
    }

    // MARK: 旋转光弧
    private var arcView: some View {
        let a: Color = Color.clear
        let b: Color = Theme.cyan.opacity(0.95)
        let c: Color = Theme.violet.opacity(0.95)
        let d: Color = Theme.cyan.opacity(0.5)
        let stops: [Color] = [a, b, a, c, a, d, a]
        let grad: AngularGradient = AngularGradient(gradient: Gradient(colors: stops),
                                                    center: UnitPoint.center)
        let side: CGFloat = size + 12

        return Circle()
            .strokeBorder(grad, lineWidth: 2.2)
            .frame(width: side, height: side)
            .rotationEffect(Angle(degrees: spin))
            .blur(radius: 1.4)
    }

    // MARK: 玻璃球主体
    private var bodyView: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .opacity(0.78)
            .frame(width: size, height: size)
    }

    // MARK: 内高光 + 描边
    private var coreView: some View {
        ZStack {
            Circle()
                .fill(innerGlow)
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(edgeStroke, lineWidth: 1)
                .frame(width: size, height: size)
        }
    }

    private var innerGlow: RadialGradient {
        let colors: [Color] = [Color.white.opacity(0.42), Color.clear]
        let center: UnitPoint = UnitPoint(x: 0.32, y: 0.26)
        return RadialGradient(colors: colors, center: center,
                              startRadius: 1, endRadius: size * 0.62)
    }

    private var edgeStroke: LinearGradient {
        let colors: [Color] = [Color.white.opacity(0.55),
                               Color.white.opacity(0.05),
                               Theme.cyan.opacity(0.35)]
        return LinearGradient(colors: colors,
                              startPoint: UnitPoint.topLeading,
                              endPoint: UnitPoint.bottomTrailing)
    }

    // MARK: 字
    private var letterView: some View {
        Text(letter)
            .font(.system(size: 56, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.96))
            .shadow(color: Theme.cyan.opacity(0.55), radius: 10)
    }

    // MARK: 左上高光
    private var highlightView: some View {
        let dx: CGFloat = -(size * 0.22)
        let dy: CGFloat = -(size * 0.24)
        return Ellipse()
            .fill(Color.white.opacity(0.5))
            .frame(width: 30, height: 18)
            .blur(radius: 7)
            .offset(x: dx, y: dy)
    }

    // MARK: 动画
    private func startAnimations() {
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

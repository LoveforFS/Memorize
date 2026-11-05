import SwiftUI

/// 环形倒计时的几何计算（M8）：进度换算、起止角度与环宽。
///
/// 计算全部为纯函数，便于在没有渲染环境时逐条验证。
enum PieGeometry {
    /// 环形起始角度：从时钟 12 点方向开始，顺时针推进。
    static let startAngle: Angle = .degrees(-90)

    /// 剩余时间对应的进度，范围 0...1。
    /// - Parameters:
    ///   - remaining: 剩余秒数。
    ///   - total: 总秒数。
    static func progress(remaining: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        if remaining <= 0 { return 0 }
        if remaining >= total { return 1 }
        return Double(remaining) / Double(total)
    }

    /// 进度对应的结束角度（-90° 起、顺时针 360°）。
    static func endAngle(for progress: Double) -> Angle {
        let clamped = min(max(progress, 0), 1)
        return .degrees(-90 + 360 * clamped)
    }

    /// 环形描边宽度：直径的 10%，限制在 3...10 点。
    static func ringWidth(for diameter: CGFloat) -> CGFloat {
        guard diameter > 0 else { return 0 }
        let base = diameter * 0.1
        return min(max(base, 3), 10)
    }
}

/// 环形倒计时视图：外层灰色轨道 + 内层按进度裁剪的彩色圆弧，中心显示剩余秒数。
///
/// 数据来源是 `GameViewModel` 的 `countdownRemaining` / `countdownTotal`，
/// 点击环形区域会调用 `toggleCountdown()`，形成“状态驱动显示、点击回写状态”的双向绑定。
struct Pie: View {
    let remaining: Int
    let total: Int
    var tint: Color = .accentColor

    private var progress: Double {
        PieGeometry.progress(remaining: remaining, total: total)
    }

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let width = PieGeometry.ringWidth(for: diameter)

            ZStack {
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: width)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(PieGeometry.startAngle)
                    .animation(.linear(duration: Double(CountdownDefaults.tickInterval)), value: progress)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            Text("\(remaining)")
                .font(.caption.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .foregroundColor(total > 0 && remaining <= 5 ? .red : .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("倒计时 \(remaining) 秒"))
        .accessibilityIdentifier("countdownPie")
    }
}

struct Pie_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            Pie(remaining: 60, total: 60)
            Pie(remaining: 30, total: 60)
            Pie(remaining: 0, total: 60)
        }
        .frame(height: 70)
        .padding()
    }
}

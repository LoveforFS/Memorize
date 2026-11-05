import SwiftUI

/// 卡片统一外观规范（M8）：所有卡片组件的形状、描边、内边距与阴影都由这里决定。
///
/// 几何量按卡片短边等比缩放并做上下限约束，保证小尺寸卡片不显得过于圆润、
/// 大尺寸卡片也不会出现夸张的圆角和粗边框。
enum CardStyle {
    /// 卡片宽高比（宽 / 高）。
    static let aspectRatio: CGFloat = 2 / 3

    static let frontFill = Color(uiColor: .systemBackground)
    static let backFill = Color.accentColor
    static let normalBorder = Color.accentColor
    static let matchedBorder = Color.green
    static let shadowColor = Color.black.opacity(0.12)

    /// 圆角半径：短边的 12%，限制在 6...20 点。
    static func cornerRadius(for size: CGSize) -> CGFloat {
        guard isValid(size) else { return 0 }
        let base = min(size.width, size.height) * 0.12
        return min(max(base, 6), 20)
    }

    /// 描边宽度：短边的 1%，限制在 1...3 点。
    static func borderWidth(for size: CGSize) -> CGFloat {
        guard isValid(size) else { return 0 }
        let base = min(size.width, size.height) * 0.01
        return min(max(base, 1), 3)
    }

    /// 内容内边距：短边的 8%，限制在 2...8 点。
    static func contentPadding(for size: CGSize) -> CGFloat {
        guard isValid(size) else { return 0 }
        let base = min(size.width, size.height) * 0.08
        return min(max(base, 2), 8)
    }

    /// 阴影模糊半径：短边的 3%，限制在 1...6 点。
    static func shadowRadius(for size: CGSize) -> CGFloat {
        guard isValid(size) else { return 0 }
        let base = min(size.width, size.height) * 0.03
        return min(max(base, 1), 6)
    }

    /// 卡片形状，圆角由尺寸推导。
    static func shape(for size: CGSize) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius(for: size))
    }

    private static func isValid(_ size: CGSize) -> Bool {
        size.width > 0 && size.height > 0
    }
}

/// 统一卡片外观的视图修饰器：负责背景、描边、内边距、阴影与宽高比。
struct Cardify: ViewModifier {
    /// 是否正面朝上（决定背景色）。
    let isFaceUp: Bool
    /// 是否已配对（决定描边颜色）。
    let isMatched: Bool

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            let shape = CardStyle.shape(for: size)

            content
                .padding(CardStyle.contentPadding(for: size))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(isFaceUp ? CardStyle.frontFill : CardStyle.backFill))
                .clipShape(shape)
                .overlay(
                    shape.strokeBorder(
                        isMatched ? CardStyle.matchedBorder : CardStyle.normalBorder,
                        lineWidth: CardStyle.borderWidth(for: size)
                    )
                )
                .shadow(
                    color: CardStyle.shadowColor,
                    radius: CardStyle.shadowRadius(for: size),
                    x: 0,
                    y: 2
                )
        }
        .aspectRatio(CardStyle.aspectRatio, contentMode: .fit)
    }
}

extension View {
    /// 应用统一的卡片外观。
    func cardify(isFaceUp: Bool, isMatched: Bool = false) -> some View {
        modifier(Cardify(isFaceUp: isFaceUp, isMatched: isMatched))
    }
}

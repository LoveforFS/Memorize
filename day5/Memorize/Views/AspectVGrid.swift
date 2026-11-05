import SwiftUI

/// 自适应网格容器（M6）：按可用空间计算单卡片尺寸，保证任意尺寸下都不溢出、不重叠。
///
/// 设计要点：
/// - 列数从 1 开始逐列增加，直到「行数 × 单元高度」不超过可用高度；
/// - 单元格宽度向下取整，避免浮点误差导致的像素级溢出；
/// - 所有排布计算集中在静态方法 `itemWidthThatFits`，便于单元测试直接验证。
struct AspectVGrid<Item: Identifiable, ItemView: View>: View {
    private let items: [Item]
    private let aspectRatio: CGFloat
    private let content: (Item) -> ItemView

    init(
        items: [Item],
        aspectRatio: CGFloat = 1,
        @ViewBuilder content: @escaping (Item) -> ItemView
    ) {
        self.items = items
        self.aspectRatio = aspectRatio
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let itemWidth = Self.itemWidthThatFits(
                count: items.count,
                size: geometry.size,
                aspectRatio: aspectRatio
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: itemWidth), spacing: 0)],
                spacing: 0
            ) {
                ForEach(items) { item in
                    content(item)
                        .aspectRatio(aspectRatio, contentMode: .fit)
                }
            }
        }
    }

    /// 计算在给定可用空间内、能完整放下所有卡片的最大卡片宽度。
    ///
    /// - Parameters:
    ///   - count: 卡片数量。
    ///   - size: 可用空间尺寸（宽 × 高）。
    ///   - aspectRatio: 单张卡片的宽高比（宽 / 高），必须大于 0。
    /// - Returns: 卡片宽度（向下取整）；输入非法或无法放下时返回 0。
    static func itemWidthThatFits(count: Int, size: CGSize, aspectRatio: CGFloat) -> CGFloat {
        guard count > 0, size.width > 0, size.height > 0, aspectRatio > 0 else {
            return 0
        }

        let itemCount = CGFloat(count)
        var columnCount: CGFloat = 1

        repeat {
            let width = size.width / columnCount
            let height = width / aspectRatio
            let rowCount = (itemCount / columnCount).rounded(.up)
            if rowCount * height <= size.height {
                return width.rounded(.down)
            }
            columnCount += 1
        } while columnCount < itemCount

        // 兜底：单列也放不下时，按宽高两个方向分别压缩后取更小值。
        return min(size.width / itemCount, size.height * aspectRatio).rounded(.down)
    }
}

struct AspectVGrid_Previews: PreviewProvider {
    static var previews: some View {
        AspectVGrid(items: Game(theme: Theme.builtIn[0], numberOfPairs: 5, shuffle: false).cards, aspectRatio: 2 / 3) { card in
            CardView(card: card)
        }
        .padding()
    }
}

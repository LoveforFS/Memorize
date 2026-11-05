import SwiftUI

/// 单张卡片视图：正面显示 emoji，背面显示统一图标；配对成功后描边变绿。
///
/// 外观（背景、描边、内边距、圆角、阴影、宽高比）统一由 `Cardify` 修饰器负责，
/// 本视图只保留「翻哪一面」与「翻牌动画」两件事。
struct CardView: View {
    let card: Card

    /// 是否展示正面：已配对卡片始终保持正面。
    private var isFaceUp: Bool {
        card.isFaceUp || card.isMatched
    }

    var body: some View {
        ZStack {
            backFace
                .opacity(isFaceUp ? 0 : 1)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            frontFace
                .opacity(isFaceUp ? 1 : 0)
        }
        .rotation3DEffect(
            .degrees(isFaceUp ? 0 : 180),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
        .animation(AnimationTiming.flip, value: isFaceUp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
    }

    private var frontFace: some View {
        Text(card.content)
            .font(.system(size: 36))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .cardify(isFaceUp: true, isMatched: card.isMatched)
    }

    private var backFace: some View {
        Image(systemName: "questionmark")
            .font(.title2.bold())
            .foregroundColor(.white)
            .cardify(isFaceUp: false)
    }

    private var accessibilityText: String {
        if card.isMatched {
            return "已配对的卡片 \(card.content)"
        }
        if card.isFaceUp {
            return "已翻开的卡片 \(card.content)"
        }
        return "未翻开的卡片"
    }
}

struct CardView_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            CardView(card: Card(content: "🐶"))
            CardView(card: Card(content: "🐶", isFaceUp: true))
            CardView(card: Card(content: "🐶", isFaceUp: true, isMatched: true))
        }
        .padding()
    }
}

import SwiftUI

/// 单张卡片视图：正面显示 emoji，背面显示统一图标；配对成功后加绿色边框。
///
/// M7 翻牌动画：
/// - 以 Y 轴 3D 旋转表现“翻面”，透视系数 0.55 保留空间层次；
/// - 正反面分层并按状态切换透明度，避免两面同时可见造成穿模；
/// - 背面单独反向旋转 180°，保证卡片朝下时图标不镜像。
struct CardView: View {
    let card: Card

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12)
    }

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
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .rotation3DEffect(
            .degrees(isFaceUp ? 0 : 180),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
        .animation(AnimationTiming.flip, value: isFaceUp)
        .overlay {
            if card.isMatched {
                cardShape
                    .strokeBorder(Color.green, lineWidth: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
    }

    private var frontFace: some View {
        ZStack {
            cardShape
                .fill(Color(uiColor: .systemBackground))
            cardShape
                .strokeBorder(Color.accentColor, lineWidth: 2)

            Text(card.content)
                .font(.system(size: 36))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(6)
        }
    }

    private var backFace: some View {
        ZStack {
            cardShape
                .fill(Color.accentColor)
            Image(systemName: "questionmark")
                .font(.title2.bold())
                .foregroundColor(.white)
        }
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

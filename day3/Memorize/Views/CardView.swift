import SwiftUI

/// 单张卡片视图：正面显示 emoji，背面显示统一图标；配对成功后加绿色边框。
struct CardView: View {
    let card: Card

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12)
    }

    var body: some View {
        ZStack {
            if card.isFaceUp || card.isMatched {
                cardShape
                    .fill(Color(uiColor: .systemBackground))
                cardShape
                    .strokeBorder(Color.accentColor, lineWidth: 2)

                Text(card.content)
                    .font(.system(size: 36))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(6)
            } else {
                cardShape
                    .fill(Color.accentColor)
                Image(systemName: "questionmark")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
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

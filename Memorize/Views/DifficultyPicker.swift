import SwiftUI

/// 难度选择器：三张并排卡片，展示难度名称与关键参数（牌数 / 时间）。
///
/// 只负责「选中哪个难度」，具体参数由 `Difficulty` 提供，
/// 因此首页与设置页可以复用同一个组件而不产生两套规则。
struct DifficultyPicker: View {
    @Binding var selection: Difficulty

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Difficulty.allCases) { difficulty in
                button(for: difficulty)
            }
        }
    }

    private func button(for difficulty: Difficulty) -> some View {
        let isSelected = difficulty == selection

        return Button {
            withAnimation(AnimationTiming.selection) {
                selection = difficulty
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: difficulty.symbolName)
                    .font(.headline)
                    .frame(height: 20)

                Text(difficulty.title)
                    .font(.subheadline.bold())

                Text("\(difficulty.cardCount) 张 · \(difficulty.countdownDuration) 秒")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(isSelected ? difficulty.tint : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? difficulty.tint.opacity(0.16) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? difficulty.tint : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("difficulty-\(difficulty.rawValue)")
        .accessibilityLabel(Text("难度：\(difficulty.title)"))
        .accessibilityValue(Text(isSelected ? "已选中，\(difficulty.ruleSummary)" : difficulty.ruleSummary))
    }
}

struct DifficultyPicker_Previews: PreviewProvider {
    static var previews: some View {
        DifficultyPicker(selection: .constant(.normal))
            .padding()
    }
}

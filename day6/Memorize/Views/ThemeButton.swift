import SwiftUI

/// 主题选择按钮：显示主题代表 emoji 与名称，选中时用主题色描边。
struct ThemeButton: View {
    let theme: Theme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(theme.emojis.prefix(2).joined())
                    .font(.title3)
                Text(theme.name)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? theme.color.opacity(0.25) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? theme.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("主题：\(theme.name)"))
        .accessibilityValue(Text(isSelected ? "当前已选中" : "未选中"))
    }
}

struct ThemeButton_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            ThemeButton(theme: Theme.builtIn[0], isSelected: true) {}
            ThemeButton(theme: Theme.builtIn[1], isSelected: false) {}
        }
        .padding()
    }
}

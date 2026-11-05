import SwiftUI

/// 主题模型：定义一局游戏使用的 emoji 集合与配色。
///
/// 约束：
/// - 名称去除首尾空白后不能为空；
/// - emoji 集合去除空白项后至少保留一个；
/// - 卡片对数必须大于 0，且不超过可用 emoji 数量（超出时按可用数量截断）。
struct Theme: Identifiable {
    let id: UUID
    let name: String
    let emojis: [String]
    let color: Color
    let numberOfPairs: Int

    /// 主题校验失败的原因。
    enum ValidationError: LocalizedError, Equatable {
        case emptyName
        case emptyEmojiSet
        case invalidNumberOfPairs(Int)

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "主题名称不能为空"
            case .emptyEmojiSet:
                return "主题至少需要一个 emoji"
            case .invalidNumberOfPairs(let value):
                return "卡片对数必须大于 0，当前为 \(value)"
            }
        }
    }

    /// 创建主题并完成校验。
    /// - Parameter numberOfPairs: 卡片对数；传 `nil` 时使用全部可用 emoji。
    init(
        id: UUID = UUID(),
        name: String,
        emojis: [String],
        color: Color,
        numberOfPairs: Int? = nil
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ValidationError.emptyName
        }

        let cleanedEmojis = emojis
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanedEmojis.isEmpty else {
            throw ValidationError.emptyEmojiSet
        }

        let requestedPairs = numberOfPairs ?? cleanedEmojis.count
        guard requestedPairs > 0 else {
            throw ValidationError.invalidNumberOfPairs(requestedPairs)
        }

        self.id = id
        self.name = trimmedName
        self.emojis = cleanedEmojis
        self.color = color
        // 对数不能超过 emoji 数量，超出时截断，避免生成不完整的牌组。
        self.numberOfPairs = min(requestedPairs, cleanedEmojis.count)
    }
}

extension Theme {
    /// 内置主题，供游戏默认使用（常量已校验，不会创建失败）。
    static let builtIn: [Theme] = [
        try! Theme(name: "动物", emojis: ["🐶", "🐱", "🐭", "🐹", "🐰", "🐻", "🐼", "🐨"], color: .orange),
        try! Theme(name: "运动", emojis: ["⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🏓", "🏸"], color: .green),
        try! Theme(name: "表情", emojis: ["😀", "😅", "🥲", "😍", "🤔", "😴", "🥳", "😎"], color: .yellow),
        try! Theme(name: "旗帜", emojis: ["🇨🇳", "🇯🇵", "🇰🇷", "🇫🇷", "🇩🇪", "🇮🇹", "🇪🇸", "🇬🇧"], color: .red),
        try! Theme(name: "天气", emojis: ["☀️", "🌤", "☁️", "🌧", "⛈", "❄️", "🌪", "🌈"], color: .blue),
        try! Theme(name: "食物", emojis: ["🍎", "🍌", "🍇", "🍓", "🍑", "🍍", "🥝", "🍒"], color: .pink)
    ]
}

import Foundation

/// 卡片模型：一张卡片只有唯一 id 与固定内容，翻转与配对属于可变状态。
struct Card: Identifiable, Equatable {
    let id: UUID
    /// 卡片内容（emoji），创建时去除首尾空白，且不允许为空。
    let content: String
    /// 是否正面朝上。
    var isFaceUp: Bool
    /// 是否已经与其他卡片配对成功。
    var isMatched: Bool

    init(
        id: UUID = UUID(),
        content: String,
        isFaceUp: Bool = false,
        isMatched: Bool = false
    ) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmedContent.isEmpty, "卡片内容不能为空")

        self.id = id
        self.content = trimmedContent
        self.isFaceUp = isFaceUp
        self.isMatched = isMatched
    }

    /// 同一张卡片（id 相同）视为相等，翻转/配对状态不参与比较。
    static func == (lhs: Card, rhs: Card) -> Bool {
        lhs.id == rhs.id
    }
}

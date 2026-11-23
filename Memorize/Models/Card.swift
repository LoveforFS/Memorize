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

    /// 是否指向同一张卡片。
    ///
    /// 注意：相等性（`==`）使用编译器合成的实现，比较全部存储属性。
    /// 不要重载 `==` 为「只比较 id」：SwiftUI 依据 `Equatable` 判断视图是否需要刷新，
    /// 若相等性忽略 `isFaceUp` / `isMatched`，翻牌后卡片会被判定为「没有变化」，
    /// 界面与无障碍标签都会停留在旧状态。判断同一张卡片请使用本方法或比较 `id`。
    func isSameCard(as other: Card) -> Bool {
        id == other.id
    }
}

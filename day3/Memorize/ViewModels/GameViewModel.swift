import SwiftUI

/// 视图模型：承载 M3 的交互状态，是视图与 `Game` 模型之间的唯一通道。
///
/// 交互规则：
/// - 错配后进入“等待翻回”状态并锁定交互，防止连点造成状态错乱；
/// - 视图在延时结束后调用 `completeMismatchFlipBack()` 翻回并解锁；
/// - 重开一局或切换主题会立即解除锁定。
final class GameViewModel: ObservableObject {
    @Published private(set) var game: Game
    /// 是否处于错配等待期（此期间忽略所有卡片与按钮点击）。
    @Published private(set) var isInteractionLocked = false

    var cards: [Card] { game.cards }
    var score: Int { game.score }
    var theme: Theme { game.theme }
    var isGameOver: Bool { game.isGameOver }
    var matchedPairsCount: Int { game.matchedPairsCount }
    var hasPendingMismatch: Bool { game.hasPendingMismatch }

    init(theme: Theme = Theme.builtIn[0], numberOfPairs: Int? = nil, shuffle: Bool = true) {
        self.game = Game(theme: theme, numberOfPairs: numberOfPairs, shuffle: shuffle)
    }

    /// 处理一次卡片点击。
    func choose(_ card: Card) {
        guard !isInteractionLocked else { return }

        game.choose(card)

        if game.hasPendingMismatch {
            isInteractionLocked = true
        }
    }

    /// 错配延时结束：翻回卡片并解除交互锁。
    func completeMismatchFlipBack() {
        guard game.hasPendingMismatch else { return }

        game.flipBackMismatch()
        isInteractionLocked = false
    }

    /// 使用当前主题重新开始，并解除交互锁。
    func newGame() {
        game.newGame()
        isInteractionLocked = false
    }

    /// 切换主题并重新开始，同时解除交互锁。
    func chooseTheme(_ theme: Theme) {
        game.startNewGame(with: theme)
        isInteractionLocked = false
    }
}

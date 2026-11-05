import SwiftUI

/// 视图模型：视图与 `Game` 模型之间的唯一通道，负责状态发布与交互调度。
///
/// 接口按大纲 M4 约定：
/// - `@Published var cards`、`@Published var score`，视图直接订阅刷新；
/// - `choose(_:)`、`chooseTheme(_:)`、`newGame()`。
///
/// 交互规则：
/// - 错配后进入“等待翻回”状态并锁定交互，防止连点造成状态错乱；
/// - 由 ViewModel 调度 `mismatchFlipDelay` 秒后的翻回任务，视图不再持有计时逻辑；
/// - 重开一局或切换主题会立即解除锁定，并让过期计时回调失效。
final class GameViewModel: ObservableObject {
    /// 当前牌组（大纲约定的 @Published 接口，视图直接订阅）。
    @Published var cards: [Card]
    /// 当前得分（大纲约定的 @Published 接口，视图直接订阅）。
    @Published var score: Int
    /// 是否处于错配等待期（此期间忽略所有卡片与按钮点击）。
    @Published private(set) var isInteractionLocked = false

    /// 牌局模型，作为唯一状态来源；对外只读，界面数据通过 cards/score 发布。
    private(set) var game: Game

    /// 错配后卡片保持正面的时长（秒），默认 0.8（与 M3 交互一致）。
    let mismatchFlipDelay: TimeInterval

    private let timer: MismatchTimerScheduling
    /// 挂起计时任务的令牌：令牌不匹配的回调视为过期，直接丢弃。
    private var pendingTimerToken: UUID?

    var theme: Theme { game.theme }
    var isGameOver: Bool { game.isGameOver }
    var matchedPairsCount: Int { game.matchedPairsCount }
    var hasPendingMismatch: Bool { game.hasPendingMismatch }

    init(
        theme: Theme = Theme.builtIn[0],
        numberOfPairs: Int? = nil,
        shuffle: Bool = true,
        mismatchFlipDelay: TimeInterval = 0.8,
        timer: MismatchTimerScheduling = DispatchMismatchTimer()
    ) {
        let initialGame = Game(theme: theme, numberOfPairs: numberOfPairs, shuffle: shuffle)

        self.game = initialGame
        self.cards = initialGame.cards
        self.score = initialGame.score
        self.mismatchFlipDelay = mismatchFlipDelay
        self.timer = timer
    }

    /// 处理一次卡片点击；错配时锁定交互并调度延时翻回。
    func choose(_ card: Card) {
        guard !isInteractionLocked else { return }

        game.choose(card)
        syncFromGame()

        guard game.hasPendingMismatch else { return }

        isInteractionLocked = true
        scheduleFlipBack()
    }

    /// 错配延时结束：翻回卡片并解除交互锁。手动调用同样有效（供测试与兜底使用）。
    func completeMismatchFlipBack() {
        pendingTimerToken = nil

        guard game.hasPendingMismatch else { return }

        game.flipBackMismatch()
        syncFromGame()
        isInteractionLocked = false
    }

    /// 使用当前主题重新开始，解除交互锁并作废未触发的计时回调。
    func newGame() {
        pendingTimerToken = nil
        isInteractionLocked = false

        game.newGame()
        syncFromGame()
    }

    /// 切换主题并重新开始，解除交互锁并作废未触发的计时回调。
    func chooseTheme(_ theme: Theme) {
        pendingTimerToken = nil
        isInteractionLocked = false

        game.startNewGame(with: theme)
        syncFromGame()
    }

    // MARK: - 私有实现

    /// 调度一次延时翻回；已有挂起任务时不再重复调度。
    private func scheduleFlipBack() {
        guard pendingTimerToken == nil else { return }

        let token = UUID()
        pendingTimerToken = token

        timer.schedule(after: mismatchFlipDelay) { [weak self] in
            guard let self = self, self.pendingTimerToken == token else { return }
            self.completeMismatchFlipBack()
        }
    }

    /// 把模型状态同步到对外发布的属性，触发视图刷新。
    private func syncFromGame() {
        cards = game.cards
        score = game.score
    }
}

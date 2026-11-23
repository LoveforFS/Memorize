import Foundation

/// App 级页面：主页 / 牌局。
enum AppPhase: Equatable {
    case home
    case playing
}

/// 流程视图模型：负责「主页 ⇄ 牌局」的切换、当前牌局的持有与设置持久化。
///
/// 职责边界：
/// - 它只决定「看哪个页面」和「用哪套参数开新局」；
/// - 牌局内的翻牌、暂停、计时仍由 `GameViewModel` 独立负责；
/// - 主页读取汇总信息（进行中牌局摘要、最佳成绩），不直接修改牌局状态。
///
/// 牌局实例在「返回主菜单」后仍然保留，这样 `继续游戏` 能恢复原来的牌面与得分；
/// 每次开新局都会递增 `sessionID`，让视图用 `.id` 重建界面状态（发牌动画、弹窗标记等）。
final class GameFlowViewModel: ObservableObject {
    /// 当前展示的页面。
    @Published private(set) var phase: AppPhase = .home

    /// 玩家设置：变化时立即持久化，并在下一局生效。
    @Published var settings: GameSettings {
        didSet {
            guard settings != oldValue else { return }
            store.settings = settings
        }
    }

    /// 当前牌局；从未开始过时为 nil。
    @Published private(set) var game: GameViewModel?
    /// 牌局会话编号：每次开新局递增，供视图重建界面状态。
    @Published private(set) var sessionID = 0
    /// 各难度最佳成绩，主页与设置页直接读取。
    @Published private(set) var bestScores: [Difficulty: Int] = [:]

    private let store: GameSettingsStoring
    /// 新局是否洗牌；UI 自动化关闭洗牌以获得确定的牌序。
    private let shuffleNewGames: Bool
    /// 错配翻回延时的覆盖值（nil 表示按难度决定）。
    private let mismatchFlipDelayOverride: TimeInterval?

    init(
        settings: GameSettings? = nil,
        store: GameSettingsStoring = InMemoryGameSettingsStore(),
        shuffleNewGames: Bool = true,
        mismatchFlipDelay: TimeInterval? = nil
    ) {
        self.store = store
        self.settings = settings ?? store.settings
        self.shuffleNewGames = shuffleNewGames
        self.mismatchFlipDelayOverride = mismatchFlipDelay
        self.bestScores = Dictionary(
            uniqueKeysWithValues: Difficulty.allCases.map { ($0, store.bestScore(for: $0)) }
        )
    }

    // MARK: - 派生信息

    /// 是否可以「继续游戏」：有牌局且还没结束。
    var canContinue: Bool {
        guard let game else { return false }
        return !game.isGameOver && game.countdownState != .finished
    }

    /// 继续游戏按钮下方的状态说明。
    var continueCaption: String {
        guard let game else { return "暂无进行中的牌局" }
        if game.isGameOver { return "上一局已全部配对完成，开始新的一局吧" }
        if game.countdownState == .finished { return "上一局时间到，开始新的一局吧" }
        return "\(game.difficulty.title) · \(game.theme.name) · 剩余 \(game.countdownRemaining) 秒"
    }

    /// 当前所选难度的最佳成绩。
    var selectedBestScore: Int {
        bestScores[settings.difficulty] ?? 0
    }

    // MARK: - 页面切换

    /// 用当前设置开一局新游戏。
    func startNewGame() {
        let newGame = makeGame(settings: settings)
        sessionID += 1
        game = newGame
        phase = .playing
    }

    /// 继续上一次未完成的牌局。
    ///
    /// 返回主页时牌局已被暂停，这里先恢复计时再回到牌面，
    /// 保证「暂停期间时间不走」的语义在跨页面时同样成立。
    func continueGame() {
        guard let game, canContinue else { return }
        game.resume()
        phase = .playing
    }

    /// 返回主菜单：保留牌局进度，但停表并进入暂停态。
    func returnToHome() {
        game?.pause()
        phase = .home
    }

    /// 重新开始：沿用**当前牌局**的难度与主题，而不是主页上可能被改动过的设置。
    func restartCurrentGame() {
        guard let current = game else {
            startNewGame()
            return
        }

        let currentSettings = GameSettings(
            difficulty: current.difficulty,
            themeName: current.theme.name
        )
        sessionID += 1
        game = makeGame(settings: currentSettings)
        phase = .playing
    }

    /// 进入后台等场景时自动暂停，避免倒计时在不可见时继续流失。
    func pauseGame() {
        game?.pause()
    }

    // MARK: - 成绩

    /// 一局结束时记录最佳成绩（同一难度取历史最高分）。
    func handleGameFinished(score: Int) {
        guard let game else { return }
        store.recordBestScore(score, for: game.difficulty)
        bestScores[game.difficulty] = store.bestScore(for: game.difficulty)
    }

    /// 清除全部最佳成绩。
    func resetBestScores() {
        store.resetBestScores()
        bestScores = Dictionary(
            uniqueKeysWithValues: Difficulty.allCases.map { ($0, store.bestScore(for: $0)) }
        )
    }

    // MARK: - 私有实现

    private func makeGame(settings: GameSettings) -> GameViewModel {
        GameViewModel(
            difficulty: settings.difficulty,
            theme: settings.theme,
            numberOfPairs: settings.numberOfPairs,
            shuffle: shuffleNewGames,
            mismatchFlipDelay: mismatchFlipDelayOverride
        )
    }
}

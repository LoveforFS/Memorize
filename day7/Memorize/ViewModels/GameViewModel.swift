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
///
/// M7 动画边界：
/// - 翻牌、得分、发牌三类动画的“是否允许播放”统一由 `animations` 判定；
/// - 视图只订阅 `boardRevision`、`scoreRevision`、`scoreChangeDelta` 三个版本号；
/// - 错配锁定期间不产生任何新的动画版本，避免动画与交互竞争。
final class GameViewModel: ObservableObject {
    /// 当前牌组（大纲约定的 @Published 接口，视图直接订阅）。
    @Published var cards: [Card]
    /// 当前得分（大纲约定的 @Published 接口，视图直接订阅）。
    @Published var score: Int
    /// 是否处于错配等待期（此期间忽略所有卡片与按钮点击）。
    @Published private(set) var isInteractionLocked = false
    /// 牌局版本号：重开或切换主题时递增，驱动错峰发牌动画。
    @Published private(set) var boardRevision = 0
    /// 得分版本号：得分真正变化时递增，驱动数值跳动与缩放反馈。
    @Published private(set) var scoreRevision = 0
    /// 最近一次得分变化量（+2 加分、-1 扣分、0 无变化）。
    @Published private(set) var scoreChangeDelta = 0

    /// 倒计时剩余秒数（M8），视图环形进度直接绑定。
    @Published private(set) var countdownRemaining = 0
    /// 倒计时总秒数。
    @Published private(set) var countdownTotal = 0
    /// 倒计时状态：未开始 / 计时中 / 已暂停 / 已结束。
    @Published private(set) var countdownState: CountdownState = .idle
    /// 是否因倒计时耗尽而时间到。
    @Published private(set) var didTimeOut = false

    /// 牌局模型，作为唯一状态来源；对外只读，界面数据通过 cards/score 发布。
    private(set) var game: Game

    /// 动画边界控制器：翻牌去重、得分合并、发牌版本号。
    let animations = GameAnimationCoordinator()

    /// 倒计时使用的周期计时器，便于测试注入。
    let countdownClock: CountdownClock
    /// 本局倒计时时长，用于重开时恢复。
    private var countdownDuration = 0


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
        timer: MismatchTimerScheduling = DispatchMismatchTimer(),
        countdownClock: CountdownClock = DispatchCountdownClock()
    ) {
        let initialGame = Game(theme: theme, numberOfPairs: numberOfPairs, shuffle: shuffle)

        self.game = initialGame
        self.cards = initialGame.cards
        self.score = initialGame.score
        self.mismatchFlipDelay = mismatchFlipDelay
        self.timer = timer
        self.countdownClock = countdownClock
    }

    /// 处理一次卡片点击；错配时锁定交互并调度延时翻回。
    func choose(_ card: Card) {
        guard !isInteractionLocked else { return }

        let previousScore = game.score
        let wasFaceUp = game.cards.first(where: { $0.id == card.id })?.isFaceUp ?? false

        game.choose(card)
        syncFromGame()

        // 只有“背面翻到正面”的真实变化才记录翻牌动画，重复点击不会叠加。
        if !wasFaceUp, let updated = game.cards.first(where: { $0.id == card.id }), updated.isFaceUp {
            animations.beginFlip(for: updated.id)
        }

        if let revision = animations.scoreDidChange(from: previousScore, to: game.score) {
            scoreRevision = revision
            scoreChangeDelta = AnimationTiming.scoreDelta(from: previousScore, to: game.score)
        }

        guard game.hasPendingMismatch else { return }

        isInteractionLocked = true
        scheduleFlipBack()
    }

    /// 翻牌动画播放结束，释放该卡片的动画占用（由视图在动画时长后回调）。
    func endFlip(for cardID: UUID) {
        animations.endFlip(for: cardID)
    }

    // MARK: - 倒计时（M8）

    /// 开始倒计时；已在计时中会先停止旧计时再重新开始。
    /// - Parameter duration: 总秒数，必须大于 0。
    func startCountdown(duration: Int = CountdownDefaults.duration) {
        guard duration > 0 else { return }

        countdownClock.stop()
        countdownDuration = duration
        countdownTotal = duration
        countdownRemaining = duration
        didTimeOut = false
        countdownState = .running
        scheduleCountdownTicks()
    }

    /// 首次进入界面时启动倒计时；已经启动过则不重复启动。
    func startCountdownIfNeeded() {
        guard countdownState == .idle, countdownDuration == 0 else { return }
        startCountdown()
    }

    /// 每次计时器触发：剩余秒数减一，归零时进入结束状态。
    func tickCountdown() {
        guard countdownState == .running else { return }

        guard countdownRemaining > 0 else {
            finishCountdown()
            return
        }

        countdownRemaining -= 1
        if countdownRemaining == 0 {
            finishCountdown()
        }
    }

    /// 暂停倒计时，保留剩余秒数。
    func pauseCountdown() {
        guard countdownState == .running else { return }
        countdownClock.stop()
        countdownState = .paused
    }

    /// 恢复到暂停前的剩余秒数继续计时。
    func resumeCountdown() {
        guard countdownState == .paused else { return }
        countdownState = .running
        scheduleCountdownTicks()
    }

    /// 在运行 / 暂停之间切换；未开始则启动，已结束则忽略。
    func toggleCountdown() {
        switch countdownState {
        case .running:
            pauseCountdown()
        case .paused:
            resumeCountdown()
        case .idle:
            startCountdown()
        case .finished:
            break
        }
    }

    /// 停止倒计时并恢复到未开始状态。
    func stopCountdown() {
        countdownClock.stop()
        countdownDuration = 0
        countdownRemaining = 0
        countdownTotal = 0
        didTimeOut = false
        countdownState = .idle
    }

    private func scheduleCountdownTicks() {
        countdownClock.start(interval: CountdownDefaults.tickInterval) { [weak self] in
            self?.tickCountdown()
        }
    }

    private func finishCountdown() {
        countdownClock.stop()
        countdownRemaining = 0
        didTimeOut = true
        countdownState = .finished
        isInteractionLocked = true
    }

    /// 重开一局时如果倒计时曾经启动过，则按原时长重新计时。
    private func restartCountdownIfNeeded() {
        guard countdownDuration > 0 else { return }
        startCountdown(duration: countdownDuration)
    }

    /// 错配延时结束：翻回卡片并解除交互锁。手动调用同样有效（供测试与兜底使用）。
    func completeMismatchFlipBack() {
        pendingTimerToken = nil

        guard game.hasPendingMismatch else { return }

        // 翻回属于同一次翻牌回合的收尾，先释放动画占用再变更状态。
        animations.endAllFlips()
        game.flipBackMismatch()
        syncFromGame()
        // 时间到后保持锁定，避免翻回任务把超时锁定意外解除。
        isInteractionLocked = countdownState == .finished
    }

    /// 使用当前主题重新开始，解除交互锁并作废未触发的计时回调。
    func newGame() {
        pendingTimerToken = nil
        isInteractionLocked = false
        scoreChangeDelta = 0

        game.newGame()
        syncFromGame()
        boardRevision = animations.beginNewBoard()
        restartCountdownIfNeeded()
    }

    /// 切换主题并重新开始，解除交互锁并作废未触发的计时回调。
    func chooseTheme(_ theme: Theme) {
        pendingTimerToken = nil
        isInteractionLocked = false
        scoreChangeDelta = 0

        game.startNewGame(with: theme)
        syncFromGame()
        boardRevision = animations.beginNewBoard()
        restartCountdownIfNeeded()
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

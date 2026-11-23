import XCTest
@testable import Memorize

/// 计时调度假实现：记录延迟值并保留待触发动作，由测试决定何时“到点”。
final class FakeMismatchTimer: MismatchTimerScheduling {
    private(set) var scheduledDelays: [TimeInterval] = []
    private var pendingActions: [() -> Void] = []

    /// 尚未触发的任务数。
    var pendingCount: Int { pendingActions.count }

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        scheduledDelays.append(delay)
        pendingActions.append(action)
    }

    /// 触发全部已调度但尚未执行的动作。
    func fireAll() {
        let actions = pendingActions
        pendingActions.removeAll()
        actions.forEach { $0() }
    }

    /// 只触发最早调度的那个动作，用于验证过期回调先到的情况。
    func fireNext() {
        guard !pendingActions.isEmpty else { return }
        let action = pendingActions.removeFirst()
        action()
    }
}

/// M4 计时功能测试：验证调度时机、延迟值、过期回调失效与触发后的状态恢复。
final class MismatchTimerTests: XCTestCase {

    // MARK: - 测试辅助

    private func makeTheme(
        name: String = "测试主题",
        emojis: [String] = ["🐶", "🐱", "🐭", "🐹"],
        numberOfPairs: Int? = nil
    ) -> Theme {
        try! Theme(name: name, emojis: emojis, color: .blue, numberOfPairs: numberOfPairs)
    }

    /// 生成不洗牌的牌局，固定为 🐶🐶🐱🐱，便于按下标制造配对与错配。
    private func makeSUT(
        delay: TimeInterval = 0.8
    ) -> (viewModel: GameViewModel, timer: FakeMismatchTimer) {
        let timer = FakeMismatchTimer()
        let viewModel = GameViewModel(
            theme: makeTheme(),
            numberOfPairs: 2,
            shuffle: false,
            mismatchFlipDelay: delay,
            timer: timer
        )
        return (viewModel, timer)
    }

    // MARK: - 调度时机

    func testFirstFlipDoesNotSchedule() {
        let (viewModel, timer) = makeSUT()
        viewModel.choose(viewModel.cards[0])

        XCTAssertTrue(timer.scheduledDelays.isEmpty)
        XCTAssertEqual(timer.pendingCount, 0)
        XCTAssertFalse(viewModel.isInteractionLocked)
    }

    func testMatchedPairDoesNotSchedule() {
        let (viewModel, timer) = makeSUT()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[1])

        XCTAssertTrue(timer.scheduledDelays.isEmpty)
        XCTAssertFalse(viewModel.isInteractionLocked)
    }

    func testMismatchSchedulesOnceWithDefaultDelay() {
        let (viewModel, timer) = makeSUT()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])

        XCTAssertEqual(timer.scheduledDelays, [0.8])
        XCTAssertEqual(timer.pendingCount, 1)
        XCTAssertTrue(viewModel.hasPendingMismatch)
        XCTAssertTrue(viewModel.isInteractionLocked)
    }

    func testCustomDelayIsUsed() {
        let (viewModel, timer) = makeSUT(delay: 0.5)
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])

        XCTAssertEqual(timer.scheduledDelays, [0.5])
        XCTAssertEqual(viewModel.mismatchFlipDelay, 0.5)
    }

    func testLockedPeriodDoesNotScheduleAgain() {
        let (viewModel, timer) = makeSUT()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])
        XCTAssertEqual(timer.pendingCount, 1)

        // 锁定期间点击被忽略，不应产生新的计时任务。
        viewModel.choose(viewModel.cards[1])
        viewModel.choose(viewModel.cards[3])

        XCTAssertEqual(timer.scheduledDelays.count, 1)
        XCTAssertEqual(timer.pendingCount, 1)
        XCTAssertTrue(viewModel.isInteractionLocked)
    }

    // MARK: - 到点执行

    func testTimerFiresFlipsBackAndUnlocks() {
        let (viewModel, timer) = makeSUT()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])
        XCTAssertTrue(viewModel.isInteractionLocked)

        timer.fireAll()

        XCTAssertFalse(viewModel.isInteractionLocked)
        XCTAssertFalse(viewModel.hasPendingMismatch)
        XCTAssertFalse(viewModel.cards[0].isFaceUp)
        XCTAssertFalse(viewModel.cards[2].isFaceUp)
        XCTAssertEqual(timer.pendingCount, 0)
    }

    func testCompleteWithoutPendingMismatchKeepsState() {
        let (viewModel, timer) = makeSUT()
        viewModel.completeMismatchFlipBack()

        XCTAssertEqual(viewModel.score, 0)
        XCTAssertFalse(viewModel.isInteractionLocked)
        XCTAssertTrue(viewModel.cards.allSatisfy { !$0.isFaceUp })
        XCTAssertTrue(timer.scheduledDelays.isEmpty)
    }

    // MARK: - 过期回调

    func testNewGameInvalidatesStaleCallback() {
        let (viewModel, timer) = makeSUT()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])
        viewModel.newGame()

        // 旧任务仍然存在，但令牌已作废，触发后不应改变新牌局状态。
        timer.fireAll()

        XCTAssertFalse(viewModel.isInteractionLocked)
        XCTAssertFalse(viewModel.hasPendingMismatch)
        XCTAssertEqual(viewModel.score, 0)
        XCTAssertTrue(viewModel.cards.allSatisfy { !$0.isFaceUp && !$0.isMatched })
    }

    func testThemeSwitchInvalidatesStaleCallback() {
        let (viewModel, timer) = makeSUT()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])

        let newTheme = makeTheme(name: "水果", emojis: ["🍎", "🍌"], numberOfPairs: 1)
        viewModel.chooseTheme(newTheme)
        timer.fireAll()

        XCTAssertEqual(viewModel.theme.name, "水果")
        XCTAssertEqual(viewModel.cards.count, 2)
        XCTAssertEqual(viewModel.score, 0)
        XCTAssertFalse(viewModel.isInteractionLocked)
    }

    func testMismatchAfterNewGameSchedulesNewTimer() {
        let (viewModel, timer) = makeSUT()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])

        viewModel.newGame()

        // newGame 会洗牌，不能假设固定下标内容不同；按内容显式选取一对错配。
        guard !viewModel.cards.isEmpty,
              let secondIndex = viewModel.cards.indices.first(where: {
                  viewModel.cards[$0].content != viewModel.cards[0].content
              }) else {
            return XCTFail("重开后找不到不同内容的卡片")
        }
        let firstIndex = 0
        viewModel.choose(viewModel.cards[firstIndex])
        viewModel.choose(viewModel.cards[secondIndex])

        XCTAssertEqual(timer.scheduledDelays, [0.8, 0.8])

        // 旧回调先到：令牌不匹配，应被忽略，牌局仍处于锁定等待。
        timer.fireNext()
        XCTAssertTrue(viewModel.isInteractionLocked)
        XCTAssertTrue(viewModel.hasPendingMismatch)

        // 新回调随后到：正常翻回并解锁。
        timer.fireNext()
        XCTAssertFalse(viewModel.isInteractionLocked)
        XCTAssertFalse(viewModel.hasPendingMismatch)
        XCTAssertFalse(viewModel.cards[firstIndex].isFaceUp)
        XCTAssertFalse(viewModel.cards[secondIndex].isFaceUp)
    }
}

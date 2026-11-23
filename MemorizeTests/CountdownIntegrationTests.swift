import XCTest
import SwiftUI
@testable import Memorize

/// 可控倒计时计时器：测试中手动推进，不依赖真实等待。
final class FakeCountdownClock: CountdownClock {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastInterval: TimeInterval?
    private var onTick: (() -> Void)?

    var isRunning: Bool { onTick != nil }

    func start(interval: TimeInterval, onTick: @escaping () -> Void) {
        startCount += 1
        lastInterval = interval
        self.onTick = onTick
    }

    func stop() {
        stopCount += 1
        onTick = nil
    }

    /// 手动推进指定次数。
    func tick(times: Int = 1) {
        for _ in 0..<times {
            onTick?()
        }
    }
}

/// M8 倒计时集成测试：ViewModel 状态机、计时器调度与 Pie 进度换算的协同。
final class CountdownIntegrationTests: XCTestCase {

    // MARK: - 测试辅助

    private func makeTheme(
        name: String = "测试主题",
        emojis: [String] = ["🐶", "🐱", "🐭", "🐹"]
    ) -> Theme {
        try! Theme(name: name, emojis: emojis, color: .blue, numberOfPairs: 2)
    }

    private func makeViewModel(countdown: Int? = nil) -> (GameViewModel, FakeCountdownClock) {
        let clock = FakeCountdownClock()
        let viewModel = GameViewModel(
            theme: makeTheme(),
            numberOfPairs: 2,
            shuffle: false,
            timer: FakeMismatchTimer(),
            countdownClock: clock
        )
        if let countdown {
            viewModel.startCountdown(duration: countdown)
        }
        return (viewModel, clock)
    }

    // MARK: - 初始状态与启动

    func testInitialCountdownIsIdle() {
        let (viewModel, clock) = makeViewModel()

        XCTAssertEqual(viewModel.countdownState, .idle)
        XCTAssertEqual(viewModel.countdownRemaining, 0)
        XCTAssertEqual(viewModel.countdownTotal, 0)
        XCTAssertFalse(viewModel.didTimeOut)
        XCTAssertEqual(clock.startCount, 0)
        XCTAssertFalse(clock.isRunning)
    }

    func testStartCountdownBeginsTicking() {
        let (viewModel, clock) = makeViewModel(countdown: 60)

        XCTAssertEqual(viewModel.countdownState, .running)
        XCTAssertEqual(viewModel.countdownRemaining, 60)
        XCTAssertEqual(viewModel.countdownTotal, 60)
        XCTAssertEqual(clock.startCount, 1)
        XCTAssertEqual(clock.lastInterval ?? 0, CountdownDefaults.tickInterval, accuracy: 0.0001)
        XCTAssertTrue(clock.isRunning)
    }

    func testInvalidDurationDoesNotStart() {
        let (viewModel, clock) = makeViewModel()

        viewModel.startCountdown(duration: 0)
        viewModel.startCountdown(duration: -5)

        XCTAssertEqual(viewModel.countdownState, .idle)
        XCTAssertEqual(clock.startCount, 0)
    }

    func testStartIfNeededOnlyStartsOnce() {
        let (viewModel, clock) = makeViewModel()

        viewModel.startCountdownIfNeeded()
        viewModel.startCountdownIfNeeded()

        XCTAssertEqual(viewModel.countdownState, .running)
        XCTAssertEqual(clock.startCount, 1)
    }

    // MARK: - 计时推进

    func testTickDecrementsRemaining() {
        let (viewModel, clock) = makeViewModel(countdown: 3)

        clock.tick()

        XCTAssertEqual(viewModel.countdownRemaining, 2)
        XCTAssertEqual(viewModel.countdownState, .running)
    }

    func testCountdownFinishesAtZeroAndLocksInteraction() {
        let (viewModel, clock) = makeViewModel(countdown: 2)

        clock.tick(times: 2)

        XCTAssertEqual(viewModel.countdownRemaining, 0)
        XCTAssertEqual(viewModel.countdownState, .finished)
        XCTAssertTrue(viewModel.didTimeOut)
        XCTAssertTrue(viewModel.isInteractionLocked)
        XCTAssertFalse(clock.isRunning)
    }

    func testTickAfterFinishedIsIgnored() {
        let (viewModel, clock) = makeViewModel(countdown: 1)
        clock.tick()

        clock.tick(times: 3)

        XCTAssertEqual(viewModel.countdownRemaining, 0)
        XCTAssertEqual(viewModel.countdownState, .finished)
    }

    func testTickWhilePausedIsIgnored() {
        let (viewModel, clock) = makeViewModel(countdown: 10)

        viewModel.pauseCountdown()
        clock.tick(times: 5)

        XCTAssertEqual(viewModel.countdownRemaining, 10)
        XCTAssertEqual(viewModel.countdownState, .paused)
    }

    // MARK: - 暂停、恢复与停止

    func testPauseKeepsRemainingAndStopsClock() {
        let (viewModel, clock) = makeViewModel(countdown: 10)
        clock.tick(times: 2)

        viewModel.pauseCountdown()

        XCTAssertEqual(viewModel.countdownState, .paused)
        XCTAssertEqual(viewModel.countdownRemaining, 8)
        XCTAssertFalse(clock.isRunning)
    }

    func testResumeContinuesFromRemaining() {
        let (viewModel, clock) = makeViewModel(countdown: 10)
        viewModel.pauseCountdown()

        viewModel.resumeCountdown()

        XCTAssertEqual(viewModel.countdownState, .running)
        XCTAssertEqual(viewModel.countdownRemaining, 10)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.startCount, 2)
    }

    func testToggleCountdownCyclesStates() {
        let (viewModel, _) = makeViewModel(countdown: 10)

        viewModel.toggleCountdown()
        XCTAssertEqual(viewModel.countdownState, .paused)

        viewModel.toggleCountdown()
        XCTAssertEqual(viewModel.countdownState, .running)
    }

    func testStopCountdownResetsState() {
        let (viewModel, clock) = makeViewModel(countdown: 10)
        clock.tick(times: 3)

        viewModel.stopCountdown()

        XCTAssertEqual(viewModel.countdownState, .idle)
        XCTAssertEqual(viewModel.countdownRemaining, 0)
        XCTAssertEqual(viewModel.countdownTotal, 0)
        XCTAssertFalse(viewModel.didTimeOut)
        XCTAssertFalse(clock.isRunning)
    }

    // MARK: - 与牌局生命周期联动

    func testNewGameRestartsCountdown() {
        let (viewModel, clock) = makeViewModel(countdown: 10)
        clock.tick(times: 3)
        XCTAssertEqual(viewModel.countdownRemaining, 7)

        viewModel.newGame()

        XCTAssertEqual(viewModel.countdownState, .running)
        XCTAssertEqual(viewModel.countdownRemaining, 10)
        XCTAssertEqual(viewModel.countdownTotal, 10)
        XCTAssertEqual(viewModel.boardRevision, 1)
        XCTAssertEqual(viewModel.score, 0)
    }

    func testThemeSwitchRestartsCountdown() {
        let (viewModel, clock) = makeViewModel(countdown: 10)
        clock.tick(times: 4)

        let fruit = try! Theme(name: "水果", emojis: ["🍎", "🍌"], color: .pink, numberOfPairs: 1)
        viewModel.chooseTheme(fruit)

        XCTAssertEqual(viewModel.countdownState, .running)
        XCTAssertEqual(viewModel.countdownRemaining, 10)
        XCTAssertEqual(viewModel.theme.name, "水果")
    }

    func testTimeoutLockPersistsAfterMismatchFlipBack() {
        let (viewModel, clock) = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])
        XCTAssertTrue(viewModel.isInteractionLocked)

        viewModel.startCountdown(duration: 2)
        clock.tick(times: 2)

        XCTAssertTrue(viewModel.didTimeOut)
        viewModel.completeMismatchFlipBack()

        XCTAssertTrue(viewModel.isInteractionLocked, "时间到后翻回任务不应解除锁定")
        XCTAssertFalse(viewModel.cards[0].isFaceUp)
    }

    func testProgressFollowsRemainingSeconds() {
        let (viewModel, clock) = makeViewModel(countdown: 10)
        clock.tick(times: 5)

        XCTAssertEqual(viewModel.countdownRemaining, 5)
        XCTAssertEqual(
            PieGeometry.progress(remaining: viewModel.countdownRemaining, total: viewModel.countdownTotal),
            0.5
        )
    }
}

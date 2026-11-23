import XCTest
import SwiftUI
@testable import Memorize

/// 暂停状态机测试：暂停期间拦截输入、停表语义、恢复时的计时归属与重开清理。
final class PauseResumeTests: XCTestCase {

    // MARK: - 测试辅助

    private func makeTheme() -> Theme {
        try! Theme(name: "测试主题", emojis: ["🐶", "🐱", "🐭", "🐹"], color: .blue)
    }

    private func makeViewModel() -> (GameViewModel, FakeCountdownClock) {
        let clock = FakeCountdownClock()
        let viewModel = GameViewModel(
            theme: makeTheme(),
            numberOfPairs: 2,
            shuffle: false,
            timer: FakeMismatchTimer(),
            countdownClock: clock
        )
        return (viewModel, clock)
    }

    // MARK: - 初始状态

    func testInitiallyNotPaused() {
        let (viewModel, _) = makeViewModel()

        XCTAssertFalse(viewModel.isPaused)
        XCTAssertTrue(viewModel.canPause)
        XCTAssertFalse(viewModel.isInteractionLocked)
    }

    // MARK: - 暂停拦截输入

    func testPauseBlocksCardSelection() {
        let (viewModel, _) = makeViewModel()
        viewModel.pause()

        viewModel.choose(viewModel.cards[0])

        XCTAssertTrue(viewModel.isPaused)
        XCTAssertFalse(viewModel.cards[0].isFaceUp, "暂停期间点击不应翻牌")
        XCTAssertNil(viewModel.game.indexOfFaceUpCard)
        XCTAssertEqual(viewModel.score, 0)
    }

    func testPauseKeepsProgress() {
        let (viewModel, _) = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[1])
        viewModel.choose(viewModel.cards[2])
        let scoreBeforePause = viewModel.score
        let matchedBeforePause = viewModel.matchedPairsCount

        viewModel.pause()

        XCTAssertEqual(viewModel.score, scoreBeforePause)
        XCTAssertEqual(viewModel.matchedPairsCount, matchedBeforePause)
        XCTAssertTrue(viewModel.cards[2].isFaceUp, "暂停不应翻回已翻开的卡片")
    }

    // MARK: - 与倒计时联动

    func testPauseStopsCountdownAndResumeRestartsIt() {
        let (viewModel, clock) = makeViewModel()
        viewModel.startCountdown(duration: 10)
        clock.tick(times: 3)

        viewModel.pause()

        XCTAssertEqual(viewModel.countdownState, .paused)
        XCTAssertEqual(viewModel.countdownRemaining, 7)
        XCTAssertFalse(clock.isRunning)

        viewModel.resume()

        XCTAssertEqual(viewModel.countdownState, .running)
        XCTAssertEqual(viewModel.countdownRemaining, 7, "继续后应从剩余时间接着计时")
        XCTAssertTrue(clock.isRunning)
    }

    func testResumeDoesNotStartCountdownThatWasManuallyPaused() {
        let (viewModel, clock) = makeViewModel()
        viewModel.startCountdown(duration: 10)
        viewModel.pauseCountdown()
        let startCountBeforePause = clock.startCount

        viewModel.pause()
        viewModel.resume()

        XCTAssertEqual(viewModel.countdownState, .paused, "手动暂停的倒计时不应被恢复操作唤醒")
        XCTAssertEqual(clock.startCount, startCountBeforePause)
    }

    func testPauseWhenCountdownIdleKeepsItIdle() {
        let (viewModel, clock) = makeViewModel()

        viewModel.pause()
        viewModel.resume()

        XCTAssertEqual(viewModel.countdownState, .idle)
        XCTAssertEqual(clock.startCount, 0)
    }

    // MARK: - 状态机

    func testPauseIsIdempotentAndToggleWorks() {
        let (viewModel, _) = makeViewModel()

        viewModel.pause()
        viewModel.pause()
        XCTAssertTrue(viewModel.isPaused)

        viewModel.togglePause()
        XCTAssertFalse(viewModel.isPaused)

        viewModel.togglePause()
        XCTAssertTrue(viewModel.isPaused)
    }

    func testResumeWithoutPauseIsNoOp() {
        let (viewModel, clock) = makeViewModel()
        viewModel.startCountdown(duration: 10)

        viewModel.resume()

        XCTAssertFalse(viewModel.isPaused)
        XCTAssertEqual(viewModel.countdownState, .running)
        XCTAssertEqual(clock.startCount, 1)
    }

    func testCannotPauseAfterTimeout() {
        let (viewModel, clock) = makeViewModel()
        viewModel.startCountdown(duration: 1)
        clock.tick()

        XCTAssertTrue(viewModel.didTimeOut)
        XCTAssertFalse(viewModel.canPause)

        viewModel.pause()
        XCTAssertFalse(viewModel.isPaused, "超时后不应进入暂停态")
    }

    func testCannotPauseAfterGameOver() {
        let (viewModel, _) = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[1])
        viewModel.choose(viewModel.cards[2])
        viewModel.choose(viewModel.cards[3])

        XCTAssertTrue(viewModel.isGameOver)
        XCTAssertFalse(viewModel.canPause)

        viewModel.pause()
        XCTAssertFalse(viewModel.isPaused)
    }

    func testNewGameClearsPauseState() {
        let (viewModel, _) = makeViewModel()
        viewModel.pause()

        viewModel.newGame()

        XCTAssertFalse(viewModel.isPaused)
        XCTAssertTrue(viewModel.canPause)
        XCTAssertEqual(viewModel.score, 0)
    }

    func testChooseThemeClearsPauseState() {
        let (viewModel, _) = makeViewModel()
        viewModel.pause()

        let fruit = try! Theme(name: "水果", emojis: ["🍎", "🍌"], color: .pink, numberOfPairs: 1)
        viewModel.chooseTheme(fruit)

        XCTAssertFalse(viewModel.isPaused)
        XCTAssertEqual(viewModel.theme.name, "水果")
    }

    // MARK: - 难度联动

    func testDefaultDifficultyDrivesCountdownDurationAndPenalty() {
        let viewModel = GameViewModel(
            difficulty: .hard,
            theme: makeTheme(),
            timer: FakeMismatchTimer(),
            countdownClock: FakeCountdownClock()
        )

        viewModel.startCountdownIfNeeded()

        XCTAssertEqual(viewModel.countdownTotal, Difficulty.hard.countdownDuration)
        XCTAssertEqual(viewModel.difficulty.title, "困难")
        XCTAssertEqual(viewModel.game.rules.repeatMismatchPenalty, 2)
    }

    func testProgressReflectsMatchedPairs() {
        let (viewModel, _) = makeViewModel()
        XCTAssertEqual(viewModel.progress, 0, accuracy: 0.0001)

        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[1])

        XCTAssertEqual(viewModel.progress, 0.5, accuracy: 0.0001)
    }
}

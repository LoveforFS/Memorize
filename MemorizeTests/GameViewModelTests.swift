import XCTest
import SwiftUI
@testable import Memorize

/// M3 视图模型交互测试：翻牌、错配锁定、延时翻回、重开与主题切换。
final class GameViewModelTests: XCTestCase {

    // MARK: - 测试辅助

    private func makeTheme(
        name: String = "测试主题",
        emojis: [String] = ["🐶", "🐱", "🐭", "🐹"],
        numberOfPairs: Int? = nil
    ) -> Theme {
        try! Theme(name: name, emojis: emojis, color: .blue, numberOfPairs: numberOfPairs)
    }

    /// 生成不洗牌的牌局，固定为 🐶🐶🐱🐱，便于按下标验证。
    private func makeViewModel(pairs: Int = 2) -> GameViewModel {
        GameViewModel(theme: makeTheme(), numberOfPairs: pairs, shuffle: false)
    }

    // MARK: - 初始状态

    func testInitialStateIsClean() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.cards.count, 4)
        XCTAssertEqual(viewModel.score, 0)
        XCTAssertEqual(viewModel.matchedPairsCount, 0)
        XCTAssertFalse(viewModel.isGameOver)
        XCTAssertFalse(viewModel.isInteractionLocked)
        XCTAssertFalse(viewModel.hasPendingMismatch)
        XCTAssertEqual(viewModel.theme.name, "测试主题")
    }

    // MARK: - 翻牌

    func testChooseFlipsCardWithoutLocking() {
        let viewModel = makeViewModel()
        viewModel.choose(viewModel.cards[0])

        XCTAssertTrue(viewModel.cards[0].isFaceUp)
        XCTAssertFalse(viewModel.isInteractionLocked)
        XCTAssertEqual(viewModel.game.indexOfFaceUpCard, 0)
    }

    func testRepeatedTapOnSameCardKeepsSingleSelection() {
        let viewModel = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[0])

        XCTAssertEqual(viewModel.game.indexOfFaceUpCard, 0)
        XCTAssertEqual(viewModel.score, 0)
        XCTAssertFalse(viewModel.isInteractionLocked)
    }

    func testMatchingPairScoresTwoAndStaysUnlocked() {
        let viewModel = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[1])

        XCTAssertEqual(viewModel.score, 2)
        XCTAssertEqual(viewModel.matchedPairsCount, 1)
        XCTAssertTrue(viewModel.cards[0].isMatched)
        XCTAssertTrue(viewModel.cards[1].isMatched)
        XCTAssertFalse(viewModel.isInteractionLocked)
        XCTAssertFalse(viewModel.hasPendingMismatch)
    }

    // MARK: - 错配与交互锁

    func testMismatchLocksInteractionAndIgnoresFurtherTaps() {
        let viewModel = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])

        XCTAssertTrue(viewModel.hasPendingMismatch)
        XCTAssertTrue(viewModel.isInteractionLocked)

        let scoreBefore = viewModel.score
        viewModel.choose(viewModel.cards[1])

        XCTAssertEqual(viewModel.score, scoreBefore)
        XCTAssertFalse(viewModel.cards[1].isFaceUp)
        XCTAssertNil(viewModel.game.indexOfFaceUpCard)
        XCTAssertTrue(viewModel.isInteractionLocked)
    }

    func testCompleteMismatchFlipBackUnlocksAndFlipsCards() {
        let viewModel = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])
        XCTAssertTrue(viewModel.isInteractionLocked)

        viewModel.completeMismatchFlipBack()

        XCTAssertFalse(viewModel.isInteractionLocked)
        XCTAssertFalse(viewModel.hasPendingMismatch)
        XCTAssertFalse(viewModel.cards[0].isFaceUp)
        XCTAssertFalse(viewModel.cards[2].isFaceUp)
    }

    func testCompleteMismatchFlipBackWithoutPendingMismatchIsNoOp() {
        let viewModel = makeViewModel()
        viewModel.completeMismatchFlipBack()

        XCTAssertEqual(viewModel.score, 0)
        XCTAssertFalse(viewModel.isInteractionLocked)
        XCTAssertFalse(viewModel.hasPendingMismatch)
        XCTAssertTrue(viewModel.cards.allSatisfy { !$0.isFaceUp })
    }

    func testRepeatedMismatchPenalizesByOne() {
        let viewModel = makeViewModel()

        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])
        XCTAssertEqual(viewModel.score, 0)
        viewModel.completeMismatchFlipBack()

        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])

        XCTAssertEqual(viewModel.score, -1)
        XCTAssertTrue(viewModel.isInteractionLocked)
    }

    // MARK: - 重开与主题切换

    func testNewGameClearsPendingStateAndUnlocks() {
        let viewModel = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])
        XCTAssertTrue(viewModel.isInteractionLocked)

        viewModel.newGame()

        XCTAssertFalse(viewModel.isInteractionLocked)
        XCTAssertFalse(viewModel.hasPendingMismatch)
        XCTAssertEqual(viewModel.score, 0)
        XCTAssertEqual(viewModel.matchedPairsCount, 0)
        XCTAssertFalse(viewModel.isGameOver)
        XCTAssertTrue(viewModel.cards.allSatisfy { !$0.isFaceUp && !$0.isMatched })
    }

    func testChooseThemeResetsGameAndUnlocks() {
        let viewModel = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])
        XCTAssertTrue(viewModel.isInteractionLocked)

        let newTheme = makeTheme(name: "水果", emojis: ["🍎", "🍌"], numberOfPairs: 1)
        viewModel.chooseTheme(newTheme)

        XCTAssertEqual(viewModel.theme.name, "水果")
        XCTAssertEqual(viewModel.cards.count, 2)
        XCTAssertEqual(viewModel.score, 0)
        XCTAssertFalse(viewModel.isInteractionLocked)
        XCTAssertFalse(viewModel.hasPendingMismatch)
        XCTAssertFalse(viewModel.isGameOver)
    }

    // MARK: - 结束状态

    func testChoosingAfterGameOverIsIgnored() {
        let viewModel = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[1])
        viewModel.choose(viewModel.cards[2])
        viewModel.choose(viewModel.cards[3])

        XCTAssertTrue(viewModel.isGameOver)
        XCTAssertEqual(viewModel.score, 4)

        viewModel.choose(viewModel.cards[0])

        XCTAssertEqual(viewModel.score, 4)
        XCTAssertTrue(viewModel.isGameOver)
    }
}

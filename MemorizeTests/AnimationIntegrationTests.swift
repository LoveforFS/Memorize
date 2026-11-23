import XCTest
import SwiftUI
@testable import Memorize

/// M7 动画集成测试：验证 ViewModel 与动画边界控制器协同后的版本号与状态。
final class AnimationIntegrationTests: XCTestCase {

    // MARK: - 测试辅助

    private func makeTheme(
        name: String = "测试主题",
        emojis: [String] = ["🐶", "🐱", "🐭", "🐹"],
        numberOfPairs: Int? = nil
    ) -> Theme {
        try! Theme(name: name, emojis: emojis, color: .blue, numberOfPairs: numberOfPairs)
    }

    /// 生成不洗牌的牌局：🐶🐶🐱🐱，便于按下标验证。
    private func makeViewModel(pairs: Int = 2) -> (GameViewModel, FakeMismatchTimer) {
        let timer = FakeMismatchTimer()
        let viewModel = GameViewModel(theme: makeTheme(), numberOfPairs: pairs, shuffle: false, timer: timer)
        return (viewModel, timer)
    }

    // MARK: - 初始状态

    func testInitialAnimationStateIsIdle() {
        let (viewModel, _) = makeViewModel()

        XCTAssertEqual(viewModel.boardRevision, 0)
        XCTAssertEqual(viewModel.scoreRevision, 0)
        XCTAssertEqual(viewModel.scoreChangeDelta, 0)
        XCTAssertEqual(viewModel.animations.activeFlipCount, 0)
    }

    // MARK: - 翻牌动画

    func testFirstFlipRegistersActiveAnimation() {
        let (viewModel, _) = makeViewModel()
        let card = viewModel.cards[0]

        viewModel.choose(card)

        XCTAssertTrue(viewModel.cards[0].isFaceUp)
        XCTAssertEqual(viewModel.animations.activeFlipCount, 1)
        XCTAssertTrue(viewModel.animations.activeFlipCardIDs.contains(card.id))
        XCTAssertEqual(viewModel.scoreRevision, 0, "翻牌本身不触发得分动画")
    }

    func testRepeatedTapOnSameCardDoesNotDuplicateFlipAnimation() {
        let (viewModel, _) = makeViewModel()
        let card = viewModel.cards[0]

        viewModel.choose(card)
        viewModel.choose(card)

        XCTAssertEqual(viewModel.animations.activeFlipCount, 1, "同一张卡片不应叠加两次翻牌动画")
        XCTAssertEqual(viewModel.score, 0)
    }

    func testEndFlipReleasesAnimationSlot() {
        let (viewModel, _) = makeViewModel()
        let card = viewModel.cards[0]
        viewModel.choose(card)
        XCTAssertEqual(viewModel.animations.activeFlipCount, 1)

        viewModel.endFlip(for: card.id)

        XCTAssertEqual(viewModel.animations.activeFlipCount, 0)
    }

    // MARK: - 得分动画

    func testMatchingPairTriggersScoreAnimationWithDeltaTwo() {
        let (viewModel, _) = makeViewModel()

        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[1])

        XCTAssertEqual(viewModel.score, 2)
        XCTAssertEqual(viewModel.scoreRevision, 1)
        XCTAssertEqual(viewModel.scoreChangeDelta, 2)
    }

    func testMismatchDoesNotTriggerScoreAnimation() {
        let (viewModel, _) = makeViewModel()

        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])

        XCTAssertEqual(viewModel.score, 0)
        XCTAssertEqual(viewModel.scoreRevision, 0, "首次错配不扣分，不应触发得分动画")
        XCTAssertEqual(viewModel.scoreChangeDelta, 0)
        XCTAssertTrue(viewModel.isInteractionLocked)
    }

    func testMismatchFlipBackEndsAllFlipAnimations() {
        let (viewModel, _) = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])
        XCTAssertEqual(viewModel.animations.activeFlipCount, 2)

        viewModel.completeMismatchFlipBack()

        XCTAssertEqual(viewModel.animations.activeFlipCount, 0, "翻回后应释放全部翻牌动画占用")
        XCTAssertFalse(viewModel.isInteractionLocked)
    }

    func testRepeatedMismatchPenaltyReportsNegativeDelta() {
        let (viewModel, _) = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])
        viewModel.completeMismatchFlipBack()

        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])

        XCTAssertEqual(viewModel.score, -1)
        XCTAssertEqual(viewModel.scoreRevision, 1)
        XCTAssertEqual(viewModel.scoreChangeDelta, -1)
    }

    // MARK: - 发牌动画与边界

    func testNewGameResetsBoardRevisionAndClearsAnimations() {
        let (viewModel, _) = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        XCTAssertEqual(viewModel.animations.activeFlipCount, 1)

        viewModel.newGame()

        XCTAssertEqual(viewModel.boardRevision, 1, "重开应触发一次新的发牌动画")
        XCTAssertEqual(viewModel.animations.activeFlipCount, 0)
        XCTAssertEqual(viewModel.scoreRevision, 0, "重开不产生得分动画")
        XCTAssertEqual(viewModel.scoreChangeDelta, 0)
        XCTAssertTrue(viewModel.cards.allSatisfy { !$0.isFaceUp && !$0.isMatched })
    }

    func testThemeSwitchIncrementsBoardRevision() {
        let (viewModel, _) = makeViewModel()
        viewModel.choose(viewModel.cards[0])

        let newTheme = makeTheme(name: "水果", emojis: ["🍎", "🍌"], numberOfPairs: 1)
        viewModel.chooseTheme(newTheme)

        XCTAssertEqual(viewModel.boardRevision, 1)
        XCTAssertEqual(viewModel.animations.activeFlipCount, 0)
        XCTAssertEqual(viewModel.theme.name, "水果")
        XCTAssertEqual(viewModel.scoreChangeDelta, 0)
    }

    func testLockedInteractionDoesNotStartNewAnimations() {
        let (viewModel, _) = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[2])
        XCTAssertTrue(viewModel.isInteractionLocked)
        let activeBefore = viewModel.animations.activeFlipCount

        viewModel.choose(viewModel.cards[1])
        viewModel.choose(viewModel.cards[3])

        XCTAssertEqual(viewModel.animations.activeFlipCount, activeBefore, "锁定期间的点击不应触发新动画")
        XCTAssertEqual(viewModel.scoreRevision, 0)
        XCTAssertTrue(viewModel.isInteractionLocked)
    }

    func testRapidMatchingPairsIncrementScoreRevisionMonotonically() {
        let (viewModel, _) = makeViewModel()

        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[1])
        XCTAssertEqual(viewModel.scoreRevision, 1)

        viewModel.choose(viewModel.cards[2])
        viewModel.choose(viewModel.cards[3])

        XCTAssertEqual(viewModel.scoreRevision, 2, "连续得分应递增版本号")
        XCTAssertEqual(viewModel.scoreChangeDelta, 2)
        XCTAssertEqual(viewModel.score, 4)
        XCTAssertTrue(viewModel.isGameOver)
    }

    func testGameOverSequenceKeepsAnimationStateConsistent() {
        let (viewModel, _) = makeViewModel()
        viewModel.choose(viewModel.cards[0])
        viewModel.choose(viewModel.cards[1])
        viewModel.choose(viewModel.cards[2])
        viewModel.choose(viewModel.cards[3])

        XCTAssertTrue(viewModel.isGameOver)
        XCTAssertEqual(viewModel.scoreRevision, 2)
        XCTAssertEqual(viewModel.boardRevision, 0)
        XCTAssertEqual(viewModel.scoreChangeDelta, 2)
        XCTAssertEqual(viewModel.animations.activeFlipCount, 4)
    }
}

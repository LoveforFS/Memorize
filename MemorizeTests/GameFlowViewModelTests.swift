import XCTest
import SwiftUI
@testable import Memorize

/// 流程视图模型测试：主页 / 牌局切换、继续游戏、重开语义与成绩记录。
final class GameFlowViewModelTests: XCTestCase {

    // MARK: - 测试辅助

    private func makeFlow(
        difficulty: Difficulty = .easy,
        store: GameSettingsStoring = InMemoryGameSettingsStore()
    ) -> GameFlowViewModel {
        GameFlowViewModel(
            settings: GameSettings(difficulty: difficulty, themeName: Theme.builtIn[0].name),
            store: store,
            shuffleNewGames: false
        )
    }

    /// 依次配对全部卡片，把牌局推进到结束状态。
    private func completeGame(_ game: GameViewModel) {
        var guardCount = 0
        while !game.isGameOver, guardCount < 100 {
            guardCount += 1
            guard let first = game.cards.first(where: { !$0.isMatched }) else { break }
            guard let second = game.cards.first(where: {
                !$0.isMatched && $0.content == first.content && $0.id != first.id
            }) else { break }
            game.choose(first)
            game.choose(second)
        }
    }

    // MARK: - 初始状态

    func testInitialPhaseIsHomeWithoutGame() {
        let flow = makeFlow()

        XCTAssertEqual(flow.phase, .home)
        XCTAssertNil(flow.game)
        XCTAssertFalse(flow.canContinue)
        XCTAssertEqual(flow.continueCaption, "暂无进行中的牌局")
    }

    // MARK: - 开新局

    func testStartNewGameUsesSelectedDifficultyAndEntersPlaying() {
        let flow = makeFlow(difficulty: .hard)

        flow.startNewGame()

        XCTAssertEqual(flow.phase, .playing)
        XCTAssertEqual(flow.sessionID, 1)
        XCTAssertEqual(flow.game?.difficulty, .hard)
        XCTAssertEqual(flow.game?.cards.count, Difficulty.hard.cardCount)
        XCTAssertEqual(flow.game?.totalPairs, Difficulty.hard.numberOfPairs)
    }

    func testStartNewGameEachTimeCreatesFreshSession() {
        let flow = makeFlow()

        flow.startNewGame()
        let first = flow.game
        flow.startNewGame()

        XCTAssertEqual(flow.sessionID, 2)
        XCTAssertFalse(flow.game === first, "开新局应替换牌局实例")
        XCTAssertEqual(flow.game?.score, 0)
    }

    // MARK: - 返回主菜单与继续

    func testReturnToHomePausesGameAndEnablesContinue() {
        let flow = makeFlow()
        flow.startNewGame()
        flow.game?.choose(flow.game!.cards[0])

        flow.returnToHome()

        XCTAssertEqual(flow.phase, .home)
        XCTAssertTrue(flow.game?.isPaused ?? false, "返回主页应停表并进入暂停态")
        XCTAssertTrue(flow.canContinue)
        XCTAssertTrue(flow.continueCaption.contains("剩余"), "继续按钮应展示进度摘要")
    }

    func testContinueGameResumesSameGame() {
        let flow = makeFlow()
        flow.startNewGame()
        flow.returnToHome()
        let sameGame = flow.game

        flow.continueGame()

        XCTAssertEqual(flow.phase, .playing)
        XCTAssertTrue(flow.game === sameGame, "继续游戏不应替换牌局实例")
        XCTAssertFalse(flow.game?.isPaused ?? true)
        XCTAssertEqual(flow.sessionID, 1, "继续游戏不应重建界面会话")
    }

    func testContinueIsUnavailableAfterCompletion() {
        let flow = makeFlow()
        flow.startNewGame()
        completeGame(flow.game!)

        XCTAssertTrue(flow.game?.isGameOver ?? false)
        XCTAssertFalse(flow.canContinue)

        flow.continueGame()
        XCTAssertEqual(flow.phase, .playing, "仍在牌局页，不应因 continue 而切换")
    }

    // MARK: - 重开语义

    func testRestartUsesCurrentGameSettingsInsteadOfEditedHomeSettings() {
        let flow = makeFlow(difficulty: .easy)
        flow.startNewGame()
        XCTAssertEqual(flow.game?.difficulty, .easy)

        // 主页 / 设置里改成困难，但进行中的牌局仍是简单。
        flow.settings.difficulty = .hard
        flow.returnToHome()

        flow.restartCurrentGame()

        XCTAssertEqual(flow.game?.difficulty, .easy, "重新开始应沿用当前牌局的难度")
        XCTAssertEqual(flow.game?.cards.count, Difficulty.easy.cardCount)
        XCTAssertEqual(flow.sessionID, 2)
        XCTAssertEqual(flow.phase, .playing)
    }

    func testRestartWithoutGameStartsNewGame() {
        let flow = makeFlow(difficulty: .normal)

        flow.restartCurrentGame()

        XCTAssertEqual(flow.phase, .playing)
        XCTAssertEqual(flow.game?.difficulty, .normal)
        XCTAssertEqual(flow.sessionID, 1)
    }

    // MARK: - 成绩

    func testGameFinishedRecordsBestScorePerDifficulty() {
        let store = InMemoryGameSettingsStore()
        let flow = makeFlow(difficulty: .easy, store: store)
        flow.startNewGame()

        flow.handleGameFinished(score: 8)
        flow.handleGameFinished(score: 4)

        XCTAssertEqual(flow.bestScores[.easy], 8)
        XCTAssertEqual(store.bestScore(for: .easy), 8)
        XCTAssertEqual(flow.bestScores[.hard], 0)
    }

    func testSelectedBestScoreFollowsDifficultySelection() {
        let flow = makeFlow(difficulty: .easy)
        flow.startNewGame()
        flow.handleGameFinished(score: 6)

        XCTAssertEqual(flow.selectedBestScore, 6)

        flow.settings.difficulty = .hard
        XCTAssertEqual(flow.selectedBestScore, 0)
    }

    func testResetBestScoresClearsAllDifficulties() {
        let store = InMemoryGameSettingsStore(bestScores: [.easy: 10, .normal: 4])
        let flow = makeFlow(store: store)

        flow.resetBestScores()

        XCTAssertEqual(flow.bestScores.values.reduce(0, +), 0)
        XCTAssertEqual(store.bestScore(for: .easy), 0)
        XCTAssertEqual(store.bestScore(for: .normal), 0)
    }

    // MARK: - 设置持久化

    func testSettingsChangeIsPersistedImmediately() {
        let store = InMemoryGameSettingsStore()
        let flow = makeFlow(store: store)

        flow.settings = GameSettings(difficulty: .hard, themeName: "运动")

        XCTAssertEqual(store.settings.difficulty, .hard)
        XCTAssertEqual(store.settings.themeName, "运动")
    }

    func testPauseGamePausesOnlyWhenPlaying() {
        let flow = makeFlow()
        flow.pauseGame()
        XCTAssertNil(flow.game)

        flow.startNewGame()
        flow.pauseGame()

        XCTAssertTrue(flow.game?.isPaused ?? false)
        XCTAssertEqual(flow.phase, .playing, "暂停不改变页面，只覆盖暂停浮层")
    }
}

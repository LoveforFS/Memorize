import XCTest
import SwiftUI
@testable import Memorize

/// 难度与设置模型测试：验证三档难度的参数差异、计分规则落地与持久化行为。
final class DifficultyTests: XCTestCase {

    // MARK: - 测试辅助

    private func makeTheme(
        emojis: [String] = ["🐶", "🐱", "🐭", "🐹"]
    ) -> Theme {
        try! Theme(name: "测试主题", emojis: emojis, color: .blue)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MemorizeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - 参数差异

    func testDifficultyProgressionIsMonotonic() {
        let cases = Difficulty.allCases

        for (lhs, rhs) in zip(cases, cases.dropFirst()) {
            XCTAssertLessThan(lhs.numberOfPairs, rhs.numberOfPairs, "牌数应逐档增加")
            XCTAssertGreaterThan(lhs.countdownDuration, rhs.countdownDuration, "时间应逐档减少")
            XCTAssertGreaterThanOrEqual(lhs.mismatchFlipDelay, rhs.mismatchFlipDelay, "翻回延时应逐档变短")
            XCTAssertLessThanOrEqual(
                lhs.scoringRules.repeatMismatchPenalty,
                rhs.scoringRules.repeatMismatchPenalty,
                "罚分应逐档变重"
            )
        }
    }

    func testDifficultyParametersMatchSpecification() {
        XCTAssertEqual(Difficulty.easy.numberOfPairs, 4)
        XCTAssertEqual(Difficulty.easy.cardCount, 8)
        XCTAssertEqual(Difficulty.easy.countdownDuration, 90)
        XCTAssertEqual(Difficulty.easy.scoringRules.repeatMismatchPenalty, 0)

        XCTAssertEqual(Difficulty.normal.numberOfPairs, 6)
        XCTAssertEqual(Difficulty.normal.cardCount, 12)
        XCTAssertEqual(Difficulty.normal.countdownDuration, 60)
        XCTAssertEqual(Difficulty.normal.scoringRules, .standard)

        XCTAssertEqual(Difficulty.hard.numberOfPairs, 8)
        XCTAssertEqual(Difficulty.hard.cardCount, 16)
        XCTAssertEqual(Difficulty.hard.countdownDuration, 45)
        XCTAssertEqual(Difficulty.hard.scoringRules.repeatMismatchPenalty, 2)
    }

    func testDifficultyTextsAreNotEmpty() {
        for difficulty in Difficulty.allCases {
            XCTAssertFalse(difficulty.title.isEmpty)
            XCTAssertFalse(difficulty.subtitle.isEmpty)
            XCTAssertFalse(difficulty.symbolName.isEmpty)
            XCTAssertTrue(difficulty.ruleSummary.contains("\(difficulty.cardCount) 张"))
            XCTAssertTrue(difficulty.ruleSummary.contains("\(difficulty.countdownDuration) 秒"))
        }
    }

    func testEasyRuleSummaryMentionsNoPenalty() {
        XCTAssertTrue(Difficulty.easy.ruleSummary.contains("错配不扣分"))
        XCTAssertTrue(Difficulty.hard.ruleSummary.contains("-2"))
    }

    // MARK: - 计分规则落地

    func testGameUsesDifficultyScoringRules() {
        let game = Game(theme: makeTheme(), numberOfPairs: 2, shuffle: false, rules: Difficulty.easy.scoringRules)

        var mutableGame = game
        mutableGame.choose(mutableGame.cards[0])
        mutableGame.choose(mutableGame.cards[1])

        XCTAssertEqual(mutableGame.score, 2, "简单难度配对同样是 +2")
    }

    func testEasyDifficultyDoesNotPenalizeRepeatedMismatch() {
        var game = Game(theme: makeTheme(), numberOfPairs: 2, shuffle: false, rules: Difficulty.easy.scoringRules)

        game.choose(game.cards[0])
        game.choose(game.cards[2])
        game.flipBackMismatch()
        game.choose(game.cards[0])
        game.choose(game.cards[2])

        XCTAssertEqual(game.score, 0, "简单难度重复错配不扣分")
    }

    func testHardDifficultyPenalizesTwoPointsOnRepeatedMismatch() {
        var game = Game(theme: makeTheme(), numberOfPairs: 2, shuffle: false, rules: Difficulty.hard.scoringRules)

        game.choose(game.cards[0])
        game.choose(game.cards[2])
        game.flipBackMismatch()
        game.choose(game.cards[0])
        game.choose(game.cards[2])

        XCTAssertEqual(game.score, -2, "困难难度重复错配扣 2 分")
    }

    func testFirstMismatchNeverPenalizesRegardlessOfDifficulty() {
        for difficulty in Difficulty.allCases {
            var game = Game(theme: makeTheme(), numberOfPairs: 2, shuffle: false, rules: difficulty.scoringRules)
            game.choose(game.cards[0])
            game.choose(game.cards[2])
            XCTAssertEqual(game.score, 0, "\(difficulty.title)：首次错配不扣分")
        }
    }

    // MARK: - 设置

    func testSettingsResolveThemeAndClampPairs() {
        let settings = GameSettings(difficulty: .hard, themeName: "测试主题")
        XCTAssertEqual(settings.theme.name, "动物", "失效主题名回落到第一个内置主题")

        let generousTheme = Theme.builtIn[0]
        let clamped = GameSettings(difficulty: .hard, themeName: generousTheme.name)
        XCTAssertEqual(clamped.numberOfPairs, min(Difficulty.hard.numberOfPairs, generousTheme.emojis.count))
    }

    func testSettingsFallBackWhenThemeNameIsUnknown() {
        let settings = GameSettings(difficulty: .easy, themeName: "不存在的主题")
        XCTAssertEqual(settings.theme.name, Theme.builtIn[0].name)
    }

    // MARK: - 持久化

    func testStorePersistsSettingsAndBestScores() {
        let defaults = makeUserDefaults()
        let store = UserDefaultsGameSettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings, .default)

        store.settings = GameSettings(difficulty: .hard, themeName: "运动")
        XCTAssertEqual(UserDefaultsGameSettingsStore(defaults: defaults).settings.difficulty, .hard)
        XCTAssertEqual(UserDefaultsGameSettingsStore(defaults: defaults).settings.themeName, "运动")

        store.recordBestScore(8, for: .hard)
        store.recordBestScore(4, for: .hard)
        XCTAssertEqual(store.bestScore(for: .hard), 8, "只保留最高分")
        XCTAssertEqual(store.bestScore(for: .easy), 0)

        store.resetBestScores()
        XCTAssertEqual(store.bestScore(for: .hard), 0)
    }

    func testStoreRepairsUnknownStoredThemeName() {
        let defaults = makeUserDefaults()
        defaults.set("已删除的主题", forKey: "memorize.settings.themeName")
        defaults.set(Difficulty.easy.rawValue, forKey: "memorize.settings.difficulty")

        let settings = UserDefaultsGameSettingsStore(defaults: defaults).settings

        XCTAssertEqual(settings.difficulty, .easy, "有效难度应保留")
        XCTAssertEqual(settings.themeName, Theme.builtIn[0].name, "失效主题名应回落")
    }

    func testInMemoryStoreKeepsBestScorePerDifficulty() {
        let store = InMemoryGameSettingsStore()

        store.recordBestScore(6, for: .normal)
        store.recordBestScore(3, for: .normal)
        store.recordBestScore(9, for: .hard)

        XCTAssertEqual(store.bestScore(for: .normal), 6)
        XCTAssertEqual(store.bestScore(for: .hard), 9)
    }
}

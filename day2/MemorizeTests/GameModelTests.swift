import XCTest
import SwiftUI
@testable import Memorize

/// M2 数据模型单元测试：Theme、Card、Game。
final class GameModelTests: XCTestCase {

    // MARK: - 测试辅助

    private func makeTheme(
        name: String = "测试主题",
        emojis: [String] = ["🐶", "🐱", "🐭", "🐹"],
        numberOfPairs: Int? = nil
    ) -> Theme {
        try! Theme(name: name, emojis: emojis, color: .blue, numberOfPairs: numberOfPairs)
    }

    /// 生成不洗牌的牌局，便于按固定下标验证逻辑（默认两对：🐶🐶🐱🐱）。
    private func makeGame(pairs: Int = 2) -> Game {
        Game(theme: makeTheme(), numberOfPairs: pairs, shuffle: false)
    }

    // MARK: - Theme

    func testThemeTrimsNameAndEmojis() throws {
        let theme = try Theme(
            name: "  动物  ",
            emojis: ["  🐶 ", "", "🐱"],
            color: .orange
        )

        XCTAssertEqual(theme.name, "动物")
        XCTAssertEqual(theme.emojis, ["🐶", "🐱"])
        XCTAssertEqual(theme.numberOfPairs, 2)
    }

    func testThemeWithEmptyNameThrows() {
        XCTAssertThrowsError(try Theme(name: "   ", emojis: ["🐶"], color: .red)) { error in
            XCTAssertEqual(error as? Theme.ValidationError, Theme.ValidationError.emptyName)
        }
    }

    func testThemeWithoutEmojisThrows() {
        XCTAssertThrowsError(try Theme(name: "空主题", emojis: [], color: .red)) { error in
            XCTAssertEqual(error as? Theme.ValidationError, Theme.ValidationError.emptyEmojiSet)
        }

        XCTAssertThrowsError(try Theme(name: "空白主题", emojis: [" ", "\n"], color: .red)) { error in
            XCTAssertEqual(error as? Theme.ValidationError, Theme.ValidationError.emptyEmojiSet)
        }
    }

    func testThemeWithNonPositivePairsThrows() {
        for pairs in [0, -3] {
            XCTAssertThrowsError(
                try Theme(name: "非法对数", emojis: ["🐶", "🐱"], color: .red, numberOfPairs: pairs)
            ) { error in
                XCTAssertEqual(error as? Theme.ValidationError, Theme.ValidationError.invalidNumberOfPairs(pairs))
            }
        }
    }

    func testThemeClampsPairsToEmojiCount() {
        let theme = makeTheme(numberOfPairs: 99)
        XCTAssertEqual(theme.numberOfPairs, theme.emojis.count)
    }

    func testBuiltInThemesAreValid() {
        XCTAssertEqual(Theme.builtIn.count, 6)
        XCTAssertEqual(Set(Theme.builtIn.map(\.name)).count, Theme.builtIn.count)

        for theme in Theme.builtIn {
            XCTAssertFalse(theme.name.isEmpty)
            XCTAssertFalse(theme.emojis.isEmpty)
            XCTAssertEqual(theme.numberOfPairs, theme.emojis.count)
        }
    }

    // MARK: - Card

    func testCardDefaultState() {
        let card = Card(content: "🐶")

        XCTAssertFalse(card.isFaceUp)
        XCTAssertFalse(card.isMatched)
        XCTAssertEqual(card.content, "🐶")
    }

    func testCardTrimsContent() {
        XCTAssertEqual(Card(content: "  🐱  ").content, "🐱")
    }

    func testCardEqualityUsesIdentity() {
        let id = UUID()
        let card = Card(id: id, content: "🐶")
        let sameCardAfterFlip = Card(id: id, content: "🐶", isFaceUp: true, isMatched: true)
        let anotherCard = Card(content: "🐶")

        XCTAssertEqual(card, sameCardAfterFlip)
        XCTAssertNotEqual(card, anotherCard)
    }

    // MARK: - 牌组生成

    func testDeckContainsTwoCardsPerPair() {
        let deck = Game.makeDeck(emojis: ["🐶", "🐱", "🐭"], numberOfPairs: 3, shuffle: false)

        XCTAssertEqual(deck.count, 6)
        XCTAssertEqual(Set(deck.map(\.content)), ["🐶", "🐱", "🐭"])
        XCTAssertEqual(Set(deck.map(\.id)).count, deck.count)
    }

    func testUnshuffledDeckKeepsPairsTogether() {
        let deck = Game.makeDeck(emojis: ["🐶", "🐱"], numberOfPairs: 2, shuffle: false)

        XCTAssertEqual(deck.map(\.content), ["🐶", "🐶", "🐱", "🐱"])
    }

    func testDeckClampsOutOfRangePairs() {
        XCTAssertEqual(
            Game.makeDeck(emojis: ["🐶", "🐱"], numberOfPairs: 0, shuffle: false).count,
            2
        )
        XCTAssertEqual(
            Game.makeDeck(emojis: ["🐶", "🐱"], numberOfPairs: 5, shuffle: false).count,
            4
        )
    }

    func testShuffleKeepsContentMultiset() {
        let emojis = ["🐶", "🐱", "🐭", "🐹"]
        let shuffled = Game.makeDeck(emojis: emojis, numberOfPairs: 4, shuffle: true)

        XCTAssertEqual(shuffled.map(\.content).sorted(), (emojis + emojis).sorted())
        XCTAssertEqual(Set(shuffled.map(\.id)).count, shuffled.count)
    }

    func testGameInitializerClampsNumberOfPairs() {
        let theme = makeTheme(emojis: ["🐶", "🐱"])
        let game = Game(theme: theme, numberOfPairs: 5, shuffle: false)

        XCTAssertEqual(game.numberOfPairs, 2)
        XCTAssertEqual(game.cards.count, 4)
    }

    func testGameUsesThemePairCountByDefault() {
        let theme = makeTheme(emojis: ["🐶", "🐱", "🐭"])
        let game = Game(theme: theme)

        XCTAssertEqual(game.numberOfPairs, 3)
        XCTAssertEqual(game.cards.count, 6)
        XCTAssertEqual(Set(game.cards.map(\.content)), Set(theme.emojis))
        XCTAssertEqual(game.theme.name, theme.name)
    }

    // MARK: - 翻牌与配对

    func testNewGameHasCleanState() {
        let game = makeGame()

        XCTAssertEqual(game.cards.count, 4)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.matchedPairsCount, 0)
        XCTAssertFalse(game.isGameOver)
        XCTAssertNil(game.indexOfFaceUpCard)
        XCTAssertTrue(game.cards.allSatisfy { !$0.isFaceUp && !$0.isMatched })
    }

    func testChooseFlipsCard() {
        var game = makeGame()
        game.choose(game.cards[0])

        XCTAssertTrue(game.cards[0].isFaceUp)
        XCTAssertEqual(game.indexOfFaceUpCard, 0)
        XCTAssertEqual(game.score, 0)
    }

    func testChoosingSameFaceUpCardTwiceIsIgnored() {
        var game = makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[0])

        XCTAssertEqual(game.indexOfFaceUpCard, 0)
        XCTAssertEqual(game.score, 0)

        // 仍然可以与它的配对卡片成功配对。
        game.choose(game.cards[1])
        XCTAssertEqual(game.score, 2)
    }

    func testMatchingPairScoresTwoAndStaysFaceUp() {
        var game = makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[1])

        XCTAssertEqual(game.score, 2)
        XCTAssertEqual(game.matchedPairsCount, 1)
        XCTAssertTrue(game.cards[0].isMatched)
        XCTAssertTrue(game.cards[1].isMatched)
        XCTAssertTrue(game.cards[0].isFaceUp)
        XCTAssertTrue(game.cards[1].isFaceUp)
        XCTAssertNil(game.indexOfFaceUpCard)
    }

    func testFirstMismatchKeepsScoreAndFlipsBack() {
        var game = makeGame()
        game.choose(game.cards[0]) // 🐶
        game.choose(game.cards[2]) // 🐱

        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.matchedPairsCount, 0)
        XCTAssertFalse(game.cards[0].isFaceUp)
        XCTAssertFalse(game.cards[2].isFaceUp)
        XCTAssertNil(game.indexOfFaceUpCard)
    }

    func testRepeatedMismatchPenalizesByOne() {
        var game = makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[2])
        XCTAssertEqual(game.score, 0)

        // 两张卡片都翻看过，再次错配扣 1 分。
        game.choose(game.cards[0])
        game.choose(game.cards[2])

        XCTAssertEqual(game.score, -1)
        XCTAssertFalse(game.cards[0].isFaceUp)
        XCTAssertFalse(game.cards[2].isFaceUp)
    }

    func testChoosingMatchedCardIsIgnored() {
        var game = makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[1])
        XCTAssertEqual(game.score, 2)

        game.choose(game.cards[0])

        XCTAssertEqual(game.score, 2)
        XCTAssertEqual(game.matchedPairsCount, 1)
    }

    func testChoosingUnknownCardIsIgnored() {
        var game = makeGame()
        game.choose(Card(content: "🦊"))

        XCTAssertEqual(game.score, 0)
        XCTAssertNil(game.indexOfFaceUpCard)
        XCTAssertTrue(game.cards.allSatisfy { !$0.isFaceUp })
    }

    func testGameOverAfterAllPairsMatched() {
        var game = makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[1])
        game.choose(game.cards[2])
        game.choose(game.cards[3])

        XCTAssertEqual(game.score, 4)
        XCTAssertEqual(game.matchedPairsCount, 2)
        XCTAssertTrue(game.isGameOver)
    }

    // MARK: - 重开一局

    func testNewGameResetsState() {
        var game = makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[1])
        XCTAssertEqual(game.score, 2)

        game.newGame(shuffle: false)

        XCTAssertEqual(game.cards.count, 4)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.matchedPairsCount, 0)
        XCTAssertFalse(game.isGameOver)
        XCTAssertNil(game.indexOfFaceUpCard)
        XCTAssertTrue(game.cards.allSatisfy { !$0.isFaceUp && !$0.isMatched })
        XCTAssertEqual(game.theme.name, "测试主题")
    }

    func testStartNewGameSwitchesThemeAndResetsState() {
        var game = makeGame()
        game.choose(game.cards[0])
        game.choose(game.cards[1])
        XCTAssertEqual(game.score, 2)

        let newTheme = makeTheme(name: "水果", emojis: ["🍎", "🍌"], numberOfPairs: 1)
        game.startNewGame(with: newTheme, shuffle: false)

        XCTAssertEqual(game.theme.name, "水果")
        XCTAssertEqual(game.numberOfPairs, 1)
        XCTAssertEqual(game.cards.count, 2)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.matchedPairsCount, 0)
        XCTAssertFalse(game.isGameOver)
        XCTAssertTrue(game.cards.allSatisfy { !$0.isFaceUp && !$0.isMatched })
    }
}

import Foundation

/// 牌局模型：维护卡片数组、当前翻开的卡片与得分，不依赖任何 UI 框架。
///
/// 规则：
/// - 每对对子的内容相同，牌组由 `makeDeck` 生成并按需洗牌；
/// - 每次只允许一张卡片处于“待配对”状态，翻开第二张时立即判定；
/// - 配对成功：两张卡片保持正面，按 `rules.pointsPerMatch` 加分（默认 +2）；
/// - 配对失败：两张卡片先保持正面，延时后由 `flipBackMismatch()` 翻回；
///   若其中任一张在本局中已经翻看过，按 `rules.repeatMismatchPenalty` 扣分（默认 -1）；
/// - 已配对或已翻开的卡片再次点击会被忽略。
struct Game {
    /// 当前牌组。
    private(set) var cards: [Card]
    /// 当前得分（重复错配可能为负）。
    private(set) var score: Int = 0
    /// 当前使用的主题。
    private(set) var theme: Theme
    /// 当前主题实际使用的卡片对数（可能小于主题的 emoji 数量）。
    private(set) var numberOfPairs: Int
    /// 计分规则，由难度决定；默认沿用标准规则。
    private(set) var rules: ScoringRules
    /// 已翻开、等待配对的卡片下标。
    private(set) var indexOfFaceUpCard: Int?
    /// 本局中已经参与过完整翻牌回合的卡片 id，用于重复错配扣分。
    private var seenCardIDs: Set<UUID> = []
    /// 错配后仍保持正面、等待延时翻回的卡片 id。
    private var mismatchedCardIDs: [UUID] = []

    /// 是否全部配对完成。
    var isGameOver: Bool {
        !cards.isEmpty && cards.allSatisfy { $0.isMatched }
    }

    /// 是否存在等待延时翻回的错配卡片。
    var hasPendingMismatch: Bool {
        !mismatchedCardIDs.isEmpty
    }

    /// 已配对的牌数。
    var matchedPairsCount: Int {
        cards.filter { $0.isMatched }.count / 2
    }

    init(
        theme: Theme,
        numberOfPairs: Int? = nil,
        shuffle: Bool = true,
        rules: ScoringRules = .standard
    ) {
        let pairs = Game.clamp(numberOfPairs ?? theme.numberOfPairs, to: theme.emojis.count)

        self.theme = theme
        self.numberOfPairs = pairs
        self.rules = rules
        self.cards = Game.makeDeck(emojis: theme.emojis, numberOfPairs: pairs, shuffle: shuffle)
    }

    /// 生成牌组：每个 emoji 生成两张卡片，可选洗牌。
    /// - Parameters:
    ///   - emojis: 可用 emoji 集合。
    ///   - numberOfPairs: 卡片对数，超过 emoji 数量时按可用数量截断。
    ///   - shuffle: 是否打乱顺序。
    static func makeDeck(emojis: [String], numberOfPairs: Int, shuffle: Bool = true) -> [Card] {
        let pairs = clamp(numberOfPairs, to: emojis.count)
        let selected = emojis.prefix(pairs)

        var deck = selected.flatMap { emoji in
            [Card(content: emoji), Card(content: emoji)]
        }
        if shuffle {
            deck.shuffle()
        }
        return deck
    }

    /// 翻开一张卡片。若这是本回合第二张，则立即判定配对结果。
    ///
    /// 配对失败时两张卡片保持正面，由调用方在延时结束后调用
    /// `flipBackMismatch()` 翻回，以便视图层展示“错配延时翻回”效果。
    mutating func choose(_ card: Card) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        guard !cards[index].isMatched, !cards[index].isFaceUp else { return }

        // 上一回合的错配卡片尚未翻回时先复位，保证同一时刻最多两张正面。
        flipBackMismatch()
        cards[index].isFaceUp = true

        guard let firstIndex = indexOfFaceUpCard, firstIndex != index else {
            indexOfFaceUpCard = index
            return
        }

        if cards[firstIndex].content == cards[index].content {
            // 配对成功：两张都标记为已配对并保持正面。
            cards[firstIndex].isMatched = true
            cards[index].isMatched = true
            score += rules.pointsPerMatch
        } else {
            // 配对失败：只要任一张之前翻看过，就按规则扣分；两张保持正面等待翻回。
            let hasSeenBefore = seenCardIDs.contains(cards[firstIndex].id)
                || seenCardIDs.contains(cards[index].id)
            if hasSeenBefore {
                score -= rules.repeatMismatchPenalty
            }
            mismatchedCardIDs = [cards[firstIndex].id, cards[index].id]
        }

        seenCardIDs.insert(cards[firstIndex].id)
        seenCardIDs.insert(cards[index].id)
        indexOfFaceUpCard = nil
    }

    /// 把错配的卡片翻回背面。无待翻回卡片时调用不会有任何变化。
    mutating func flipBackMismatch() {
        guard !mismatchedCardIDs.isEmpty else { return }

        for id in mismatchedCardIDs {
            if let index = cards.firstIndex(where: { $0.id == id }) {
                cards[index].isFaceUp = false
            }
        }
        mismatchedCardIDs.removeAll()
    }

    /// 使用当前主题重新开始一局。
    mutating func newGame(shuffle: Bool = true) {
        reset(theme: theme, numberOfPairs: numberOfPairs, shuffle: shuffle)
    }

    /// 切换主题并重新开始一局。
    mutating func startNewGame(with newTheme: Theme, shuffle: Bool = true) {
        reset(
            theme: newTheme,
            numberOfPairs: Game.clamp(newTheme.numberOfPairs, to: newTheme.emojis.count),
            shuffle: shuffle
        )
    }

    /// 重置牌局状态。
    private mutating func reset(theme newTheme: Theme, numberOfPairs pairs: Int, shuffle: Bool) {
        theme = newTheme
        numberOfPairs = pairs
        cards = Game.makeDeck(emojis: newTheme.emojis, numberOfPairs: pairs, shuffle: shuffle)
        score = 0
        indexOfFaceUpCard = nil
        seenCardIDs.removeAll()
        mismatchedCardIDs.removeAll()
    }

    /// 把卡片对数限制在 1...可用数量 的范围内。
    private static func clamp(_ pairs: Int, to emojiCount: Int) -> Int {
        max(1, min(pairs, emojiCount))
    }
}

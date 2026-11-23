import Foundation

/// 玩家偏好：难度与主题，可跨启动保留。
///
/// 主题按名称保存而不是按 `Theme.id`：内置主题的 id 每次启动都会重新生成，
/// 名称才是稳定的持久化标识。
struct GameSettings: Equatable {
    var difficulty: Difficulty
    var themeName: String

    /// 首次启动的默认配置。
    static let `default` = GameSettings(difficulty: .normal, themeName: Theme.builtIn[0].name)

    init(difficulty: Difficulty = .normal, themeName: String = Theme.builtIn[0].name) {
        self.difficulty = difficulty
        self.themeName = themeName
    }

    /// 按名称解析内置主题；名称失效时回落到第一个主题，保证永远有牌可发。
    var theme: Theme {
        Theme.builtIn.first { $0.name == themeName } ?? Theme.builtIn[0]
    }

    /// 本局实际卡片对数：难度对数与主题可用 emoji 数量取小值。
    var numberOfPairs: Int {
        max(1, min(difficulty.numberOfPairs, theme.emojis.count))
    }
}

/// 设置与最佳成绩的持久化抽象。
///
/// 抽出协议的目的：生产环境用 `UserDefaults`，单元测试、预览与 UI 自动化用内存实现，
/// 避免测试之间通过真机存储互相污染（例如「继续游戏」在上一次测试后仍可用）。
protocol GameSettingsStoring: AnyObject {
    var settings: GameSettings { get set }
    func bestScore(for difficulty: Difficulty) -> Int
    func recordBestScore(_ score: Int, for difficulty: Difficulty)
    func resetBestScores()
}

/// 内存实现：进程结束后即丢弃。
final class InMemoryGameSettingsStore: GameSettingsStoring {
    var settings: GameSettings
    private var bestScores: [Difficulty: Int]

    init(settings: GameSettings = .default, bestScores: [Difficulty: Int] = [:]) {
        self.settings = settings
        self.bestScores = bestScores
    }

    func bestScore(for difficulty: Difficulty) -> Int {
        bestScores[difficulty] ?? 0
    }

    func recordBestScore(_ score: Int, for difficulty: Difficulty) {
        bestScores[difficulty] = max(bestScore(for: difficulty), score)
    }

    func resetBestScores() {
        bestScores.removeAll()
    }
}

/// 生产实现：键名统一带前缀，读取到非法值时回落到默认配置。
final class UserDefaultsGameSettingsStore: GameSettingsStoring {
    private enum Key {
        static let difficulty = "memorize.settings.difficulty"
        static let themeName = "memorize.settings.themeName"

        static func bestScore(_ difficulty: Difficulty) -> String {
            "memorize.bestScore.\(difficulty.rawValue)"
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var settings: GameSettings {
        get {
            let difficulty = defaults.string(forKey: Key.difficulty)
                .flatMap(Difficulty.init(rawValue:)) ?? GameSettings.default.difficulty

            // 主题名可能来自旧版本或已被移除的配置，校验通过后才使用。
            let storedThemeName = defaults.string(forKey: Key.themeName)
            let themeName = Theme.builtIn.first { $0.name == storedThemeName }?.name
                ?? GameSettings.default.themeName

            return GameSettings(difficulty: difficulty, themeName: themeName)
        }
        set {
            defaults.set(newValue.difficulty.rawValue, forKey: Key.difficulty)
            defaults.set(newValue.themeName, forKey: Key.themeName)
        }
    }

    func bestScore(for difficulty: Difficulty) -> Int {
        defaults.integer(forKey: Key.bestScore(difficulty))
    }

    func recordBestScore(_ score: Int, for difficulty: Difficulty) {
        guard score > bestScore(for: difficulty) else { return }
        defaults.set(score, forKey: Key.bestScore(difficulty))
    }

    func resetBestScores() {
        for difficulty in Difficulty.allCases {
            defaults.removeObject(forKey: Key.bestScore(difficulty))
        }
    }
}

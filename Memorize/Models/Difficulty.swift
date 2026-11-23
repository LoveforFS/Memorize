import SwiftUI

/// 计分规则：配对得分与「重复错配」的罚分。
///
/// 抽成独立值类型后，`Game` 不再内置写死的 +2 / -1，
/// 难度只需要提供一份规则，模型与界面共享同一份定义。
struct ScoringRules: Equatable {
    /// 配对成功一次加多少分。
    let pointsPerMatch: Int
    /// 同一张卡片再次翻错时扣多少分（首次错配不扣分）。
    let repeatMismatchPenalty: Int

    /// 沿用的标准规则：配对 +2、重复错配 -1。
    static let standard = ScoringRules(pointsPerMatch: 2, repeatMismatchPenalty: 1)
}

/// 难度：决定牌组规模、倒计时时长、错配翻回速度与计分规则。
///
/// 四个维度同时变化，保证「简单 / 普通 / 困难」有可感知的差异：
/// - 牌越多，需要同时记住的信息越多；
/// - 时间越短，容错空间越小；
/// - 翻回越快，可记忆的窗口越短；
/// - 罚分越重，反复翻错越吃亏。
enum Difficulty: String, CaseIterable, Identifiable {
    case easy
    case normal
    case hard

    var id: String { rawValue }

    /// 展示名称。
    var title: String {
        switch self {
        case .easy: return "简单"
        case .normal: return "普通"
        case .hard: return "困难"
        }
    }

    /// 一句话描述，用于首页与设置页的难度卡片。
    var subtitle: String {
        switch self {
        case .easy: return "时间充裕，错配不扣分"
        case .normal: return "标准规则，适合日常练习"
        case .hard: return "牌多时间紧，翻错扣两分"
        }
    }

    /// 卡片对数；主题 emoji 不足时由 `GameSettings` 按可用数量截断。
    var numberOfPairs: Int {
        switch self {
        case .easy: return 4
        case .normal: return 6
        case .hard: return 8
        }
    }

    /// 卡片张数。
    var cardCount: Int { numberOfPairs * 2 }

    /// 每局倒计时秒数。
    var countdownDuration: Int {
        switch self {
        case .easy: return 90
        case .normal: return 60
        case .hard: return 45
        }
    }

    /// 错配后卡片保持正面的时长（秒），同时也是玩家额外的记忆时间。
    var mismatchFlipDelay: TimeInterval {
        switch self {
        case .easy: return 1.1
        case .normal: return 0.8
        case .hard: return 0.6
        }
    }

    /// 计分规则：简单不罚分，普通 -1，困难 -2。
    var scoringRules: ScoringRules {
        switch self {
        case .easy: return ScoringRules(pointsPerMatch: 2, repeatMismatchPenalty: 0)
        case .normal: return .standard
        case .hard: return ScoringRules(pointsPerMatch: 2, repeatMismatchPenalty: 2)
        }
    }

    /// 规则摘要，例如「8 张 · 90 秒 · 错配不扣分」。
    var ruleSummary: String {
        let penalty = scoringRules.repeatMismatchPenalty == 0
            ? "错配不扣分"
            : "重复翻错 -\(scoringRules.repeatMismatchPenalty)"
        return "\(cardCount) 张 · \(countdownDuration) 秒 · \(penalty)"
    }

    /// 难度图标。
    var symbolName: String {
        switch self {
        case .easy: return "leaf"
        case .normal: return "square.grid.2x2"
        case .hard: return "flame"
        }
    }

    /// 难度强调色。
    var tint: Color {
        switch self {
        case .easy: return .green
        case .normal: return .blue
        case .hard: return .orange
        }
    }
}

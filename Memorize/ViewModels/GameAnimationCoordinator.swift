import Foundation

/// M7 动画边界控制器：集中判定“哪些状态变化可以触发动画”，避免快速操作造成动画冲突。
///
/// 规则：
/// - 同一张卡片在翻牌动画结束前只触发一次动画，重复点击不叠加；
/// - 得分只在数值真正变化时递增版本号，连续变化以最新一次为准；
/// - 新牌局会作废所有进行中的翻牌动画，并递增牌局版本号驱动发牌动画。
final class GameAnimationCoordinator {
    /// 牌局版本号：每次重开或切换主题递增，视图据此重新播放发牌动画。
    private(set) var boardRevision = 0
    /// 得分版本号：每次得分变化递增，视图据此触发数值跳动与缩放。
    private(set) var scoreRevision = 0
    /// 正在播放翻牌动画的卡片 id。
    private(set) var activeFlipCardIDs: Set<UUID> = []

    /// 当前进行中的翻牌动画数量。
    var activeFlipCount: Int { activeFlipCardIDs.count }

    /// 开始新牌局：清空进行中的翻牌动画并递增牌局版本号。
    /// - Returns: 新的牌局版本号，供视图驱动错峰发牌。
    @discardableResult
    func beginNewBoard() -> Int {
        activeFlipCardIDs.removeAll()
        boardRevision += 1
        return boardRevision
    }

    /// 尝试为某张卡片开始翻牌动画。
    /// - Returns: `true` 表示允许播放；同一张卡片正在播放时返回 `false`，避免动画叠加。
    @discardableResult
    func beginFlip(for cardID: UUID) -> Bool {
        guard !activeFlipCardIDs.contains(cardID) else { return false }
        activeFlipCardIDs.insert(cardID)
        return true
    }

    /// 翻牌动画结束，释放该卡片的动画占用。
    func endFlip(for cardID: UUID) {
        activeFlipCardIDs.remove(cardID)
    }

    /// 结束全部翻牌动画（错配翻回或新牌局时调用）。
    func endAllFlips() {
        activeFlipCardIDs.removeAll()
    }

    /// 记录一次得分变化。
    /// - Returns: 发生变化时返回新的得分版本号；数值未变时返回 `nil`，视图不播放动画。
    func scoreDidChange(from oldValue: Int, to newValue: Int) -> Int? {
        guard oldValue != newValue else { return nil }
        scoreRevision += 1
        return scoreRevision
    }
}

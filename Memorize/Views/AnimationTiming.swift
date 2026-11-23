import SwiftUI

/// M7 动画参数与节奏策略：集中管理时长、错峰延迟与得分反馈幅度。
///
/// 所有参数都放在这里，视图只引用、不硬编码，便于统一调整与单元测试。
enum AnimationTiming {
    /// 翻牌 3D 旋转时长（秒）。
    static let flipDuration: Double = 0.45
    /// 单张卡片发牌动画时长（秒）。
    static let dealDuration: Double = 0.35
    /// 相邻卡片的发牌间隔（秒）。
    static let dealStagger: Double = 0.06
    /// 发牌延迟上限（秒），避免卡片数量多时末尾等待过久。
    static let dealMaxStagger: Double = 0.6
    /// 得分弹跳动画时长（秒）。
    static let scorePopDuration: Double = 0.3
    /// 得分弹跳的最大缩放倍数。
    static let scorePopScale: CGFloat = 1.25
    /// 得分变化量悬浮提示的可见时长（秒）。
    static let scoreDeltaVisibleDuration: Double = 0.7
    /// 主页与牌局之间的页面切换时长（秒）。
    static let pageTransitionDuration: Double = 0.28

    /// 翻牌动画：缓入缓出，保证旋转过程平滑、无突兀停顿。
    static var flip: Animation { .easeInOut(duration: flipDuration) }
    /// 发牌动画：缓出，卡片落位时减速，视觉上更自然。
    static var deal: Animation { .easeOut(duration: dealDuration) }
    /// 得分动画：带阻尼的弹簧，产生一次清晰可感知的回弹。
    static var score: Animation { .spring(response: scorePopDuration, dampingFraction: 0.62) }
    /// 得分缩放复位：短促缓出，避免与下一次加分动画叠加。
    static var scoreReset: Animation { .easeOut(duration: 0.18) }
    /// 页面切换：缓入缓出，主页与牌局横向推开。
    static var pageTransition: Animation { .easeInOut(duration: pageTransitionDuration) }
    /// 暂停浮层：短促淡入淡出，不拖慢操作反馈。
    static var pause: Animation { .easeInOut(duration: 0.2) }
    /// 难度等小型选中反馈。
    static var selection: Animation { .easeOut(duration: 0.18) }

    /// 第 index 张卡片的发牌延迟：按下标线性错峰，并封顶。
    static func dealDelay(forCardAt index: Int) -> Double {
        guard index > 0 else { return 0 }
        return min(Double(index) * dealStagger, dealMaxStagger)
    }

    /// 得分变化量（正数为加分，负数为扣分）。
    static func scoreDelta(from oldValue: Int, to newValue: Int) -> Int {
        newValue - oldValue
    }
}

import Foundation

/// 错配翻回的计时调度抽象。
///
/// 把延时能力从视图层抽出，既让 ViewModel 负责调度，又便于在单元测试中
/// 注入假计时器，精确验证“调度延迟值、是否重复调度、过期回调是否失效”。
protocol MismatchTimerScheduling {
    /// 在 `delay` 秒后执行一次 `action`。
    func schedule(after delay: TimeInterval, action: @escaping () -> Void)
}

/// 生产实现：基于主队列的延时调度。
struct DispatchMismatchTimer: MismatchTimerScheduling {
    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
}

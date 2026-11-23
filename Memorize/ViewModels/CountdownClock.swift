import Foundation

/// 倒计时状态（M8）。
enum CountdownState: String, Equatable {
    /// 尚未开始。
    case idle
    /// 正在计时。
    case running
    /// 已暂停。
    case paused
    /// 已结束（时间耗尽）。
    case finished
}

/// 倒计时默认参数。
enum CountdownDefaults {
    /// 每局初始倒计时秒数。
    static let duration = 60
    /// 计时器触发间隔（秒）。
    static let tickInterval: TimeInterval = 1
}

/// 周期计时器抽象：便于在测试中注入可控实现，避免真实等待。
protocol CountdownClock: AnyObject {
    /// 以固定间隔重复触发 `onTick`；重复调用会先停止旧计时。
    func start(interval: TimeInterval, onTick: @escaping () -> Void)
    /// 停止计时。
    func stop()
}

/// 生产实现：基于 `Timer` 的主线程周期计时。
final class DispatchCountdownClock: CountdownClock {
    private var timer: Timer?

    func start(interval: TimeInterval, onTick: @escaping () -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            onTick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

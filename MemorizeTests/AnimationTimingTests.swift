import XCTest
@testable import Memorize

/// M7 动画参数单元测试：验证错峰发牌延迟、时长与得分反馈幅度的取值规则。
final class AnimationTimingTests: XCTestCase {

    func testDealDelayStartsAtZero() {
        XCTAssertEqual(AnimationTiming.dealDelay(forCardAt: 0), 0)
        XCTAssertEqual(AnimationTiming.dealDelay(forCardAt: -1), 0)
        XCTAssertEqual(AnimationTiming.dealDelay(forCardAt: -20), 0)
    }

    func testDealDelayAppliesLinearStagger() {
        let stagger = AnimationTiming.dealStagger

        XCTAssertEqual(AnimationTiming.dealDelay(forCardAt: 1), stagger, accuracy: 0.0001)
        XCTAssertEqual(AnimationTiming.dealDelay(forCardAt: 3), stagger * 3, accuracy: 0.0001)
        XCTAssertEqual(AnimationTiming.dealDelay(forCardAt: 5), stagger * 5, accuracy: 0.0001)
    }

    func testDealDelayCapsAtMaximum() {
        // 10 × 0.06 = 0.6，刚好触顶；更大的下标不再增长。
        XCTAssertEqual(AnimationTiming.dealDelay(forCardAt: 10), AnimationTiming.dealMaxStagger, accuracy: 0.0001)
        XCTAssertEqual(AnimationTiming.dealDelay(forCardAt: 16), AnimationTiming.dealMaxStagger, accuracy: 0.0001)
        XCTAssertEqual(AnimationTiming.dealDelay(forCardAt: 100), AnimationTiming.dealMaxStagger, accuracy: 0.0001)
    }

    func testDealDelayIsMonotonic() {
        var previous = AnimationTiming.dealDelay(forCardAt: 0)

        for index in 1...40 {
            let current = AnimationTiming.dealDelay(forCardAt: index)
            XCTAssertGreaterThanOrEqual(current, previous, "下标 \(index) 的延迟不应小于前一张")
            previous = current
        }
    }

    func testDealDelayNeverExceedsCap() {
        for index in 0...100 {
            XCTAssertLessThanOrEqual(
                AnimationTiming.dealDelay(forCardAt: index),
                AnimationTiming.dealMaxStagger
            )
        }
    }

    func testFlipDurationIsSmoothAndPositive() {
        XCTAssertGreaterThan(AnimationTiming.flipDuration, 0.2)
        XCTAssertLessThanOrEqual(AnimationTiming.flipDuration, 0.6)
        XCTAssertEqual(AnimationTiming.flipDuration, 0.45, accuracy: 0.0001)
    }

    func testDealDurationIsShorterThanFlipDuration() {
        // 发牌是“入场”动画，应比翻牌更快，避免开局等待过久。
        XCTAssertLessThan(AnimationTiming.dealDuration, AnimationTiming.flipDuration)
    }

    func testScoreDeltaReportsIncreaseDecreaseAndNoChange() {
        XCTAssertEqual(AnimationTiming.scoreDelta(from: 0, to: 2), 2)
        XCTAssertEqual(AnimationTiming.scoreDelta(from: 2, to: 4), 2)
        XCTAssertEqual(AnimationTiming.scoreDelta(from: 0, to: -1), -1)
        XCTAssertEqual(AnimationTiming.scoreDelta(from: 3, to: 3), 0)
    }

    func testScorePopScaleIsPerceptibleButNotExcessive() {
        XCTAssertGreaterThan(AnimationTiming.scorePopScale, 1.1)
        XCTAssertLessThanOrEqual(AnimationTiming.scorePopScale, 1.5)
        XCTAssertEqual(AnimationTiming.scorePopScale, 1.25, accuracy: 0.0001)
    }
}

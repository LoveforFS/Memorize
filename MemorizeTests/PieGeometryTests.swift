import XCTest
import SwiftUI
@testable import Memorize

/// M8 Pie 环形倒计时几何单元测试：进度换算、角度映射与环宽约束。
final class PieGeometryTests: XCTestCase {

    func testProgressIsZeroForNonPositiveTotal() {
        XCTAssertEqual(PieGeometry.progress(remaining: 30, total: 0), 0)
        XCTAssertEqual(PieGeometry.progress(remaining: 30, total: -10), 0)
    }

    func testProgressIsZeroWhenRemainingDepleted() {
        XCTAssertEqual(PieGeometry.progress(remaining: 0, total: 60), 0)
        XCTAssertEqual(PieGeometry.progress(remaining: -5, total: 60), 0)
    }

    func testProgressIsOneWhenRemainingAtOrAboveTotal() {
        XCTAssertEqual(PieGeometry.progress(remaining: 60, total: 60), 1)
        XCTAssertEqual(PieGeometry.progress(remaining: 90, total: 60), 1)
    }

    func testProgressUsesRatioInMiddle() {
        XCTAssertEqual(PieGeometry.progress(remaining: 30, total: 60), 0.5)
        XCTAssertEqual(PieGeometry.progress(remaining: 45, total: 60), 0.75)
        XCTAssertEqual(PieGeometry.progress(remaining: 12, total: 60), 0.2)
    }

    func testProgressNeverExceedsUnitRange() {
        for remaining in -20...80 {
            let progress = PieGeometry.progress(remaining: remaining, total: 60)
            XCTAssertGreaterThanOrEqual(progress, 0)
            XCTAssertLessThanOrEqual(progress, 1)
        }
    }

    func testEndAngleStartsAtMinusNinety() {
        XCTAssertEqual(PieGeometry.startAngle.degrees, -90, accuracy: 0.001)
        XCTAssertEqual(PieGeometry.endAngle(for: 0).degrees, -90, accuracy: 0.001)
    }

    func testEndAngleQuarterTurn() {
        XCTAssertEqual(PieGeometry.endAngle(for: 0.25).degrees, 0, accuracy: 0.001)
    }

    func testEndAngleFullTurn() {
        XCTAssertEqual(PieGeometry.endAngle(for: 0.5).degrees, 90, accuracy: 0.001)
        XCTAssertEqual(PieGeometry.endAngle(for: 1).degrees, 270, accuracy: 0.001)
    }

    func testEndAngleClampsInvalidProgress() {
        XCTAssertEqual(PieGeometry.endAngle(for: -0.5).degrees, -90, accuracy: 0.001)
        XCTAssertEqual(PieGeometry.endAngle(for: 1.5).degrees, 270, accuracy: 0.001)
    }

    func testRingWidthScalesAndClamps() {
        XCTAssertEqual(PieGeometry.ringWidth(for: 40), 4, accuracy: 0.001)
        XCTAssertEqual(PieGeometry.ringWidth(for: 200), 10, accuracy: 0.001)
        XCTAssertEqual(PieGeometry.ringWidth(for: 10), 3, accuracy: 0.001)
        XCTAssertEqual(PieGeometry.ringWidth(for: 0), 0)
        XCTAssertEqual(PieGeometry.ringWidth(for: -10), 0)
    }
}

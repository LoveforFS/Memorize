import XCTest
import SwiftUI
@testable import Memorize

/// M8 Cardify 几何布局单元测试：卡片形状、描边、内边距与阴影按尺寸缩放并受限。
final class CardifyStyleTests: XCTestCase {

    func testCornerRadiusScalesWithShortSide() {
        XCTAssertEqual(CardStyle.cornerRadius(for: CGSize(width: 100, height: 150)), 12, accuracy: 0.001)
        XCTAssertEqual(CardStyle.cornerRadius(for: CGSize(width: 150, height: 100)), 12, accuracy: 0.001)
        XCTAssertEqual(CardStyle.cornerRadius(for: CGSize(width: 80, height: 120)), 9.6, accuracy: 0.001)
    }

    func testCornerRadiusClampsSmallCards() {
        // 40 × 12% = 4.8，低于下限 6。
        XCTAssertEqual(CardStyle.cornerRadius(for: CGSize(width: 40, height: 60)), 6, accuracy: 0.001)
        XCTAssertEqual(CardStyle.cornerRadius(for: CGSize(width: 10, height: 15)), 6, accuracy: 0.001)
    }

    func testCornerRadiusClampsLargeCards() {
        // 300 × 12% = 36，超过上限 20。
        XCTAssertEqual(CardStyle.cornerRadius(for: CGSize(width: 300, height: 450)), 20, accuracy: 0.001)
        XCTAssertEqual(CardStyle.cornerRadius(for: CGSize(width: 600, height: 900)), 20, accuracy: 0.001)
    }

    func testCornerRadiusRequiresPositiveSize() {
        XCTAssertEqual(CardStyle.cornerRadius(for: .zero), 0)
        XCTAssertEqual(CardStyle.cornerRadius(for: CGSize(width: -40, height: 60)), 0)
        XCTAssertEqual(CardStyle.cornerRadius(for: CGSize(width: 40, height: 0)), 0)
    }

    func testBorderWidthScalesAndClamps() {
        XCTAssertEqual(CardStyle.borderWidth(for: CGSize(width: 100, height: 150)), 1, accuracy: 0.001)
        XCTAssertEqual(CardStyle.borderWidth(for: CGSize(width: 200, height: 300)), 2, accuracy: 0.001)
        XCTAssertEqual(CardStyle.borderWidth(for: CGSize(width: 300, height: 450)), 3, accuracy: 0.001)
        XCTAssertEqual(CardStyle.borderWidth(for: CGSize(width: 40, height: 60)), 1, accuracy: 0.001)
    }

    func testContentPaddingScalesAndClamps() {
        XCTAssertEqual(CardStyle.contentPadding(for: CGSize(width: 100, height: 150)), 8, accuracy: 0.001)
        XCTAssertEqual(CardStyle.contentPadding(for: CGSize(width: 40, height: 60)), 3.2, accuracy: 0.001)
        XCTAssertEqual(CardStyle.contentPadding(for: CGSize(width: 10, height: 15)), 2, accuracy: 0.001)
        XCTAssertEqual(CardStyle.contentPadding(for: CGSize(width: 300, height: 450)), 8, accuracy: 0.001)
    }

    func testShadowRadiusScalesAndClamps() {
        XCTAssertEqual(CardStyle.shadowRadius(for: CGSize(width: 100, height: 150)), 3, accuracy: 0.001)
        XCTAssertEqual(CardStyle.shadowRadius(for: CGSize(width: 300, height: 450)), 6, accuracy: 0.001)
        XCTAssertEqual(CardStyle.shadowRadius(for: CGSize(width: 10, height: 15)), 1, accuracy: 0.001)
    }

    func testAspectRatioIsTwoToThree() {
        XCTAssertEqual(CardStyle.aspectRatio, 2 / 3, accuracy: 0.0001)
        // `RoundedRectangle` 只公开 `cornerSize`，`cornerRadius` 会被 View 的同名修饰器遮蔽。
        XCTAssertEqual(CardStyle.shape(for: CGSize(width: 100, height: 150)).cornerSize.width, 12)
    }
}

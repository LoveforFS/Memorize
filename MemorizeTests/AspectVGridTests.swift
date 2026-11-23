import XCTest
import SwiftUI
@testable import Memorize

/// M6 自适应布局单元测试：验证 AspectVGrid 的尺寸算法在各类屏幕尺寸下都可完整容纳卡片。
final class AspectVGridTests: XCTestCase {

    // MARK: - 测试辅助

    private func itemWidth(
        count: Int,
        width: CGFloat,
        height: CGFloat,
        aspectRatio: CGFloat
    ) -> CGFloat {
        AspectVGrid<Card, EmptyView>.itemWidthThatFits(
            count: count,
            size: CGSize(width: width, height: height),
            aspectRatio: aspectRatio
        )
    }

    /// 按 adaptive 网格的真实列数规则推算行数，用于验证“不溢出”。
    private func rows(count: Int, itemWidth: CGFloat, availableWidth: CGFloat) -> Int {
        guard itemWidth > 0 else { return count }
        let columnCount = max(1, Int(availableWidth / itemWidth))
        return Int(ceil(Double(count) / Double(columnCount)))
    }

    // MARK: - 非法输入

    func testZeroItemCountReturnsZero() {
        XCTAssertEqual(itemWidth(count: 0, width: 390, height: 700, aspectRatio: 2 / 3), 0)
    }

    func testZeroOrNegativeSizeReturnsZero() {
        XCTAssertEqual(itemWidth(count: 8, width: 0, height: 700, aspectRatio: 2 / 3), 0)
        XCTAssertEqual(itemWidth(count: 8, width: 390, height: 0, aspectRatio: 2 / 3), 0)
        XCTAssertEqual(itemWidth(count: 8, width: -390, height: 700, aspectRatio: 2 / 3), 0)
    }

    func testNonPositiveAspectRatioReturnsZero() {
        XCTAssertEqual(itemWidth(count: 8, width: 390, height: 700, aspectRatio: 0), 0)
        XCTAssertEqual(itemWidth(count: 8, width: 390, height: 700, aspectRatio: -0.5), 0)
    }

    // MARK: - 典型屏幕尺寸

    /// 竖屏：8 张 2:3 卡片在 390×700 内应排 3 列，宽度 130。
    func testPortraitLayoutChoosesThreeColumns() {
        let width = itemWidth(count: 8, width: 390, height: 700, aspectRatio: 2 / 3)

        XCTAssertEqual(width, 130)
        XCTAssertEqual(rows(count: 8, itemWidth: width, availableWidth: 390), 3)
        // 3 行 × 195 = 585，不超过 700。
        XCTAssertLessThanOrEqual(CGFloat(3) * 195, 700)
    }

    /// 横屏：同样 8 张卡片在 700×390 内应切换到更多列，宽度更小但不为 0。
    func testLandscapeLayoutChoosesMoreColumns() {
        let width = itemWidth(count: 8, width: 700, height: 390, aspectRatio: 2 / 3)

        XCTAssertEqual(width, 116)
        XCTAssertEqual(rows(count: 8, itemWidth: width, availableWidth: 700), 2)
        XCTAssertLessThanOrEqual(CGFloat(2) * (116 / (2 / 3)), 390)
    }

    /// 小屏 + 多卡片：16 张卡片在 320×480 内仍然完整放下。
    func testSmallScreenWithManyCardsStillFits() {
        let width = itemWidth(count: 16, width: 320, height: 480, aspectRatio: 2 / 3)

        XCTAssertEqual(width, 80)
        XCTAssertEqual(rows(count: 16, itemWidth: width, availableWidth: 320), 4)
    }

    // MARK: - 通用性质

    /// 任意尺寸、任意卡片数量、任意宽高比下，卡片都不会溢出可用区域。
    func testLayoutNeverOverflowsAvailableSpace() {
        let sizes: [CGSize] = [
            CGSize(width: 320, height: 480),
            CGSize(width: 390, height: 700),
            CGSize(width: 430, height: 932),
            CGSize(width: 700, height: 390),
            CGSize(width: 932, height: 430),
            CGSize(width: 1024, height: 768)
        ]
        let ratios: [CGFloat] = [0.5, 2 / 3, 1, 1.5]

        for size in sizes {
            for ratio in ratios {
                for count in [2, 6, 8, 10, 12, 16, 20, 32] {
                    let width = itemWidth(
                        count: count,
                        width: size.width,
                        height: size.height,
                        aspectRatio: ratio
                    )

                    XCTAssertGreaterThan(width, 0, "count=\(count) size=\(size) ratio=\(ratio)")
                    XCTAssertLessThanOrEqual(width, size.width, "count=\(count) size=\(size) ratio=\(ratio)")

                    let rowCount = rows(count: count, itemWidth: width, availableWidth: size.width)
                    let usedHeight = CGFloat(rowCount) * (width / ratio)
                    XCTAssertLessThanOrEqual(
                        usedHeight,
                        size.height,
                        "count=\(count) size=\(size) ratio=\(ratio) 使用高度 \(usedHeight) 超出"
                    )
                }
            }
        }
    }

    /// 相同输入必须得到相同结果，保证旋转屏幕时不会出现尺寸抖动。
    func testLayoutIsDeterministicForSameInput() {
        let first = itemWidth(count: 8, width: 390, height: 700, aspectRatio: 2 / 3)
        let second = itemWidth(count: 8, width: 390, height: 700, aspectRatio: 2 / 3)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, 130)
    }

    /// 宽度取整到整数点，避免浮点误差造成像素级溢出。
    func testItemWidthIsRoundedDownToWholePoints() {
        // 391 / 3 ≈ 130.33，向下取整后应为 130。
        let width = itemWidth(count: 8, width: 391, height: 700, aspectRatio: 2 / 3)

        XCTAssertEqual(width, width.rounded(.down))
        XCTAssertEqual(width, 130)
    }
}

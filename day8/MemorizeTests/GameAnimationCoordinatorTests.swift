import XCTest
@testable import Memorize

/// M7 动画边界控制器单元测试：翻牌去重、得分合并与牌局版本号的语义。
final class GameAnimationCoordinatorTests: XCTestCase {

    func testInitialStateIsIdle() {
        let coordinator = GameAnimationCoordinator()

        XCTAssertEqual(coordinator.boardRevision, 0)
        XCTAssertEqual(coordinator.scoreRevision, 0)
        XCTAssertEqual(coordinator.activeFlipCount, 0)
    }

    func testFirstFlipIsAccepted() {
        let coordinator = GameAnimationCoordinator()
        let id = UUID()

        XCTAssertTrue(coordinator.beginFlip(for: id))
        XCTAssertEqual(coordinator.activeFlipCount, 1)
        XCTAssertTrue(coordinator.activeFlipCardIDs.contains(id))
    }

    func testDuplicateFlipWhileActiveIsRejected() {
        let coordinator = GameAnimationCoordinator()
        let id = UUID()

        XCTAssertTrue(coordinator.beginFlip(for: id))
        XCTAssertFalse(coordinator.beginFlip(for: id))
        XCTAssertEqual(coordinator.activeFlipCount, 1)
    }

    func testFlipCanRestartAfterEndFlip() {
        let coordinator = GameAnimationCoordinator()
        let id = UUID()

        XCTAssertTrue(coordinator.beginFlip(for: id))
        coordinator.endFlip(for: id)
        XCTAssertEqual(coordinator.activeFlipCount, 0)
        XCTAssertTrue(coordinator.beginFlip(for: id), "动画结束后同一卡片应可再次翻牌")
    }

    func testDistinctCardsCanFlipConcurrently() {
        let coordinator = GameAnimationCoordinator()
        let first = UUID()
        let second = UUID()

        XCTAssertTrue(coordinator.beginFlip(for: first))
        XCTAssertTrue(coordinator.beginFlip(for: second))
        XCTAssertEqual(coordinator.activeFlipCount, 2)
    }

    func testEndAllFlipsClearsActiveCards() {
        let coordinator = GameAnimationCoordinator()
        let first = UUID()
        let second = UUID()
        _ = coordinator.beginFlip(for: first)
        _ = coordinator.beginFlip(for: second)

        coordinator.endAllFlips()

        XCTAssertEqual(coordinator.activeFlipCount, 0)
        XCTAssertTrue(coordinator.activeFlipCardIDs.isEmpty)
    }

    func testScoreChangeIncrementsRevision() {
        let coordinator = GameAnimationCoordinator()

        XCTAssertEqual(coordinator.scoreDidChange(from: 0, to: 2), 1)
        XCTAssertEqual(coordinator.scoreRevision, 1)
        XCTAssertEqual(coordinator.scoreDidChange(from: 2, to: 4), 2)
        XCTAssertEqual(coordinator.scoreRevision, 2)
    }

    func testUnchangedScoreDoesNotAnimate() {
        let coordinator = GameAnimationCoordinator()

        XCTAssertNil(coordinator.scoreDidChange(from: 2, to: 2))
        XCTAssertNil(coordinator.scoreDidChange(from: 0, to: 0))
        XCTAssertEqual(coordinator.scoreRevision, 0)
    }

    func testRapidScoreChangesKeepMonotonicRevision() {
        let coordinator = GameAnimationCoordinator()
        var revisions: [Int] = []

        for _ in 0..<5 {
            if let revision = coordinator.scoreDidChange(from: 0, to: 2) {
                revisions.append(revision)
            }
        }

        XCTAssertEqual(revisions, [1, 2, 3, 4, 5], "连续得分只递增版本号，不重置")
    }

    func testNewBoardClearsFlipsAndIncrementsRevision() {
        let coordinator = GameAnimationCoordinator()
        let id = UUID()
        _ = coordinator.beginFlip(for: id)

        let revision = coordinator.beginNewBoard()

        XCTAssertEqual(revision, 1)
        XCTAssertEqual(coordinator.boardRevision, 1)
        XCTAssertEqual(coordinator.activeFlipCount, 0)
        XCTAssertEqual(coordinator.scoreRevision, 0, "新牌局不产生得分动画")

        XCTAssertEqual(coordinator.beginNewBoard(), 2, "每次重开都应得到新的牌局版本号")
    }
}

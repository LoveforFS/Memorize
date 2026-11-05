import XCTest

/// M7 动画 UI 自动化测试：验证快速操作、锁定期间点击与重开时的动画边界表现。
///
/// 启动参数 `-uitesting` 使用确定性牌局：2 对、不洗牌，卡片依次为 🐶、🐶、🐱、🐱。
final class AnimationFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func card(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "card-\(index)").firstMatch
    }

    private var scoreLabel: XCUIElement {
        app.staticTexts["scoreLabel"]
    }

    private var themeNameLabel: XCUIElement {
        app.staticTexts["themeNameLabel"]
    }

    private var hintLabel: XCUIElement {
        app.staticTexts["interactionHint"]
    }

    private func waitForLabel(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 3.0) {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "等待元素文案为「\(expected)」超时，当前为「\(element.label)」")
    }

    // MARK: - 快速操作

    func testRapidDoubleTapFlipsCardOnlyOnce() {
        let element = card(0)
        element.tap()
        element.tap()

        waitForLabel(element, "已翻开的卡片 🐶")
        waitForLabel(scoreLabel, "0")
        waitForLabel(hintLabel, "点击卡片翻开，找出全部对子")
    }

    func testRapidTapsDuringMismatchLockAreIgnored() {
        card(0).tap()
        card(2).tap()
        waitForLabel(hintLabel, "配对失败，卡片即将翻回…")

        card(3).tap()
        waitForLabel(card(3), "未翻开的卡片")
        waitForLabel(scoreLabel, "0")
    }

    // MARK: - 动画中途重开

    func testThemeSwitchDuringFlipResetsBoardAndAnimations() {
        card(0).tap()
        waitForLabel(card(0), "已翻开的卡片 🐶")

        app.buttons["theme-运动"].tap()

        waitForLabel(themeNameLabel, "主题：运动")
        waitForLabel(scoreLabel, "0")
        waitForLabel(card(0), "未翻开的卡片")
        XCTAssertTrue(card(0).exists, "切题后应重新播放发牌动画并重新出现卡片")
    }
}

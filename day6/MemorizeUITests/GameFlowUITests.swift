import XCTest

/// M4 UI 自动化测试：验证主界面元素、翻牌与错配延时、计分、主题切换与结算弹窗。
///
/// 启动参数 `-uitesting` 让 App 使用确定性牌局：2 对、不洗牌，
/// 四张卡片依次为 🐶、🐶、🐱、🐱，对应标识 card-0 ... card-3。
final class GameFlowUITests: XCTestCase {

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

    // MARK: - 测试辅助

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

    private func waitForLabel(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 2.0) {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "等待元素文案为「\(expected)」超时，当前为「\(element.label)」")
    }

    // MARK: - 主界面

    func testMainScreenShowsCoreElements() {
        XCTAssertTrue(app.staticTexts["Memorize"].waitForExistence(timeout: 3))

        waitForLabel(themeNameLabel, "主题：动物")
        waitForLabel(scoreLabel, "0")
        waitForLabel(hintLabel, "点击卡片翻开，找出全部对子")

        for theme in ["动物", "运动", "表情", "旗帜", "天气", "食物"] {
            XCTAssertTrue(app.buttons["theme-\(theme)"].exists, "缺少主题按钮：\(theme)")
        }

        for index in 0..<4 {
            XCTAssertTrue(card(index).waitForExistence(timeout: 2), "缺少卡片 card-\(index)")
        }
        waitForLabel(card(0), "未翻开的卡片")
    }

    // MARK: - 翻牌与错配

    func testMismatchLocksHintAndFlipsBackAfterDelay() {
        card(0).tap()
        waitForLabel(card(0), "已翻开的卡片 🐶")

        card(2).tap()
        waitForLabel(hintLabel, "配对失败，卡片即将翻回…")
        waitForLabel(scoreLabel, "0")

        // 锁定期间点击第三张卡片不应生效。
        card(3).tap()
        waitForLabel(card(3), "未翻开的卡片")

        // 0.8 秒后自动翻回并恢复默认提示。
        waitForLabel(hintLabel, "点击卡片翻开，找出全部对子", timeout: 3.0)
        waitForLabel(card(0), "未翻开的卡片")
        waitForLabel(card(2), "未翻开的卡片")
    }

    func testMatchingPairScoresTwo() {
        card(0).tap()
        card(1).tap()

        waitForLabel(scoreLabel, "2")
        waitForLabel(card(0), "已配对的卡片 🐶")
        waitForLabel(card(1), "已配对的卡片 🐶")
        waitForLabel(hintLabel, "点击卡片翻开，找出全部对子")
    }

    // MARK: - 主题切换

    func testThemeSwitchResetsScoreAndBoard() {
        card(0).tap()
        card(1).tap()
        waitForLabel(scoreLabel, "2")

        app.buttons["theme-运动"].tap()

        waitForLabel(themeNameLabel, "主题：运动")
        waitForLabel(scoreLabel, "0")
        waitForLabel(card(0), "未翻开的卡片")
        XCTAssertTrue(card(0).exists)
    }

    // MARK: - 结算与重开

    func testCompletionAlertAndRestart() {
        card(0).tap()
        card(1).tap()

        card(2).tap()
        card(3).tap()

        let alert = app.alerts["全部配对成功！"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "全部配对后未出现结算弹窗")
        XCTAssertTrue(alert.staticTexts["本局得分：4"].exists)

        alert.buttons["再来一局"].tap()

        waitForLabel(scoreLabel, "0")
        waitForLabel(card(0), "未翻开的卡片")
        waitForLabel(card(2), "未翻开的卡片")
    }
}

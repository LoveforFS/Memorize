import XCTest

/// 主页与暂停页 UI 自动化测试。
///
/// 启动参数 `-uitesting-home`：
/// - 从主页进入，设置存内存，牌局不洗牌（牌序固定为 🐶🐶🐱🐱…）；
/// - 错配翻回延时放宽到 2 秒，避免与 XCUITest 的查询耗时形成竞态。
final class HomeFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitesting-home"]
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

    private var pauseTitle: XCUIElement {
        app.staticTexts["pauseTitle"]
    }

    /// 紧密轮询等待文案，避免 XCTNSPredicateExpectation 约 1 秒的轮询间隔漏掉瞬态状态。
    private func waitForLabel(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 4.0) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.label == expected { return }
            usleep(20_000)
        } while Date() < deadline

        let current = element.exists ? element.label : "<元素不存在>"
        XCTFail("等待元素文案为「\(expected)」超时，当前为「\(current)」")
    }

    /// 等待元素的无障碍值变为期望值。
    private func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 3.0) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if (element.value as? String) == expected { return }
            usleep(20_000)
        } while Date() < deadline

        XCTFail("等待元素值为「\(expected)」超时，当前为「\(String(describing: element.value))」")
    }

    /// 等待元素消失。
    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3.0) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !element.exists { return }
            usleep(20_000)
        } while Date() < deadline

        XCTFail("元素「\(element.identifier)」在 \(timeout) 秒内仍未消失")
    }

    private func startGameFromHome() {
        let start = app.buttons["startGameButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "主页缺少开始游戏按钮")
        start.tap()
        XCTAssertTrue(card(0).waitForExistence(timeout: 5), "开始游戏后未出现牌面")
    }

    // MARK: - 主页

    func testHomeShowsEntriesAndGuidance() {
        XCTAssertTrue(app.staticTexts["homeTitle"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["startGameButton"].exists, "缺少开始游戏入口")
        XCTAssertTrue(app.buttons["settingsButton"].exists, "缺少设置入口")

        let continueButton = app.buttons["continueGameButton"]
        XCTAssertTrue(continueButton.exists, "缺少继续游戏入口")
        XCTAssertFalse(continueButton.isEnabled, "首次启动没有进行中的牌局，继续游戏应禁用")
        XCTAssertTrue(
            continueButton.label.contains("暂无进行中的牌局"),
            "继续游戏应说明当前没有可继续的牌局，实际为「\(continueButton.label)」"
        )

        for difficulty in ["easy", "normal", "hard"] {
            XCTAssertTrue(app.buttons["difficulty-\(difficulty)"].exists, "缺少难度选项 \(difficulty)")
        }

        XCTAssertTrue(app.staticTexts["howToPlayTitle"].exists, "缺少操作引导")
        XCTAssertEqual(app.staticTexts["bestScoreLabel"].label, "0")
    }

    func testSettingsSheetShowsDifficultyAndThemes() {
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5))
        app.buttons["settingsButton"].tap()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3), "未打开设置页")
        XCTAssertTrue(app.buttons["difficulty-hard"].exists)

        let sportTheme = app.buttons["settings-theme-运动"]
        XCTAssertTrue(sportTheme.exists, "设置页缺少主题选项")
        sportTheme.tap()
        waitForValue(sportTheme, "当前已选中")

        app.buttons["settingsDoneButton"].tap()
        XCTAssertTrue(app.staticTexts["homeTitle"].waitForExistence(timeout: 3))
    }

    // MARK: - 开始游戏与暂停

    func testStartGameThenPauseAndResume() {
        startGameFromHome()

        app.buttons["pauseButton"].tap()
        XCTAssertTrue(pauseTitle.waitForExistence(timeout: 3), "点击暂停后未出现暂停页面")
        XCTAssertEqual(app.staticTexts["pauseScoreLabel"].label, "0")
        XCTAssertEqual(app.staticTexts["pauseDifficultyLabel"].label, "普通")

        app.buttons["resumeButton"].tap()
        waitForDisappearance(pauseTitle)
        waitForLabel(app.staticTexts["interactionHint"], "点击卡片翻开，找出全部对子")
    }

    func testPauseRestartResetsBoardAndScore() {
        startGameFromHome()
        card(0).tap()
        card(1).tap()
        waitForLabel(scoreLabel, "2")

        app.buttons["pauseButton"].tap()
        XCTAssertTrue(pauseTitle.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["pauseScoreLabel"].label, "2")

        app.buttons["restartButton"].tap()

        waitForDisappearance(pauseTitle)
        waitForLabel(scoreLabel, "0")
        waitForLabel(card(0), "未翻开的卡片")
        waitForLabel(app.staticTexts["progressLabel"], "已配对 0/6")
    }

    func testPauseExitToHomeKeepsGameAvailableForContinue() {
        startGameFromHome()
        card(0).tap()
        waitForLabel(card(0), "已翻开的卡片 🐶")

        app.buttons["pauseButton"].tap()
        XCTAssertTrue(pauseTitle.waitForExistence(timeout: 3))
        app.buttons["backToHomeButton"].tap()

        XCTAssertTrue(app.staticTexts["homeTitle"].waitForExistence(timeout: 3), "未返回主菜单")

        let continueButton = app.buttons["continueGameButton"]
        XCTAssertTrue(continueButton.isEnabled, "返回主菜单后进行中的牌局应可继续")

        continueButton.tap()
        XCTAssertTrue(card(0).waitForExistence(timeout: 5))
        waitForLabel(card(0), "已翻开的卡片 🐶")
        waitForDisappearance(pauseTitle)
    }

    // MARK: - 难度

    func testEasyDifficultyStartsSmallerBoard() {
        let easy = app.buttons["difficulty-easy"]
        XCTAssertTrue(easy.waitForExistence(timeout: 5))
        easy.tap()

        XCTAssertEqual(app.staticTexts["bestScoreLabel"].label, "0")
        XCTAssertTrue(app.staticTexts["homeRuleSummary"].label.contains("8 张"))

        app.buttons["startGameButton"].tap()

        XCTAssertTrue(card(7).waitForExistence(timeout: 5), "简单难度应有 8 张牌")
        XCTAssertFalse(card(8).exists, "简单难度不应出现第 9 张牌")
        XCTAssertEqual(app.staticTexts["difficultyLabel"].label, "简单")
    }

    func testHardDifficultyStartsLargerBoard() {
        let hard = app.buttons["difficulty-hard"]
        XCTAssertTrue(hard.waitForExistence(timeout: 5))
        hard.tap()

        app.buttons["startGameButton"].tap()

        XCTAssertTrue(card(15).waitForExistence(timeout: 5), "困难难度应有 16 张牌")
        XCTAssertEqual(app.staticTexts["difficultyLabel"].label, "困难")
    }
}

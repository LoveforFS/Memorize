import Foundation
import SwiftUI

@main
struct MemorizeApp: App {
    /// UI 自动化启动参数：直接进入确定性牌局（2 对、不洗牌），
    /// 保证下标与内容固定，用于牌面交互与动画测试。
    private var isGameUITesting: Bool {
        CommandLine.arguments.contains("-uitesting")
    }

    /// UI 自动化启动参数：从主页开始，设置使用内存存储、牌局不洗牌，
    /// 用于验证主页 / 设置 / 暂停页的流程。
    private var isHomeUITesting: Bool {
        CommandLine.arguments.contains("-uitesting-home")
    }

    /// 错配后卡片保持正面的时长。
    ///
    /// UI 自动化下放宽到 2 秒：错配锁定提示只在这段时间内可见，
    /// 而 XCUITest 每次查询/点击无障碍树的耗时接近 0.8 秒，原来的时长会让
    /// 「锁定期间点击被忽略」这类断言变成竞态（时序不确定）。
    private let uiTestingMismatchFlipDelay: TimeInterval = 2.0

    var body: some Scene {
        WindowGroup {
            if isHomeUITesting {
                RootView(flow: makeHomeTestingFlow())
            } else if isGameUITesting {
                GameView(
                    viewModel: GameViewModel(
                        theme: Theme.builtIn[0],
                        numberOfPairs: 2,
                        shuffle: false,
                        mismatchFlipDelay: uiTestingMismatchFlipDelay
                    )
                )
            } else {
                RootView(flow: GameFlowViewModel(store: UserDefaultsGameSettingsStore()))
            }
        }
    }

    /// 主页 UI 测试使用的流程：设置存内存，牌序固定，翻回延时放宽。
    private func makeHomeTestingFlow() -> GameFlowViewModel {
        GameFlowViewModel(
            settings: GameSettings(difficulty: .normal, themeName: Theme.builtIn[0].name),
            store: InMemoryGameSettingsStore(),
            shuffleNewGames: false,
            mismatchFlipDelay: uiTestingMismatchFlipDelay
        )
    }
}

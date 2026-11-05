import Foundation
import SwiftUI

@main
struct MemorizeApp: App {
    /// UI 自动化测试启动参数：使用确定性牌局（2 对、不洗牌），保证下标与内容固定。
    private var isUITesting: Bool {
        CommandLine.arguments.contains("-uitesting")
    }

    var body: some Scene {
        WindowGroup {
            if isUITesting {
                GameView(
                    viewModel: GameViewModel(
                        theme: Theme.builtIn[0],
                        numberOfPairs: 2,
                        shuffle: false
                    )
                )
            } else {
                GameView()
            }
        }
    }
}

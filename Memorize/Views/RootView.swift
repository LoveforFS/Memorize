import SwiftUI

/// 根视图：主页与牌局之间的唯一切换点。
///
/// - 页面切换由 `GameFlowViewModel.phase` 驱动，视图不保留额外的导航布尔值；
/// - 牌局用 `sessionID` 作为 `.id`：开新局时重建整棵子树（发牌动画、弹窗状态复位），
///   「继续游戏」不改变 id，因此保留原来的牌面与界面状态；
/// - App 进入非活跃状态时自动暂停，防止倒计时在后台继续流失。
struct RootView: View {
    @StateObject private var flow: GameFlowViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(flow: GameFlowViewModel = GameFlowViewModel()) {
        _flow = StateObject(wrappedValue: flow)
    }

    var body: some View {
        ZStack {
            switch flow.phase {
            case .home:
                HomeView(flow: flow)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .playing:
                gameScreen
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(AnimationTiming.pageTransition, value: flow.phase)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            flow.pauseGame()
        }
    }

    @ViewBuilder
    private var gameScreen: some View {
        if let game = flow.game {
            GameView(
                viewModel: game,
                onExitToHome: { flow.returnToHome() },
                onGameFinished: { score in flow.handleGameFinished(score: score) }
            )
            .id(flow.sessionID)
        } else {
            // 理论上不可达：没有牌局时 phase 不会进入 playing。
            HomeView(flow: flow)
        }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}

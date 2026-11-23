import Foundation
import SwiftUI

/// 游戏主界面：标题与计分区、主题选择区、卡片区，以及暂停页面浮层。
///
/// M4 调整：
/// - 视图只负责渲染与事件绑定，计时与状态调度全部在 `GameViewModel`；
/// - 订阅 `cards`、`score` 的 @Published 变化自动刷新；
/// - 支持注入 ViewModel，便于 UI 自动化测试使用确定性牌局。
///
/// 页面化扩展：
/// - 左上角暂停按钮进入暂停页面，浮层覆盖牌面并显示当前进度；
/// - `onExitToHome` / `onGameFinished` 把「返回主菜单」和「结算」交给上层流程处理，
///   视图自身不关心主页是否存在，保持可独立预览与测试。
struct GameView: View {
    @StateObject private var viewModel: GameViewModel
    /// 返回主菜单（由根视图注入；独立使用时为空）。
    private let onExitToHome: (() -> Void)?
    /// 一局结束（通关或超时）时回调，用于记录最佳成绩。
    private let onGameFinished: ((Int) -> Void)?

    @State private var isResultAlertPresented = false
    /// 得分缩放倍数：加分/扣分时先放大，再回落到 1。
    @State private var scorePopScale: CGFloat = 1
    /// 得分变化量（+2 / -1）是否可见。
    @State private var isScoreDeltaVisible = false

    init(
        viewModel: GameViewModel = GameViewModel(),
        onExitToHome: (() -> Void)? = nil,
        onGameFinished: ((Int) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onExitToHome = onExitToHome
        self.onGameFinished = onGameFinished
    }

    var body: some View {
        ZStack {
            gameContent

            if viewModel.isPaused {
                PauseView(
                    difficulty: viewModel.difficulty,
                    score: viewModel.score,
                    matchedPairs: viewModel.matchedPairsCount,
                    totalPairs: viewModel.totalPairs,
                    remainingSeconds: viewModel.countdownRemaining,
                    onResume: { withAnimation(AnimationTiming.pause) { viewModel.resume() } },
                    onRestart: { withAnimation(AnimationTiming.pause) { viewModel.newGame() } },
                    onExitToHome: { onExitToHome?() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1)
            }
        }
        .animation(AnimationTiming.pause, value: viewModel.isPaused)
        .alert(resultAlertTitle, isPresented: $isResultAlertPresented) {
            Button("再来一局") {
                viewModel.newGame()
            }
            Button("返回主菜单") {
                onExitToHome?()
            }
        } message: {
            Text("本局得分：\(viewModel.score)")
        }
        .onChange(of: viewModel.isGameOver) { _, isGameOver in
            if isGameOver {
                isResultAlertPresented = true
                onGameFinished?(viewModel.score)
            }
        }
        .onChange(of: viewModel.didTimeOut) { _, didTimeOut in
            if didTimeOut {
                isResultAlertPresented = true
                onGameFinished?(viewModel.score)
            }
        }
        .onChange(of: viewModel.scoreRevision) { _, _ in
            playScoreFeedback()
        }
        .onAppear {
            viewModel.startCountdownIfNeeded()
        }
    }

    /// 牌面内容。暂停时整体禁用，防止浮层透传手势。
    private var gameContent: some View {
        VStack(spacing: 12) {
            header
            themeBar
            statusRow
            cardArea
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .disabled(viewModel.isPaused)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            pauseButton

            VStack(alignment: .leading, spacing: 2) {
                Text("Memorize")
                    .font(.largeTitle.bold())
                HStack(spacing: 6) {
                    Text("主题：\(viewModel.theme.name)")
                        .accessibilityIdentifier("themeNameLabel")
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(viewModel.difficulty.title)
                        .foregroundColor(viewModel.difficulty.tint)
                        .accessibilityIdentifier("difficultyLabel")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            }

            Spacer()

            countdownPie

            VStack(alignment: .trailing, spacing: 2) {
                Text("得分")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(viewModel.score)")
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundColor(viewModel.score < 0 ? .red : .primary)
                    .contentTransition(.numericText())
                    .scaleEffect(scorePopScale)
                    .animation(AnimationTiming.score, value: viewModel.scoreRevision)
                    // 标识必须加在 overlay 之前：加在 overlay 之后会连同「+2」一起
                    // 继承 "scoreLabel"，导致同名元素出现两个，查询时报
                    // "Multiple matching elements found"。
                    .accessibilityIdentifier("scoreLabel")
                    .overlay(alignment: .leading) {
                        if isScoreDeltaVisible && viewModel.scoreChangeDelta != 0 {
                            Text(scoreDeltaText)
                                .font(.caption.bold())
                                .monospacedDigit()
                                .foregroundColor(viewModel.scoreChangeDelta > 0 ? .green : .red)
                                .offset(x: -30, y: -12)
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityIdentifier("scoreDeltaLabel")
                        }
                    }
            }
        }
    }

    /// 暂停入口：牌局结束时禁用，避免弹出无意义的暂停页。
    private var pauseButton: some View {
        Button {
            withAnimation(AnimationTiming.pause) {
                viewModel.pause()
            }
        } label: {
            Image(systemName: "pause.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canPause)
        .opacity(viewModel.canPause ? 1 : 0.3)
        .accessibilityIdentifier("pauseButton")
        .accessibilityLabel(Text("暂停游戏"))
    }

    /// 环形倒计时：绑定 ViewModel 的剩余秒数与总秒数；点击切换暂停 / 继续。
    private var countdownPie: some View {
        Pie(
            remaining: viewModel.countdownRemaining,
            total: viewModel.countdownTotal,
            tint: viewModel.countdownRemaining <= 5 && viewModel.countdownTotal > 0 ? .red : .accentColor
        )
        .frame(width: 44, height: 44)
        .opacity(viewModel.countdownState == .idle ? 0.35 : 1)
        .contentShape(Circle())
        .onTapGesture {
            viewModel.toggleCountdown()
        }
        .accessibilityAction(named: "暂停或继续倒计时") {
            viewModel.toggleCountdown()
        }
    }

    /// 得分变化的文案，例如 +2、-1。
    private var scoreDeltaText: String {
        viewModel.scoreChangeDelta > 0
            ? "+\(viewModel.scoreChangeDelta)"
            : "\(viewModel.scoreChangeDelta)"
    }

    /// 结算弹窗标题：通关优先展示成功文案，其次展示超时文案。
    private var resultAlertTitle: String {
        viewModel.isGameOver ? "全部配对成功！" : "时间到！"
    }

    /// 得分反馈：数值跳动（contentTransition）+ 元素缩放 + 变化量浮现。
    private func playScoreFeedback() {
        guard viewModel.scoreChangeDelta != 0 else { return }

        scorePopScale = AnimationTiming.scorePopScale
        withAnimation(AnimationTiming.score) {
            scorePopScale = 1
        }

        withAnimation(AnimationTiming.scoreReset) {
            isScoreDeltaVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationTiming.scoreDeltaVisibleDuration) {
            withAnimation(AnimationTiming.scoreReset) {
                isScoreDeltaVisible = false
            }
        }
    }

    // MARK: - 主题选择

    private var themeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Theme.builtIn) { theme in
                    ThemeButton(
                        theme: theme,
                        isSelected: theme.id == viewModel.theme.id
                    ) {
                        viewModel.chooseTheme(theme)
                    }
                    .accessibilityIdentifier("theme-\(theme.name)")
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(viewModel.isInteractionLocked)
        .opacity(viewModel.isInteractionLocked ? 0.6 : 1.0)
    }

    // MARK: - 卡片区

    /// 提示行 + 配对进度，固定高度避免锁定前后布局跳动。
    private var statusRow: some View {
        HStack(spacing: 8) {
            Text(hintText)
                .font(.footnote)
                .foregroundColor(hintColor)
                .accessibilityIdentifier("interactionHint")

            Spacer()

            Text("已配对 \(viewModel.matchedPairsCount)/\(viewModel.totalPairs)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .accessibilityIdentifier("progressLabel")
        }
        .frame(height: 18)
    }

    private var hintText: String {
        if viewModel.isPaused {
            return "已暂停，继续后倒计时才会恢复"
        }
        if viewModel.countdownState == .finished {
            return "时间到，点击「再来一局」重新开始"
        }
        if viewModel.countdownState == .paused {
            return "倒计时已暂停，点击环形继续计时"
        }
        return viewModel.isInteractionLocked
            ? "配对失败，卡片即将翻回…"
            : "点击卡片翻开，找出全部对子"
    }

    private var hintColor: Color {
        if viewModel.isPaused {
            return .blue
        }
        if viewModel.countdownState == .finished {
            return .red
        }
        if viewModel.countdownState == .paused {
            return .blue
        }
        return viewModel.isInteractionLocked ? .orange : .secondary
    }

    /// M6：用 AspectVGrid 自适应排布；M7：外层包 DealtCardView 实现错峰发牌动画。
    /// 以 `boardRevision` 作为网格身份：重开或切题时整组重建，发牌动画重新播放。
    private var cardArea: some View {
        Group {
            if viewModel.cards.isEmpty {
                emptyState
            } else {
                AspectVGrid(items: viewModel.cards, aspectRatio: 2 / 3) { card in
                    let index = cardIndex(of: card)
                    DealtCardView(index: index) {
                        CardView(card: card)
                    }
                    .onTapGesture {
                        choose(card)
                    }
                    .accessibilityIdentifier("card-\(index)")
                    .accessibilityAction(named: "翻开") {
                        choose(card)
                    }
                }
                .id(viewModel.boardRevision)
                .padding(.bottom, 8)
            }
        }
    }

    /// 卡片在牌组中的稳定下标，供 UI 自动化测试定位使用。
    private func cardIndex(of card: Card) -> Int {
        viewModel.cards.firstIndex(where: { $0.id == card.id }) ?? 0
    }

    /// 翻牌统一入口：用 withAnimation 封装状态变更，并在动画时长后释放动画占用。
    private func choose(_ card: Card) {
        withAnimation(AnimationTiming.flip) {
            viewModel.choose(card)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + AnimationTiming.flipDuration) {
            viewModel.endFlip(for: card.id)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("当前牌组为空")
                .font(.headline)
            Text("请切换主题或重新开始")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// 发牌动画包装：卡片首次出现时按下标错峰淡入、放大并轻微上移。
///
/// 延迟由 `AnimationTiming.dealDelay(forCardAt:)` 统一计算，
/// 因此同一屏内的卡片形成从左到右、从上到下的序列发牌效果。
private struct DealtCardView<Content: View>: View {
    let index: Int
    let content: Content

    @State private var isDealt = false

    /// 显式提供接收视图构建器的初始化器：
    /// 结构体的隐式成员初始化器参数类型是具体的 `Content`，
    /// 无法接收尾随闭包，必须由 `@ViewBuilder` 把闭包转换成视图。
    init(index: Int, @ViewBuilder content: () -> Content) {
        self.index = index
        self.content = content()
    }

    var body: some View {
        content
            .opacity(isDealt ? 1 : 0)
            .scaleEffect(isDealt ? 1 : 0.6)
            .offset(y: isDealt ? 0 : -10)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .onAppear {
                guard !isDealt else { return }
                withAnimation(AnimationTiming.deal.delay(AnimationTiming.dealDelay(forCardAt: index))) {
                    isDealt = true
                }
            }
    }
}

struct GameView_Previews: PreviewProvider {
    static var previews: some View {
        GameView()
    }
}

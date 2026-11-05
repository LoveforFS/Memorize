import Foundation
import SwiftUI

/// 游戏主界面：标题与计分区、主题选择区、卡片区。
///
/// M4 调整：
/// - 视图只负责渲染与事件绑定，计时与状态调度全部在 `GameViewModel`；
/// - 订阅 `cards`、`score` 的 @Published 变化自动刷新；
/// - 支持注入 ViewModel，便于 UI 自动化测试使用确定性牌局。
struct GameView: View {
    @StateObject private var viewModel: GameViewModel
    @State private var isGameOverAlertPresented = false

    init(viewModel: GameViewModel = GameViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            themeBar
            interactionHint
            cardArea
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .alert("全部配对成功！", isPresented: $isGameOverAlertPresented) {
            Button("再来一局") {
                viewModel.newGame()
            }
        } message: {
            Text("本局得分：\(viewModel.score)")
        }
        .onChange(of: viewModel.isGameOver) { isGameOver in
            if isGameOver {
                isGameOverAlertPresented = true
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Memorize")
                    .font(.largeTitle.bold())
                Text("主题：\(viewModel.theme.name)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("themeNameLabel")
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("得分")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(viewModel.score)")
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundColor(viewModel.score < 0 ? .red : .primary)
                    .accessibilityIdentifier("scoreLabel")
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

    /// 固定高度的提示行，避免错配锁定前后布局跳动。
    private var interactionHint: some View {
        Text(viewModel.isInteractionLocked ? "配对失败，卡片即将翻回…" : "点击卡片翻开，找出全部对子")
            .font(.footnote)
            .foregroundColor(viewModel.isInteractionLocked ? .orange : .secondary)
            .frame(height: 18)
            .accessibilityIdentifier("interactionHint")
    }

    /// M6：改用 AspectVGrid，按剩余空间自动计算卡片尺寸，横竖屏都不溢出、不重叠。
    private var cardArea: some View {
        Group {
            if viewModel.cards.isEmpty {
                emptyState
            } else {
                AspectVGrid(items: viewModel.cards, aspectRatio: 2 / 3) { card in
                    CardView(card: card)
                        .onTapGesture {
                            viewModel.choose(card)
                        }
                        .accessibilityIdentifier("card-\(cardIndex(of: card))")
                        .accessibilityAction(named: "翻开") {
                            viewModel.choose(card)
                        }
                }
                .padding(.bottom, 8)
            }
        }
    }

    /// 卡片在牌组中的稳定下标，供 UI 自动化测试定位使用。
    private func cardIndex(of card: Card) -> Int {
        viewModel.cards.firstIndex(where: { $0.id == card.id }) ?? 0
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

struct GameView_Previews: PreviewProvider {
    static var previews: some View {
        GameView()
    }
}

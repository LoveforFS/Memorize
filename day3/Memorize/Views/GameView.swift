import Foundation
import SwiftUI

/// 游戏主界面：标题与计分区、主题选择区、卡片区。
///
/// M3 交互：
/// - 点击卡片翻牌，翻开第二张时判定配对；
/// - 错配后两张卡片保持正面 0.8 秒再翻回，期间锁定交互防止连点；
/// - 全部配对后弹出结算弹窗，可重新开始。
struct GameView: View {
    @StateObject private var viewModel = GameViewModel()
    @State private var isGameOverAlertPresented = false

    /// 错配后保持正面的时长（秒）。
    private let mismatchFlipDelay: Double = 0.8

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
    }

    private var cardArea: some View {
        ScrollView {
            if viewModel.cards.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 68, maximum: 104), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(viewModel.cards) { card in
                        CardView(card: card)
                            .onTapGesture {
                                handleTap(card)
                            }
                            .accessibilityAction(named: "翻开") {
                                handleTap(card)
                            }
                    }
                }
                .padding(.bottom, 8)
            }
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

    // MARK: - 交互

    private func handleTap(_ card: Card) {
        guard !viewModel.isInteractionLocked else { return }

        viewModel.choose(card)

        guard viewModel.hasPendingMismatch else { return }

        // 错配延时翻回：等待期间 viewModel 已锁定交互。
        let model = viewModel
        DispatchQueue.main.asyncAfter(deadline: .now() + mismatchFlipDelay) {
            model.completeMismatchFlipBack()
        }
    }
}

struct GameView_Previews: PreviewProvider {
    static var previews: some View {
        GameView()
    }
}

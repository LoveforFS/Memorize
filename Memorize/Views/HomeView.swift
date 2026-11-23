import SwiftUI

/// 游戏主页面：展示品牌信息、难度与最佳成绩，提供「开始游戏 / 继续游戏 / 设置」入口，
/// 并用一段「如何玩」说明当前难度下的规则。
///
/// 页面本身不持有牌局状态：所有入口都转交给 `GameFlowViewModel`，
/// 由它决定是新建牌局、恢复暂停的牌局，还是只切换页面。
struct HomeView: View {
    @ObservedObject var flow: GameFlowViewModel

    @State private var isSettingsPresented = false

    private var difficulty: Difficulty { flow.settings.difficulty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statsRow
                difficultySection
                actionSection
                guideSection
                Text("难度与主题可在设置中修改，将在下一局开始时生效。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(flow: flow)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Memorize")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("homeTitle")
                Text("记忆翻牌 · 在时间内找出全部对子")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(Color(uiColor: .secondarySystemBackground))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settingsButton")
            .accessibilityLabel(Text("设置"))
        }
    }

    // MARK: - 概览

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(
                title: "最佳成绩",
                value: "\(flow.selectedBestScore)",
                caption: difficulty.title,
                valueIdentifier: "bestScoreLabel"
            )
            statCard(
                title: "本局规模",
                value: "\(difficulty.cardCount) 张",
                caption: "\(difficulty.countdownDuration) 秒倒计时",
                valueIdentifier: "boardSizeLabel"
            )
        }
    }

    private func statCard(
        title: String,
        value: String,
        caption: String,
        valueIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .accessibilityIdentifier(valueIdentifier)
            Text(caption)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: - 难度

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("难度")
                    .font(.headline)
                Spacer()
                Text(difficulty.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("difficultySubtitle")
            }

            DifficultyPicker(selection: $flow.settings.difficulty)

            Text(difficulty.ruleSummary)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("homeRuleSummary")
        }
    }

    // MARK: - 入口

    private var actionSection: some View {
        VStack(spacing: 10) {
            Button(action: flow.startNewGame) {
                Text(flow.canContinue ? "开始新一局" : "开始游戏")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("startGameButton")
            .accessibilityHint(Text("按当前难度开始一局新游戏"))

            Button(action: flow.continueGame) {
                VStack(spacing: 2) {
                    Text("继续游戏")
                        .font(.headline)
                        // 用文字颜色表达禁用，而不是整体降透明度：
                        // 降透明度会让浅色模式下的说明文字低到几乎看不清。
                        .foregroundColor(flow.canContinue ? .primary : .secondary)
                    Text(flow.continueCaption)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("continueHint")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(!flow.canContinue)
            .accessibilityIdentifier("continueGameButton")
            .accessibilityHint(Text("回到上一次未完成的牌局"))
        }
    }

    // MARK: - 操作引导

    private var guideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("如何玩")
                .font(.headline)
                .accessibilityIdentifier("howToPlayTitle")

            guideRow(index: 1, text: "依次点击两张卡片，把它们翻开。")
            guideRow(index: 2, text: "图案相同即配对成功，每对得 \(difficulty.scoringRules.pointsPerMatch) 分。")
            guideRow(index: 3, text: penaltyText)
            guideRow(index: 4, text: "牌局中点左上角暂停按钮，可以暂停、重开或返回主菜单。")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var penaltyText: String {
        let penalty = difficulty.scoringRules.repeatMismatchPenalty
        if penalty == 0 {
            return "图案不同会自动翻回，本难度翻错不扣分。"
        }
        return "图案不同会自动翻回，重复翻错同一张卡扣 \(penalty) 分。"
    }

    private func guideRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.footnote)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(flow: GameFlowViewModel())
    }
}

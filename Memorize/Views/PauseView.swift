import SwiftUI

/// 暂停页面：半透明遮罩 + 居中面板，展示当前进度并提供「继续 / 重新开始 / 返回主菜单」。
///
/// 设计要点：
/// - 遮罩本身吞掉点击，避免手势穿透到下面的牌面；
/// - 面板只读取传入的快照数据，不持有牌局，动作全部通过闭包回传；
/// - 「继续」是唯一的主按钮，其余操作用次要样式，避免误触导致进度丢失。
struct PauseView: View {
    let difficulty: Difficulty
    let score: Int
    let matchedPairs: Int
    let totalPairs: Int
    let remainingSeconds: Int

    let onResume: () -> Void
    let onRestart: () -> Void
    let onExitToHome: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* 仅用于拦截穿透，点击遮罩不关闭暂停 */ }

            VStack(spacing: 18) {
                titleBlock
                statsGrid
                actions
            }
            .padding(22)
            .background(
                // 用材质而不是纯色：深色模式下纯 systemBackground 与遮罩后的牌面几乎同色，
                // 面板边界会消失；材质自带明暗层次，两种外观下都能看清面板轮廓。
                RoundedRectangle(cornerRadius: 24)
                    .fill(.regularMaterial)
                    .shadow(color: Color.black.opacity(0.28), radius: 28, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        // 注意：不要在这个容器上加 accessibilityIdentifier。
        // 容器标识会被下发给内部所有文本与按钮，导致 pauseTitle / resumeButton
        // 等子元素标识被覆盖，UI 测试只能按容器名查到重复元素。
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)

            Text("已暂停")
                .font(.title.bold())
                .accessibilityIdentifier("pauseTitle")

            Text("倒计时已停止，继续游戏后从剩余时间接着计时")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            stat(title: "得分", value: "\(score)", identifier: "pauseScoreLabel")
            stat(title: "已配对", value: "\(matchedPairs)/\(totalPairs)", identifier: "pausePairsLabel")
            stat(title: "剩余时间", value: "\(remainingSeconds) 秒", identifier: "pauseRemainingLabel")
            stat(title: "难度", value: difficulty.title, identifier: "pauseDifficultyLabel")
        }
    }

    private func stat(title: String, value: String, identifier: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: onResume) {
                Label("继续游戏", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("resumeButton")
            .accessibilityHint(Text("关闭暂停页面并恢复倒计时"))

            Button(action: onRestart) {
                Label("重新开始", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("restartButton")
            .accessibilityHint(Text("清空当前进度，用相同难度重开一局"))

            Button(action: onExitToHome) {
                Label("返回主菜单", systemImage: "house")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("backToHomeButton")
            .accessibilityHint(Text("保留当前进度并回到主页面"))
        }
    }
}

struct PauseView_Previews: PreviewProvider {
    static var previews: some View {
        PauseView(
            difficulty: .normal,
            score: 6,
            matchedPairs: 3,
            totalPairs: 6,
            remainingSeconds: 42,
            onResume: {},
            onRestart: {},
            onExitToHome: {}
        )
    }
}

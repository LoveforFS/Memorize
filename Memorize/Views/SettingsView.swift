import SwiftUI

/// 设置页：调整难度与主题、清除最佳成绩。
///
/// 设置项直接绑定 `GameFlowViewModel.settings`，改动会立即持久化；
/// 但只影响下一局——进行中的牌局由独立的 `GameViewModel` 持有自己的难度与牌组。
struct SettingsView: View {
    @ObservedObject var flow: GameFlowViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isResetAlertPresented = false

    private let themeColumns = [GridItem(.adaptive(minimum: 88), spacing: 8)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DifficultyPicker(selection: $flow.settings.difficulty)
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                } header: {
                    Text("难度")
                } footer: {
                    Text(flow.settings.difficulty.subtitle)
                }

                Section {
                    LazyVGrid(columns: themeColumns, alignment: .leading, spacing: 8) {
                        ForEach(Theme.builtIn) { theme in
                            ThemeButton(
                                theme: theme,
                                isSelected: theme.name == flow.settings.themeName
                            ) {
                                withAnimation(AnimationTiming.selection) {
                                    flow.settings.themeName = theme.name
                                }
                            }
                            .accessibilityIdentifier("settings-theme-\(theme.name)")
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                } header: {
                    Text("主题")
                } footer: {
                    Text("主题决定卡片上的图案集合，共 \(flow.settings.theme.emojis.count) 种图案可选。")
                }

                Section {
                    HStack {
                        Text("最佳成绩")
                        Spacer()
                        Text("\(flow.selectedBestScore)")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("settingsBestScoreRow")

                    Button("清除最佳成绩", role: .destructive) {
                        isResetAlertPresented = true
                    }
                    .accessibilityIdentifier("resetScoresButton")
                    .disabled(flow.bestScores.values.allSatisfy { $0 == 0 })
                } header: {
                    Text("成绩")
                } footer: {
                    Text("修改难度与主题会在下一局开始时生效，进行中的牌局不受影响。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("settingsDoneButton")
                }
            }
            .alert("清除最佳成绩？", isPresented: $isResetAlertPresented) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) { flow.resetBestScores() }
            } message: {
                Text("所有难度的历史最高分会归零，进行中的牌局不受影响。")
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(flow: GameFlowViewModel())
    }
}

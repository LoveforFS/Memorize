# 复核补丁说明（R-01：倒计时超时后无法重开）

## 问题

`GameView` 的结算弹窗只监听 `viewModel.isGameOver`，而超时状态 `didTimeOut`
没有被任何视图观察。倒计时归零后：

- `GameViewModel.finishCountdown()` 将 `isInteractionLocked` 置为 `true`；
- 卡片、主题栏、环形点击全部被锁定；
- 提示行显示“时间到，点击「再来一局」重新开始”，但界面上并不存在该按钮。

结果：超时后应用进入不可恢复状态，只能杀掉进程重进。该问题影响演示脚本步骤 7，
也与提示文案自相矛盾。

## 补丁内容

文件：`Test/fix/GameView.swift`（相对 `day8/Memorize/Views/GameView.swift` 的完整修订版）
差异：`Test/fix/GameView.diff`

1. 将 `isGameOverAlertPresented` 重命名为 `isResultAlertPresented`，表示“结算弹窗”；
2. 弹窗标题改为计算属性 `resultAlertTitle`：通关优先显示“全部配对成功！”，否则“时间到！”；
3. 新增 `onChange(of: viewModel.didTimeOut)`，超时同样弹出结算弹窗；
4. 弹窗按钮仍为“再来一局”→ `viewModel.newGame()`，重开后倒计时按原时长重启。

不改动 `GameViewModel`、模型与 132 条测试，`GameFlowUITests` 对
“全部配对成功！”与“再来一局”的断言保持不变。

## 应用方式（在 macOS 工程中）

```bash
cp Test/fix/GameView.swift day8/Memorize/Views/GameView.swift   # 或在 Xcode 中替换
# 然后执行全量测试
xcodebuild test -project Memorize.xcodeproj -scheme Memorize \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## 验收步骤

1. 132 条测试全部通过（尤其 `GameFlowUITests/testCompletionAlertAndRestart`）；
2. 手动将 `CountdownDefaults.duration` 临时改为 5 秒，等待归零：
   - 出现标题为“时间到！”的弹窗；
   - 点击“再来一局”后得分归零、卡片重新发牌、倒计时回到原时长；
   - 卡片与主题栏恢复可点击。
3. 正常通关路径仍显示“全部配对成功！”与“本局得分：N”。

## 状态

- 补丁已生成，**尚未合并回 day8**（按复核要求，修改只在 Test 目录进行）。
- 当前可在 Windows 完成的验证：静态检查（结构与状态引用）、132 条等价回归不受影响。
- 需要 macOS + Xcode 完成的验证：编译、XCUITest、超时弹窗实机确认。

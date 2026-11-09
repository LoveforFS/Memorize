# WorkBuddy 交接提示词

> 用途：把 Memorize 项目交给后续 AI / 开发者时的**可直接复制提示词**。
> 使用方式：整段复制“二、提示词正文”到 WorkBuddy，按其现有项目路径执行即可。
> 维护要求：任务状态变化时，只更新第二～五节，不要改动第六节的技术事实。

---

## 一、交接摘要

| 项目 | 内容 |
| --- | --- |
| 项目 | 综合应用开发项目实训 · SwiftUI 记忆配对游戏 Memorize |
| 仓库根目录 | `c:\Users\22320\Desktop\实训\综合应用开发项目实训` |
| 交付版本 | `day8/`（day1–day8 每日目录留存） |
| 当前状态 | D1–D8 代码、测试、文档、Xcode 工程全部完成；132 条等价测试通过 |
| 阻塞项 | 无 macOS / Xcode，无法执行 `xcodebuild test` 与录屏 |
| 后续目标 | 原生验证 132 条 → 录屏（含超时流程）→ 回填证据 |

---

## 二、提示词正文（复制以下全部内容）

```text
你是 Memorize 项目的后续开发与验收负责人。请先阅读项目根目录
`c:\Users\22320\Desktop\实训\综合应用开发项目实训\day8\README.md`、
`day8\项目核心文档.md`、`day8\演示脚本.md` 和 `day8\录屏拍摄清单.md`，
再按下面的约束继续工作。不要重复已经完成的 D1–D8 开发，不要重构现有架构。

【项目上下文】
1. 技术栈：Swift 5.9 工具链（工程语言模式 5.0）、SwiftUI、Combine、XCTest / XCUITest，
   iOS 16.0 部署目标；工程为 `day8/Memorize.xcodeproj`，objectVersion 56，
   共享 Scheme 名 `Memorize`，包含 Memorize、MemorizeTests、MemorizeUITests 三个 Target。
2. 三层架构：Models（Theme/Card/Game）→ ViewModels（GameViewModel、
   MismatchTimerScheduling、GameAnimationCoordinator、CountdownClock）→
   Views（GameView、CardView、Cardify、Pie、ThemeButton、AspectVGrid、AnimationTiming）。
   依赖只能自上而下：View 依赖 ViewModel，ViewModel 依赖 Model，禁止反向引用。
3. 已完成：6 套主题、翻牌配对、+2/-1 计分、0.8 秒错配翻回、60 秒环形倒计时
   （暂停/继续/超时）、通关与超时共用结算弹窗、“再来一局”、3D 翻牌、错峰发牌、
   得分动画、Cardify 统一外观、AspectVGrid 自适应布局。
4. 测试：132 条（MemorizeTests 124 + MemorizeUITests 8）。Windows 侧
   `python day8/WinTestHarness/run_tests.py` 最近一次为 132/132、失败 0、跳过 0。
   必须保留该基线与用例名称映射，任何改动后都要重新跑通。
5. 关键参数不可随意修改：错配 0.8s、翻牌 0.45s、发牌 0.06s（封顶 0.6s）、
   得分缩放 1.25、浮标 0.7s、倒计时 60s、tick 1s、最后 5s 转红。

【当前环境与限制】
- 当前机器为 Windows 11 + PowerShell 5.1，没有 Swift、Xcode、xcodebuild，
  不能真实编译 iOS 工程，也不能录屏。
- 不得伪造 xcodebuild 输出、不得把未执行的测试或录屏写成“已完成”。
- 若具备 macOS，请优先执行原生验证与录屏；若没有，只能做 Windows 等价验证、
  静态工程校验与文档准备，并明确标注未完成项。

【后续任务（按顺序）】
1. 原生验证：在 macOS 的 day8 目录执行
   `xcodebuild -list -project Memorize.xcodeproj` 确认三个 Target 与共享 Scheme；
   再执行
   `xcodebuild test -project Memorize.xcodeproj -scheme Memorize -destination 'platform=iOS Simulator,name=iPhone 15' -resultBundlePath ./TestResults.xcresult`，
   目标 `Executed 132 tests, with 0 failures`。若出现编译错误或失败，逐条定位修复后重跑，
   直到 132/132；修复不得降低断言强度或删除用例。
2. 录屏：按 `day8/录屏拍摄清单.md` 录制 8 个分镜，必须包含
   “超时触发 → 时间到弹窗（标题‘时间到！’、显示本局得分）→ 点击‘再来一局’
   → 得分归零、重新发牌、倒计时重启”完整片段；录屏文件建议命名
   `Memorize-演示-YYYYMMDD.mp4`，放在 `day8/` 下。
3. 证据回填：把原生测试结果（.xcresult 路径、终端摘要）与录屏文件路径补入
   `day8/README.md` §5.2、`day8/答辩PPT大纲.md` 与 `day8/苏信忠-实训日报-第八天.docx`
   的遗留项；同时更新 `Test/复核报告-第八天.md` 的 R-03、R-03a 状态。
4. 回归：任何 Swift 改动后执行
   `python day8/WinTestHarness/run_tests.py`，确认仍为 132/132；
   执行 `python Test/check_project.py`，目标 0 失败（允许既有 1 条日期警告）。
5. 如新增/删除 Swift 文件，执行 `python Test/gen_xcodeproj.py` 重建工程并确认自检通过。

【代码与文档规范】
- 中文注释、中文文档；命名遵循现有 Swift API Design Guidelines；
- 业务规则只写在 Model，UI 状态只由 ViewModel 发布，View 不写规则；
- 不引入第三方依赖；不新增全局单例；不把计时逻辑放回 View；
- 不使用强制解包（内置主题常量除外）；新增分支必须有边界处理与对应用例；
- 文档中的命令必须可在目标环境直接复制执行；路径使用相对 day8 的写法；
- 所有说明必须与代码一致，验证结论必须注明“原生 / 等价”。

【禁止事项】
- 禁止重写架构、批量重命名、无关格式化或“顺手优化”；
- 禁止删除、跳过、弱化任何测试用例来换取通过；
- 禁止在未运行的情况下声称 xcodebuild 通过或录屏完成；
- 禁止修改 day1–day7 的历史日报与代码，除非是明确的兼容性修复。

【交付标准】
1. 工程可在 macOS 上 `xcodebuild -list` 列出 3 个 Target，`xcodebuild test` 132/132；
2. 录屏完整、清晰、无遮挡，超时流程可辨认，文件名与存放路径符合约定；
3. README、答辩大纲、复核报告、日报中的状态与证据一致，无“待办已勾选但未执行”；
4. `WinTestHarness/test_results.json` 为 132/132，`check_project.py` 0 失败；
5. 最终用中文汇报：完成了什么、证据在哪、还剩什么、风险是什么。

【输出要求】
每次任务结束输出：
- 变更文件清单（绝对路径）；
- 实际执行的命令与关键输出（不得省略失败信息）；
- 未完成项与阻塞原因；
- 下一步建议（不超过 3 条）。
```

---

## 三、交接时必须一并移交的文件

| 文件 | 作用 |
| --- | --- |
| `day8/Memorize.xcodeproj/` | 可直接打开的工程与共享 Scheme |
| `day8/Memorize/` | 15 个业务源码文件 |
| `day8/MemorizeTests/`、`day8/MemorizeUITests/` | 132 条测试 |
| `day8/WinTestHarness/` | 等价执行器与结果 JSON |
| `day8/README.md` | 构建、测试、判定标准 |
| `day8/项目核心文档.md` | 模块、历史问题、边界与架构 |
| `day8/演示脚本.md` | 现场演示顺序 |
| `day8/答辩PPT大纲.md` | 答辩结构 |
| `day8/录屏拍摄清单.md` | 录屏分镜与验收点 |
| `Test/gen_xcodeproj.py` | 工程再生成脚本 |
| `Test/check_project.py` | 全项目一致性复核 |
| `Test/复核报告-第八天.md` | 问题与风险记录 |

---

## 四、交接验收清单

- [ ] 能打开 `day8/Memorize.xcodeproj`，看到 3 个 Target；
- [ ] `xcodebuild -list` 能列出 `Memorize` Scheme；
- [ ] `xcodebuild test` 结果为 132 条、0 失败、0 跳过；
- [ ] 录屏包含超时结算与“再来一局”完整链路；
- [ ] Windows 等价回归仍为 132/132；
- [ ] `check_project.py` 0 失败；
- [ ] 文档状态与实际证据一致，无虚假完成标记。

---

## 五、常见问题速查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `xcodebuild: error: Unable to find a scheme` | 未在 day8 目录执行或 Scheme 未共享 | `cd day8` 后重试；确认 `xcshareddata/xcschemes/Memorize.xcscheme` 存在 |
| `No such module 'XCTest'` | 测试 Target 类型或 SDK 不正确 | 确认 Target 为 unit-test / ui-testing，重新生成工程 |
| `@testable import Memorize` 失败 | 主目标模块名或 TEST_HOST 错误 | 确认 Product Module Name 为 `Memorize`、`ENABLE_TESTABILITY=YES`（Debug） |
| 模拟器名称不存在 | 本机未安装对应模拟器 | `xcrun simctl list devices available` 选择可用设备 |
| 测试卡在倒计时 | 用例注入了真实计时器 | 使用 `FakeCountdownClock`，不要真实等待 60 秒 |
| 超时后无法操作 | 预期行为 | 点击结算弹窗“再来一局”；不要移除超时锁 |
| 快照 / 动画不稳定 | UI 测试受动画时长影响 | 等待元素 `waitForExistence(timeout:)`，不要用固定 sleep |
| 工程文件被 Xcode 重写 | Xcode 保存时重排 | 属正常现象；UUID 与引用应保持不变，重新执行自检脚本核对 |

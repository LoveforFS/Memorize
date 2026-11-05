# Memorize 答辩 PPT 大纲

> 适用版本：day8（D8 整合交付）
> 建议页数：14–16 页，讲解时长 8–10 分钟
> 配套材料：`README.md`（架构与测试流程）、`演示脚本.md`（现场操作）、`WinTestHarness/test_results.json`（测试证据）

---

## 第 1 页　封面

- 标题：Memorize —— 基于 SwiftUI 的记忆配对游戏
- 副标题：《综合应用开发项目实训》结项答辩
- 信息：苏信忠 · 240200126 · 24软件2 · 指导教师：赵明 · 2026 年 11 月 8 日

**讲解要点**：一句话说明选题——用 SwiftUI 完整实现一款可玩、可测、可演示的记忆配对游戏。

---

## 第 2 页　项目概述与目标

- 产品形态：iOS 单页应用，点击卡片配对 emoji
- 核心能力：主题切换、计分、自适应布局、三类动画、统一卡片外观、环形倒计时
- 交付标准：模型 / 视图模型 / 视图三层分层；132 条用例 100% 通过
- 迭代节奏：D2 模型 → D3 交互 → D4 MVVM 与计分 → D5 布局 → D6 动画 → D7 装饰与倒计时 → D8 整合

**讲解要点**：强调“每日可运行、每日有测试、每日有交付”的迭代方式。

---

## 第 3 页　技术选型与总体架构

- 技术栈：Swift 5.9、SwiftUI、Combine（`@Published`）、XCTest / XCUITest
- 三层结构图：
  - Model（`Theme` / `Card` / `Game`）：规则与状态
  - ViewModel（`GameViewModel` + 3 个调度器）：唯一状态源
  - View（`GameView` / `CardView` / `Cardify` / `Pie` / `AspectVGrid`）：渲染与手势
- 依赖方向：View → ViewModel → Model，禁止反向依赖

**讲解要点**：指出视图不写规则、模型不碰 UI，便于测试与替换。

---

## 第 4 页　数据流与调用关系

- 主链路：点击卡片 → `GameView.choose` → `GameViewModel.choose` → `Game.choose` → `syncFromGame` → `@Published` → 视图刷新
- 调度链路：错配 → 锁定 → 0.8 秒定时器 → 翻回 → 解锁
- 动画链路：`GameAnimationCoordinator` 产出 `boardRevision` / `scoreRevision`，视图只订阅版本号
- 倒计时链路：`CountdownClock` 每秒 tick → `tickCountdown` → `Pie` 重绘

**讲解要点**：用一张时序图说明“状态变更先行、动画表现随后”。

---

## 第 5 页　核心交互流程（一）：翻牌与配对

- 操作步骤：点击第一张 → 翻开；点击第二张 → 比对内容
- 规则：内容相同 → 双方 `isMatched`、得分 +2；内容不同 → 登记错配、锁定交互、0.8 秒后翻回
- 防连点：同一张卡重复点击被忽略；锁定期间所有点击被忽略
- 对应代码：`Game.choose`、`GameViewModel.choose`、`MismatchTimerScheduling`

**讲解要点**：现场演示步骤 2，强调“真实翻面才登记动画”。

---

## 第 6 页　核心交互流程（二）：计分与主题切换

- 计分规则：配对 +2；涉及已见卡片的错配 -1；得分可为负并转红
- 版本号机制：得分真正变化才递增 `scoreRevision`，避免动画排队
- 主题切换：6 套内置主题，切换即重置牌局、得分、错配令牌与倒计时
- 通关：所有卡片配对完成 → 弹窗 → “再来一局”

**讲解要点**：现场演示步骤 3、5、6，说明规则全部在模型层。

---

## 第 7 页　关键动画效果的展示节点

| 动画 | 触发点 | 参数 | 展示节点 |
| --- | --- | --- | --- |
| 翻牌 | 卡片背面 → 正面 | 3D Y 轴旋转，0.45 秒，透视 0.55 | 演示步骤 2 |
| 发牌 | 新牌局首次出现 | 0.06 秒错峰、封顶 0.6 秒，缩放 0.6→1 + 淡入 | 演示步骤 1、5、6 |
| 得分 | 得分数值变化 | 数值滚动 + 1.25 倍缩放回弹 + ±变化量浮标 0.7 秒 | 演示步骤 2、3 |

**讲解要点**：
- 正反面分层互斥显示，背面反向旋转 180° 防止图标镜像；
- 动画参数集中在 `AnimationTiming`，改一处即可全局生效；
- 动画边界由 `GameAnimationCoordinator` 控制，快速操作不叠加、不冲突。

---

## 第 8 页　倒计时功能实现逻辑（一）：状态机

- 四种状态：`idle` → `running` ⇄ `paused` → `finished`
- 启动：`startCountdownIfNeeded()` 在视图 `onAppear` 幂等启动，默认 60 秒
- 推进：`tickCountdown()` 仅在 `running` 递减，归零进入 `finished`
- 暂停 / 恢复：暂停停止计时器并保留剩余；恢复从剩余继续
- 结束：停止计时器、剩余归零、`didTimeOut = true`、锁定交互

**讲解要点**：强调所有状态变更在 ViewModel，视图不持有计时逻辑。

---

## 第 9 页　倒计时功能实现逻辑（二）：Pie 与双向绑定

- 几何：`PieGeometry.progress = remaining / total`（0…1）；
  起始 -90°（12 点方向），结束角度 `-90° + 360° × progress`；环宽为直径 10%（3…10 pt）
- 渲染：灰色轨道圆 + `Circle().trim(from:0,to:progress)` 彩色圆弧 + 中心剩余秒数
- 绑定方向一（显示）：`@Published countdownRemaining / countdownTotal` → `Pie`
- 绑定方向二（回写）：点击环形 / 可访问性动作 → `toggleCountdown()`
- 视觉警示：剩余 ≤ 5 秒时环形与数字转红

**讲解要点**：现场演示步骤 4，指出点击环形即可暂停/继续。

---

## 第 10 页　倒计时与牌局的联动边界

- 重开一局：`newGame()` → 牌局重置 → 按原时长重启倒计时
- 切换主题：`chooseTheme()` → 同上
- 超时锁定：`completeMismatchFlipBack()` 仅在 `countdownState != .finished` 时解锁
- 未启动场景：纯模型测试中不会凭空启动计时，保证历史基线断言不变

**讲解要点**：说明“为什么超时后翻回任务不会把锁解除”。

---

## 第 11 页　卡片外观统一：Cardify

- 问题：早期卡片样式散落在多个视图，改一处漏一处
- 方案：`CardStyle`（纯函数几何）+ `Cardify`（ViewModifier）+ `View.cardify(...)`
- 规范：宽高比 2:3；圆角短边 12%（6…20）；描边 1%（1…3）；内边距 8%（2…8）；阴影 3%（1…6）
- 颜色：正面 `systemBackground`、背面 `accentColor`、配对描边绿色
- 收益：全部卡片唯一入口，尺寸自适应且可单元测试

**讲解要点**：打开 `Cardify.swift` 与 `CardView.swift` 对照展示替换前后差异。

---

## 第 12 页　测试体系与 132 条用例总览

| 套件 | 用例数 | 覆盖 |
| --- | --- | --- |
| GameModelTests | 28 | 主题校验、牌组、配对、计分、重开 |
| GameViewModelTests | 11 | 状态发布、锁定、解锁、切题 |
| MismatchTimerTests | 10 | 延时调度、令牌失效 |
| AspectVGridTests | 9 | 自适应列数与不溢出 |
| AnimationTimingTests | 9 | 错峰延迟、时长、得分幅度 |
| GameAnimationCoordinatorTests | 10 | 翻牌去重、得分合并、牌局版本 |
| AnimationIntegrationTests | 13 | 动画与 VM 协同、快速操作 |
| CardifyStyleTests | 8 | 圆角/描边/内边距/阴影/宽高比 |
| PieGeometryTests | 10 | 进度、角度、环宽、边界 |
| CountdownIntegrationTests | 16 | 倒计时状态机与牌局联动 |
| GameFlowUITests | 5 | 主流程 UI 自动化 |
| AnimationFlowUITests | 3 | 快速点击与切图重置 |
| **合计** | **132** | 历史基线 98 + D7 新增 34 |

**讲解要点**：说明用例按“模型 → 视图模型 → 视图 / UI”逐层覆盖。

---

## 第 13 页　测试执行与验证证据

- macOS 原生：`⌘U` 或 `xcodebuild test -scheme Memorize -destination 'platform=iOS Simulator,name=iPhone 15'`
- Windows 等价：`D:\miniconda3\python.exe day8/WinTestHarness/run_tests.py`
- 结果证据（截图位 / 结果说明）：
  - 控制台：`总计 132 条 | 通过 132 | 失败 0 | 跳过 0 | 通过率 100.00%`
  - 映射校验：`Swift 132 条，Python 132 条，一致`；12 个套件缺失 0、多余 0
  - 结果文件：`WinTestHarness/test_results.json`（逐条状态、耗时、套件统计）
- 通过判定五项：退出码 0、failed 0、skipped 0、total 132、coverage.ok 为 true

**讲解要点**：明确等效级别——逻辑与状态机等价，UI 为状态投影级等价；真实像素级渲染需在模拟器录屏。

---

## 第 14 页　边界、异常与质量保障

- 边界用例：非法主题（空名 / 空 emoji / 非法对数）、非法卡片点击、非法布局尺寸、非法环形进度、非法倒计时时长
- 并发与快速操作：连点、锁定期点击、动画中途切题、连续得分
- 质量措施：版本号合并、令牌失效、状态判定前置、纯函数几何、依赖注入
- 代码规范：分层依赖单向、命名统一、参数集中、无重复样式逻辑

**讲解要点**：挑 2–3 个真实踩坑（穿模、内边距溢出、超时锁被误解锁）说明修复思路。

---

## 第 15 页　交付物与目录说明

- 源码：`Memorize/`（Models / ViewModels / Views）
- 测试：`MemorizeTests/`（124 条）、`MemorizeUITests/`（8 条）
- 执行器：`WinTestHarness/run_tests.py` + `test_results.json`
- 文档：`README.md`、`演示脚本.md`、`答辩PPT大纲.md`、第八天日报 docx
- 版本管理：Git 按日提交，每日一个可运行里程碑

**讲解要点**：说明“代码、测试、文档、证据”四件套齐全。

---

## 第 16 页　总结与展望

- 已完成：三层架构、完整交互、计分、自适应布局、三类动画、统一外观、环形倒计时、132 条用例
- 收获：状态单一来源、动画边界控制、可注入计时器、纯函数几何便于测试
- 待改进：
  1. Reduce Motion（减弱动态效果）适配；
  2. 倒计时时长可配置、成绩持久化；
  3. 在 macOS + Xcode 上完成原生 132 条执行与真机录屏。
- 结束页：致谢 + Q&A

---

## 附：演示与答辩时间分配建议

| 环节 | 时长 |
| --- | --- |
| 开场与项目概述 | 1 分钟 |
| 架构与数据流 | 1.5 分钟 |
| 现场操作演示（步骤 1–6） | 3 分钟 |
| 倒计时与 Cardify 实现 | 1.5 分钟 |
| 测试证据与质量保障 | 1.5 分钟 |
| 总结与 Q&A | 1 分钟 |

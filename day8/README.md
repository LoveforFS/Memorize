# Memorize · SwiftUI 记忆配对游戏

> 《综合应用开发项目实训》（实训单一 · Stanford CS193p 2023）
> 作者：苏信忠（240200126，24软件2）　指导教师：赵明
> 交付版本：D8 整合交付（含 M2–M8 全部模块与 132 条测试用例）

Memorize 是一款基于 SwiftUI 的记忆配对游戏：点击卡片翻开 emoji，找出全部对子。
项目按每日迭代推进，最终整合为模型、视图模型、视图三层结构，覆盖交互、计分、自适应布局、
翻牌 / 发牌 / 得分动画、统一卡片外观与环形倒计时。

---

## 一、目录结构

```
day8/
├── Memorize/                     # 应用主目标（iOS App）
│   ├── MemorizeApp.swift         # @main 入口
│   ├── Models/                   # 领域模型层
│   │   ├── Theme.swift
│   │   ├── Card.swift
│   │   └── Game.swift
│   ├── ViewModels/               # 视图模型与调度层
│   │   ├── GameViewModel.swift
│   │   ├── MismatchTimerScheduling.swift
│   │   ├── GameAnimationCoordinator.swift
│   │   └── CountdownClock.swift
│   └── Views/                    # 视图与表现层
│       ├── GameView.swift
│       ├── CardView.swift
│       ├── Cardify.swift
│       ├── Pie.swift
│       ├── ThemeButton.swift
│       ├── AspectVGrid.swift
│       └── AnimationTiming.swift
├── MemorizeTests/                # 单元 / 集成测试（124 条）
├── MemorizeUITests/              # UI 自动化测试（8 条）
├── WinTestHarness/               # Windows 行为等价执行器
│   ├── run_tests.py
│   └── test_results.json         # 最近一次执行结果
└── README.md
```

---

## 二、架构分层说明

### 2.1 分层与职责边界

| 层级 | 目录 | 职责 | 允许依赖 | 禁止事项 |
| --- | --- | --- | --- | --- |
| 模型层 Model | `Memorize/Models` | 定义主题、卡片、牌局规则与计分；维护牌组、翻面、配对、错配状态 | 仅 Foundation / Swift 标准库 | 不引用 SwiftUI 视图、不持有计时器、不发布 UI 状态 |
| 视图模型层 ViewModel | `Memorize/ViewModels` | 唯一状态源：把模型状态转为 `@Published`；调度错配翻回与倒计时；动画边界判定 | 模型层、Foundation、Combine | 不直接绘制界面、不依赖具体视图类型 |
| 视图层 View | `Memorize/Views` | 渲染卡片 / 主题 / 得分 / 倒计时；把用户手势转成 ViewModel 调用；只订阅发布属性 | 视图模型层、SwiftUI | 不写业务规则、不直接修改模型 |
| 测试层 Test | `MemorizeTests`、`MemorizeUITests` | 单元、集成、UI 自动化验证；可注入假计时器构造确定性场景 | 全部业务层 + XCTest | 不复制业务实现、不依赖真实等待 |
| 等价执行层 Harness | `WinTestHarness` | Windows 下以 Python 镜像执行业务等价断言并校验用例映射 | Python 3 标准库 | 不替代 macOS 原生 XCTest 结论 |

### 2.2 数据流向

```
用户点击卡片
   │
   ▼
GameView.choose(_:) ── withAnimation(AnimationTiming.flip) ──▶ GameViewModel.choose(_:)
                                                                     │
                                                                     ▼
                                                              Game.choose(card)
                                                         （翻面 / 配对 / 计分 / 错配登记）
                                                                     │
                                                                     ▼
                                                     syncFromGame() 写入 @Published
                                                     cards / score / scoreRevision
                                                     / boardRevision / scoreChangeDelta
                                                                     │
                        ┌────────────────────────────┬───────────────┴──────────────┐
                        ▼                            ▼                              ▼
                 CardView + Cardify            GameView 得分区                DealtCardView 发牌
                 （外观 / 3D 翻牌）            （数值跳动 / 缩放）           （错峰入场）
```

倒计时链路（M8）：

```
GameView.onAppear ──▶ startCountdownIfNeeded() ──▶ CountdownClock.start(1s)
                                                          │ 每秒回调
                                                          ▼
                                                   tickCountdown()
                                                          │ 递减 @Published
                                                          ▼
                       Pie(remaining:total:) 渲染 ◀── countdownRemaining / countdownTotal
                                                          ▲
                       Pie 点击 / 可访问性动作 ──▶ toggleCountdown()（运行 ⇄ 暂停）
```

### 2.3 关键调用关系

- **状态单一来源**：`Game` 持有牌组与得分，`GameViewModel` 只做同步与调度，视图不保存牌局副本。
- **错配时序**：`GameViewModel.choose` 检测到 `hasPendingMismatch` → 锁定交互 → `MismatchTimerScheduling.schedule(after: 0.8)` → `completeMismatchFlipBack()` 翻回并解锁。
- **动画边界**：`GameAnimationCoordinator` 负责翻牌去重（`beginFlip` / `endFlip`）、得分版本合并（`scoreDidChange`）、牌局重置（`beginNewBoard`）；视图只响应版本号。
- **倒计时边界**：`CountdownClock` 协议可注入，测试使用假计时器手动推进；超时后 `isInteractionLocked` 保持，`completeMismatchFlipBack` 按 `countdownState == .finished` 判定是否解锁。
- **外观统一**：`CardStyle`（纯函数几何）→ `Cardify`（ViewModifier）→ `View.cardify(isFaceUp:isMatched:)`，所有卡片唯一入口。
- **环形几何**：`PieGeometry`（纯函数进度 / 角度 / 环宽）→ `Pie` 轨道与进度圆弧 → `GameView.countdownPie` 绑定。

---

## 三、模块与功能点对照映射表

| 代码模块路径 | 所属层 | 业务功能点 | 关键公开接口 |
| --- | --- | --- | --- |
| `Memorize/MemorizeApp.swift` | 入口 | 应用启动，装载游戏主界面 | `@main`、`WindowGroup` |
| `Memorize/Models/Theme.swift` | 模型 | 主题定义与校验；6 套内置主题 | `Theme`、`Theme.ValidationError`、`Theme.builtIn` |
| `Memorize/Models/Card.swift` | 模型 | 单张卡片：内容、翻面、配对状态，按 id 判等 | `Card.content/isFaceUp/isMatched` |
| `Memorize/Models/Game.swift` | 模型 | 牌组生成、翻牌规则、配对 +2 / 重复错配 -1、错配回翻、重开与切题 | `Game.choose`、`flipBackMismatch`、`newGame`、`startNewGame` |
| `Memorize/ViewModels/GameViewModel.swift` | 视图模型 | 对外状态发布、交互锁定、发牌 / 得分版本号、倒计时状态机与牌局联动 | `@Published cards/score/...`、`choose`、`chooseTheme`、`newGame`、`endFlip`、`startCountdown` 等 |
| `Memorize/ViewModels/MismatchTimerScheduling.swift` | 视图模型 | 错配翻回的延时调度抽象与生产实现 | `MismatchTimerScheduling`、`DispatchMismatchTimer` |
| `Memorize/ViewModels/GameAnimationCoordinator.swift` | 视图模型 | 动画边界：翻牌去重、得分合并、牌局版本号 | `beginNewBoard`、`beginFlip`、`endFlip`、`scoreDidChange` |
| `Memorize/ViewModels/CountdownClock.swift` | 视图模型 | 倒计时状态枚举、默认参数、周期计时器协议与实现 | `CountdownState`、`CountdownDefaults`、`CountdownClock`、`DispatchCountdownClock` |
| `Memorize/Views/GameView.swift` | 视图 | 主界面：头部（标题 / 环形倒计时 / 得分）、主题栏、提示行、卡片区、通关弹窗 | `GameView(viewModel:)` |
| `Memorize/Views/CardView.swift` | 视图 | 卡片正反面渲染、Y 轴 3D 翻牌、可访问性标签 | `CardView(card:)` |
| `Memorize/Views/Cardify.swift` | 视图 | 统一卡片外观规范与修饰器（圆角 / 描边 / 内边距 / 阴影 / 宽高比） | `CardStyle`、`Cardify`、`View.cardify` |
| `Memorize/Views/Pie.swift` | 视图 | 环形倒计时：进度几何、轨道与圆弧、中心秒数、最后 5 秒警示 | `PieGeometry`、`Pie(remaining:total:tint:)` |
| `Memorize/Views/ThemeButton.swift` | 视图 | 主题选择按钮与选中态样式 | `ThemeButton(theme:isSelected:action:)` |
| `Memorize/Views/AspectVGrid.swift` | 视图 | 按可用宽高自动选择列数的自适应网格 | `AspectVGrid.itemWidthThatFits` |
| `Memorize/Views/AnimationTiming.swift` | 视图 | 动画时长、错峰延迟、得分缩放与曲线集中定义 | `AnimationTiming` |
| `MemorizeTests/*.swift` | 测试 | 124 条单元 / 集成用例（模型 28、VM 11、计时 10、布局 9、动画 9+10+13、卡片 8、环形 10、倒计时 16） | `XCTestCase` 子类 |
| `MemorizeUITests/*.swift` | 测试 | 8 条 UI 自动化用例（主流程 5、动画快速操作 3） | `XCUITestCase` 子类 |
| `WinTestHarness/run_tests.py` | 验证 | Windows 行为等价执行、逐条结果与映射校验 | `main()` |

---

## 四、Step-by-step 项目构建

### 4.1 环境依赖

| 项目 | 要求 | 说明 |
| --- | --- | --- |
| 操作系统（主构建） | macOS 13 Ventura 及以上 | Xcode 仅支持 macOS |
| Xcode | 15.0 及以上 | 提供 Swift 5.9+ 与 iOS 17 SDK |
| 部署目标 | iOS 16.0 及以上 | 使用 `contentTransition(.numericText())` 等 iOS 16 起可用的 SwiftUI API |
| 模拟器 / 真机 | iPhone 15 模拟器或 iOS 16+ 设备 | 演示建议 iPhone 15 |
| Windows 验证环境 | Python 3.10+（本机实测 3.12.9） | 仅标准库，无第三方依赖 |
| Git | 任意近版本 | 版本管理与提交 |

> 仓库不包含 `.xcodeproj`（避免机器相关的工程文件冲突），首次构建需按下述步骤创建工程并挂载源码。

### 4.2 构建步骤（按顺序执行）

1. **克隆 / 获取代码**
   ```bash
   git clone <仓库地址>
   cd 综合应用开发项目实训/day8
   ```
2. **创建 Xcode 工程**
   - Xcode → File → New → Project → iOS → App；
   - Product Name：`Memorize`；Interface：SwiftUI；Language：Swift；Testing System：None（测试目标后续单独添加）；
   - Bundle Identifier 建议 `com.suxinzhong.memorize`；Minimum Deployment：iOS 16.0。
3. **挂载业务源码**
   - 删除模板生成的 `MemorizeApp.swift` 与 `ContentView.swift`；
   - 将本仓库 `day8/Memorize/` 下的 `MemorizeApp.swift`、`Models/`、`ViewModels/`、`Views/` 拖入工程；
   - 勾选 Copy items if needed，Target Membership 仅勾选 `Memorize`。
4. **添加测试目标**
   - File → New → Target → Unit Testing，命名 `MemorizeTests`，Host Application 选择 `Memorize`；
   - File → New → Target → UI Testing，命名 `MemorizeUITests`，Target Application 选择 `Memorize`；
   - 分别把 `day8/MemorizeTests/`、`day8/MemorizeUITests/` 下的 Swift 文件加入对应目标（不要加入主目标）。
5. **确认模块名**
   - 测试文件使用 `@testable import Memorize`，因此主目标 Product Module Name 必须为 `Memorize`（默认与 Product Name 一致）。
6. **编译**
   - 选择 `Memorize` scheme 与 iPhone 15 模拟器；
   - `⌘B` 编译，`⌘R` 运行；首次运行需在模拟器中允许无签名调试。
7. **打包（可选，用于交付演示）**
   - Product → Archive → Distribute App；
   - 选择 Development / Ad Hoc 导出，需要有效的开发者 Team 与签名证书；无签名时仅能在模拟器运行。
8. **Windows 侧可用性验证（等价执行）**
   ```powershell
   D:\miniconda3\python.exe "c:\Users\22320\Desktop\实训\综合应用开发项目实训\day8\WinTestHarness\run_tests.py"
   ```
   退出码 0 且输出 `总计 132 条 | 通过 132 | 失败 0` 即视为通过。

---

## 五、测试执行流程

### 5.1 用例规模

| 套件 | 来源 | 用例数 |
| --- | --- | --- |
| `GameModelTests` | D2 基线 | 28 |
| `GameViewModelTests` | D3 基线 | 11 |
| `MismatchTimerTests` | D4 基线 | 10 |
| `AspectVGridTests` | D5 基线 | 9 |
| `AnimationTimingTests` | D6 基线 | 9 |
| `GameAnimationCoordinatorTests` | D6 基线 | 10 |
| `AnimationIntegrationTests` | D6 基线 | 13 |
| `CardifyStyleTests` | D7 新增 | 8 |
| `PieGeometryTests` | D7 新增 | 10 |
| `CountdownIntegrationTests` | D7 新增 | 16 |
| `GameFlowUITests` | D3 基线 | 5 |
| `AnimationFlowUITests` | D6 基线 | 3 |
| **合计** | — | **132** |

### 5.2 macOS 原生执行方式

- **全量执行**：Xcode 中 `⌘U`，或命令行：
  ```bash
  xcodebuild test \
    -project Memorize.xcodeproj \
    -scheme Memorize \
    -destination 'platform=iOS Simulator,name=iPhone 15'
  ```
- **单套件执行**：
  ```bash
  xcodebuild test -project Memorize.xcodeproj -scheme Memorize \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:MemorizeTests/CountdownIntegrationTests
  ```
- **单条用例执行**：
  ```bash
  xcodebuild test -project Memorize.xcodeproj -scheme Memorize \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -only-testing:MemorizeTests/CountdownIntegrationTests/testCountdownFinishesAtZeroAndLocksInteraction
  ```
- **输出**：Xcode Test Navigator 显示逐条状态；命令行输出 `Test Suite ... passed` 与 `Executed 132 tests, with 0 failures`。
- **通过判定**：132 条全部 `passed`，失败数 0、跳过数 0。

### 5.3 Windows 行为等价执行方式

```powershell
D:\miniconda3\python.exe "c:\Users\22320\Desktop\实训\综合应用开发项目实训\day8\WinTestHarness\run_tests.py"
```

- **执行方式**：Python `unittest` 逐条运行，每条用例打印 `[PASS]` / `[FAIL]`；
- **输出产物**：控制台汇总 + `WinTestHarness/test_results.json`（含逐条状态、耗时、失败堆栈、套件统计与映射校验）；
- **通过判定（全部满足才算通过）**：
  1. 进程退出码为 `0`；
  2. `summary.failed == 0` 且 `summary.skipped == 0`；
  3. `summary.total == 132`、`summary.passRate == 100.0`；
  4. `coverage.ok == true`，且每个套件的 `missingInPython` 与 `extraInPython` 均为空（Swift 与 Python 用例名一一对应）；
  5. 映射总数 `expectedTotal == 132`。
- **等效级别说明**：模型、布局、动画边界、卡片几何、环形几何与倒计时状态机为**逻辑等价**；UI 用例为**状态投影级等价**（校验与 Swift 版相同的可见结论），不等同于 XCUITest 在模拟器上的像素级渲染验证。

### 5.4 回归基线口径

- 历史基线 **98 条**（D2–D6）必须保持全部通过；
- D7 新增 **34 条** 必须全部通过；
- 任何新增或修改代码提交前，均需在 `day8/WinTestHarness` 下重新执行全量 132 条并确认五项判定全部满足，再生成当日日报并提交 Git。

---

## 六、交付物清单

| 产物 | 路径 | 说明 |
| --- | --- | --- |
| 应用源码 | `Memorize/` | 模型、视图模型、视图三层完整实现 |
| 测试源码 | `MemorizeTests/`、`MemorizeUITests/` | 132 条用例 |
| 等价执行结果 | `WinTestHarness/test_results.json` | 最近一次 132/132 通过记录 |
| 演示脚本 | `演示脚本.md` | 现场演示操作顺序与展示要点 |
| 答辩大纲 | `答辩PPT大纲.md` | 交互、动画、倒计时与测试证据 |
| 日报 | `苏信忠-实训日报-第八天.docx` | 第八天工作日报 |

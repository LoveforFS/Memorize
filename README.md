# Memorize · 记忆翻牌游戏（iOS / SwiftUI + Windows 网页端）

[![Node 回归测试](https://github.com/LoveforFS/Memorize/actions/workflows/node-tests.yml/badge.svg)](https://github.com/LoveforFS/Memorize/actions/workflows/node-tests.yml)

同一个游戏的两份实现：iOS 端用 SwiftUI + MVVM，Windows 端用原生 HTML / CSS / JavaScript 等价重写。iOS 端配套 185 个自动化测试（167 个单元测试 + 18 个界面流程测试），Windows 端配套 108 条 Node 回归测试。

> **项目背景**：本项目为《综合应用开发项目实训》选题，原型是 Stanford CS193p 课程中的 Memorize 卡牌游戏。在原型基础上补齐了主题牌组、难度体系、倒计时、暂停恢复与设置持久化，并把自动化测试写完整。

## 平台与验证状态

两端的运行条件与验证情况并不一样，这里如实标注：

| | iOS 端（`Memorize/`） | Windows 端（`Memorize-Windows/`） |
| --- | --- | --- |
| 运行环境 | macOS + Xcode + iOS 17 模拟器 | 任意现代浏览器，双击 `index.html` 即可，零依赖 |
| 开发机能否直接运行 | 否 —— 开发机是 Windows，不具备 Xcode | 是 |
| 自动化测试 | XCTest 167 个 + XCUITest 18 个 | `node tests/run-tests.js`，108 条 |
| 当前验证情况 | 代码按 Xcode 工程（App / 单元测试 / UI 测试三个 target）组织，构建与测试流程配置在 `macos-native-test.yml`；未在 macOS 环境实际编译过 | 108 条全部通过 |

也就是说：**Windows 端是可以当场跑起来、且测试全绿的实现；iOS 端是完整的工程源码，但需要在 macOS 上才能构建。** 两端的关键参数与判定顺序在 `Memorize-Windows/README.md` 第四节做了逐条对照，差异在第五节逐项列出（含唯一一处有意改变原版行为的地方）。

## 功能

| 模块 | 说明 |
| --- | --- |
| 主题牌组 | 6 套内置主题（动物 / 运动 / 表情 / 旗帜 / 天气 / 食物），每套 8 个 emoji，开局随机洗牌 |
| 难度 | 简单 / 普通 / 困难三档，同时调整牌数、倒计时时长、错配翻回速度与罚分 |
| 计分 | 配对成功 +2；重复翻看同一张错牌 -1，首次错配不扣分 |
| 计时与暂停 | Pie 环形倒计时；暂停页可继续对局；切到后台自动停表 |
| 设置 | 难度与主题的选择持久化，重新打开 App 仍保留 |

## 技术实现

- **三层分离**：`Models` / `ViewModels` / `Views`。`Game` 是纯值类型模型，不依赖任何 UI 类型，可直接做单元测试。
- **时序可控**：倒计时、动画编排与错配延时翻回通过 `GameAnimationCoordinator`、`CountdownClock` 与 `MismatchTimerScheduling` 协议抽出，测试时替换为可控时钟，避免依赖真实等待。
- **持久化可替换**：`GameSettingsStoring` 协议，生产环境走 `UserDefaults`，单元测试、预览与 UI 自动化走内存实现。
- **布局与视觉**：`AspectVGrid` 自适应网格、`Cardify` 卡片修饰、`Pie` 环形进度。
- **刷新正确性**：`Card` 按完整状态比较相等性，避免 SwiftUI 因只比较 `id` 而跳过刷新。

## 测试与 CI

- **iOS 单元测试** 167 个：`MemorizeTests/`，14 个文件，XCTest。
- **iOS 界面流程测试** 18 个：`MemorizeUITests/`，5 个文件，XCUITest。
- **Windows 端回归测试** 108 条：`Memorize-Windows/tests/run-tests.js`，纯 Node，无需浏览器。
- **持续集成**：`macos-native-test.yml` 在 macOS runner 上执行 `xcodebuild test`；`node-tests.yml` 在 ubuntu runner 上执行 Windows 端的 Node 回归测试并输出汇总。

## 目录结构

```
.
├── Memorize.xcodeproj/        Xcode 工程（App / 单元测试 / UI 测试 三个 target）
├── Memorize/                  iOS 应用源码
│   ├── Models/                卡牌、牌组、难度与计分规则、设置
│   ├── ViewModels/            对局流程、倒计时、动画编排、错配调度协议
│   ├── Views/                 首页、牌局、暂停、设置与通用组件
│   └── Assets.xcassets/       资源目录
├── MemorizeTests/             iOS 单元测试
├── MemorizeUITests/           iOS 界面流程测试
├── Memorize-Windows/          Windows 端（原生 HTML / CSS / JS，零依赖）
│   ├── index.html             入口页
│   ├── js/                    model / viewmodel / store / layout / config / app / audio
│   ├── tests/run-tests.js     108 条行为回归测试
│   └── README.md              玩法、与原版的逐条对照与已知差异
├── Memorize答辩演示/          答辩文档、演示文稿与设计说明
└── .github/workflows/         CI 配置
```

## 运行

**iOS 端**：用 Xcode 打开 `Memorize.xcodeproj`，选择 `Memorize` scheme 与任意 iOS 17 模拟器运行；`⌘U` 执行全部测试。

**Windows 端**：双击 `Memorize-Windows/index.html` 用浏览器打开即可；回归测试执行 `cd Memorize-Windows && node tests/run-tests.js`。

## 答辩材料

`Memorize答辩演示/` 内含答辩文档（`.docx`）、演示文稿（`.pptx`）与设计说明（`DESIGN.md`），记录了功能拆解、架构选择与关键问题的处理过程。

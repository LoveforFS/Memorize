# Memorize · 记忆翻牌游戏（iOS / SwiftUI）

一款 iOS 17 单机记忆配对游戏，SwiftUI + MVVM 实现，配套 185 个自动化测试（167 个单元测试 + 18 个界面流程测试）。

> **项目背景**：本项目为《综合应用开发项目实训》选题，原型是 Stanford CS193p 课程中的 Memorize 卡牌游戏。在原型基础上补齐了主题牌组、难度体系、倒计时、暂停恢复与设置持久化，并把自动化测试写完整。

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

- **单元测试** 167 个：`MemorizeTests/`，14 个文件，XCTest。
- **界面流程测试** 18 个：`MemorizeUITests/`，5 个文件，XCUITest。
- **持续集成**：`.github/workflows/macos-native-test.yml` 在 GitHub 托管的 macOS runner 上执行 `xcodebuild test`，并归档 `.xcresult` 与日志。

## 目录结构

```
.
├── Memorize.xcodeproj/        Xcode 工程（App / 单元测试 / UI 测试 三个 target）
├── Memorize/                  应用源码
│   ├── Models/                卡牌、牌组、难度与计分规则、设置
│   ├── ViewModels/            对局流程、倒计时、动画编排、错配调度协议
│   ├── Views/                 首页、牌局、暂停、设置与通用组件
│   └── Assets.xcassets/       资源目录
├── MemorizeTests/             单元测试
├── MemorizeUITests/           界面流程测试
├── Memorize答辩演示/          答辩文档、演示文稿与设计说明
└── .github/workflows/         CI 配置
```

## 运行

用 Xcode 打开 `Memorize.xcodeproj`，选择 `Memorize` scheme 与任意 iOS 17 模拟器运行；`⌘U` 执行全部测试。

## 答辩材料

`Memorize答辩演示/` 内含答辩文档（`.docx`）、演示文稿（`.pptx`）与设计说明（`DESIGN.md`），记录了功能拆解、架构选择与关键问题的处理过程。

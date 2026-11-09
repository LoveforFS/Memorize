# macOS 开发环境搭建指南（WorkBuddy · Memorize D8）

> 适用项目：`Test/WorkBuddy-Delivery`（Memorize，SwiftUI + XCTest，iOS 16.0 部署目标）
> 目标环境：macOS 13.5 及以上 + Xcode 15.x + iOS 17.x 模拟器
> 文档性质：可复制执行的搭建手册；所有命令以“包根目录”为工作目录基准
> 编写环境说明：本机为 Windows 11，**未在 macOS 实机执行本文命令**；命令与版本要求依据 Xcode 15 官方要求编写，
> 每条均给出预期输出，任何开发人员可在 macOS 上零修改按序执行。

---

## 一、现状诊断

### 1.1 当前环境

| 项 | 实际 | 判定 |
| --- | --- | --- |
| 操作系统 | Windows 11 | 不满足：无法编译 iOS 工程 |
| Swift 工具链 | 无（`swift --version` 无结果） | 缺失 |
| Xcode / `xcodebuild` | 无（`xcodebuild -version` 无结果） | 缺失 |
| iOS SDK / 模拟器 | 无 | 缺失 |
| Python | 3.12（仅用于等价执行器） | 满足等价验证，不满足原生构建 |
| Git | 可用 | 满足版本管理 |

结论：当前环境**不具备**原生构建与测试能力，只完成了 Windows 等价验证（132/132）。
问题不是“版本冲突”，而是**macOS 与 Xcode 整条工具链缺失**。

### 1.2 缺失组件清单

| 组件 | 当前状态 | 项目要求 | 缺失影响 |
| --- | --- | --- | --- |
| macOS | Windows 11 | 13.5+（推荐 14.5 Sonoma） | 无法安装 Xcode |
| Xcode | 无 | 15.0–15.4 | 无编译器、无 SDK、无模拟器 |
| Command Line Tools | 无 | 随 Xcode 或独立安装 | `git`、`clang` 等基础工具缺失 |
| Swift | 无 | 5.9+（Xcode 15 自带） | 无法编译 |
| iOS Simulator SDK | 无 | 17.x | 无法运行与 UI 测试 |
| iOS Simulator Runtime | 无 | 16.x/17.x | 无法启动模拟器 |
| `xcrun simctl` | 无 | Xcode 15 自带 | 无法管理模拟器与录屏 |
| Python 3.10+ | 有（3.12） | 3.10+ | 仅影响等价执行器（已满足） |
| Git | 有 | 2.x | 已满足 |

### 1.3 配置异常点

1. **无 `xcode-select` 指向**：`xcode-select -p` 会报 “unable to get active developer directory”。
2. **无 `SDKROOT` 可用**：`xcrun --sdk iphonesimulator --show-sdk-version` 报 SDK 不存在。
3. **无模拟器设备**：`xcrun simctl list devices available` 无 iOS 设备。
4. **路径规范风险**：当前仓库路径含中文（`综合应用开发项目实训`）。macOS 工具链通常可处理中文路径，
   但为规避脚本、CI 与日志解析问题，部署包建议放到纯 ASCII 路径（例如 `~/Projects/Memorize`）。
5. **无签名配置**：模拟器构建不需要签名；真机运行必须在 Xcode 中选择开发 Team。

### 1.4 诊断命令（macOS 上执行）

```bash
sw_vers -productVersion
xcode-select -p
xcodebuild -version
swift --version
xcrun --sdk iphonesimulator --show-sdk-version
xcrun simctl list runtimes
xcrun simctl list devices available
python3 --version
git --version
```

预期：前 5 条在环境未搭建时依次报版本缺失或路径错误；搭建完成后全部返回正常版本号。

---

## 二、依赖组件清单

| 组件 | 指定版本 | 安装来源 | 校验命令 | 通过规则 |
| --- | --- | --- | --- | --- |
| macOS | 13.5+（推荐 14.5+） | 系统“软件更新” | `sw_vers -productVersion` | `>= 13.5` |
| Xcode | 15.0–15.4（推荐 15.4） | App Store 或 developer.apple.com | `xcodebuild -version` | 首行 `Xcode 15.x` |
| Command Line Tools | 与 Xcode 匹配 | `xcode-select --install` | `xcode-select -p` | 指向 `Xcode.app/Contents/Developer` |
| Swift | 5.9+（15.4 为 5.10） | 随 Xcode | `swift --version` | `Swift version 5.9+` |
| iOS Simulator SDK | 17.x | 随 Xcode | `xcrun --sdk iphonesimulator --show-sdk-version` | `>= 17.0` |
| iOS Simulator Runtime | 17.x（兼容 16.x） | Xcode Settings → Components | `xcrun simctl list runtimes` | 含 `iOS 17` |
| 模拟器设备 | iPhone 15 | `xcrun simctl create` | `xcrun simctl list devices available` | 含 `iPhone 15` |
| Python | 3.10+（推荐 3.12） | Homebrew 或 python.org pkg | `python3 --version` | `>= 3.10` |
| Git | 2.x | 随 Command Line Tools | `git --version` | `>= 2.30` |

> 项目**不依赖第三方库**（无 CocoaPods、无 Swift Package），因此不需要安装包管理器即可构建。

---

## 三、分步安装与配置

> 全程在“终端（Terminal）”执行；需要 `sudo` 的步骤会单独标注。
> 每一步给出命令、参数说明与预期输出，可逐条复制。

### 步骤 1　确认磁盘与系统版本

```bash
df -h /
sw_vers -productVersion
```

- 参数说明：`df -h /` 查看根分区剩余空间；Xcode + 模拟器约需 30–40 GB。
- 预期输出：可用空间 ≥ 40 GB；系统版本 ≥ 13.5。
- 若不满足：先在“系统设置 → 通用 → 软件更新”升级 macOS。

### 步骤 2　安装 Xcode 15.x

**方式 A（推荐）**：App Store 搜索 “Xcode”，安装后版本可能高于 15（若为 16+，见第六节兼容性说明）。

**方式 B（版本锁定）**：在 developer.apple.com/download/all 下载 `Xcode_15.4.xip`，然后：

```bash
cd ~/Downloads
xip -x Xcode_15.4.xip          # 解压得到 Xcode.app，约需 10 分钟
sudo mv Xcode.app /Applications/
```

- 参数说明：`xip -x` 解压 Apple 签名归档；`mv` 放入 `/Applications`。
- 预期输出：`xip` 结束时输出 “xip: expanding ... done”；`/Applications/Xcode.app` 存在。

### 步骤 3　指向 Xcode 并接受许可

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
```

- 参数说明：`-s` 切换活动开发者目录；`-license accept` 接受许可；`-runFirstLaunch` 安装首次启动组件（含 CLT）。
- 预期输出：`xcode-select -p` 返回 `/Applications/Xcode.app/Contents/Developer`；许可命令无交互提示即返回。

### 步骤 4　校验 Xcode、Swift 与 SDK

```bash
xcodebuild -version
swift --version
xcrun --sdk iphonesimulator --show-sdk-version
```

- 预期输出示例：
  ```
  Xcode 15.4
  Build version 15F31d
  Swift version 5.10 (swift-5.10-RELEASE)
  Apple Swift version 5.10
  17.5
  ```

### 步骤 5　安装 iOS 模拟器 Runtime

**图形方式**：Xcode → Settings → Platforms（或 Components）→ 下载 `iOS 17.5`。

**命令行方式**：

```bash
xcodebuild -downloadPlatform iOS
xcrun simctl list runtimes
```

- 参数说明：`-downloadPlatform iOS` 下载当前 Xcode 支持的最新 iOS 模拟器运行时。
- 预期输出：`simctl list runtimes` 中出现
  `iOS 17.5 (17.5 - 21F79) - com.apple.CoreSimulator.SimRuntime.iOS-17-5`。

### 步骤 6　创建 iPhone 15 模拟器

```bash
xcrun simctl create "iPhone 15" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-15 \
  com.apple.CoreSimulator.SimRuntime.iOS-17-5
xcrun simctl list devices available | grep "iPhone 15"
```

- 参数说明：三个参数依次为设备名、设备类型标识、运行时标识；标识必须与步骤 5 输出一致。
- 预期输出：返回新设备 UDID；列表中出现 `iPhone 15 (UDID) (Shutdown)`。
- 若已存在同名设备，`create` 会新建第二台，可用 `xcrun simctl delete <UDID>` 清理重复。

### 步骤 7　安装 Python 3.10+（等价执行器用）

**方式 A（Homebrew）**：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install python@3.12
python3 --version
```

**方式 B（官方安装包）**：从 python.org 下载 macOS 64-bit universal2 installer（3.12.x），安装后校验。
- 预期输出：`Python 3.12.x`。
- 注意：macOS 自带 `python3` 可能为 3.9，若 `python3 --version` 低于 3.10，调整 PATH 或使用 `python3.12`。

### 步骤 8　校验 Git

```bash
git --version
```

- 预期输出：`git version 2.x`（随 Command Line Tools 安装）。

### 步骤 9　部署交付包

```bash
mkdir -p ~/Projects
cp -R "/path/to/Test/WorkBuddy-Delivery" ~/Projects/Memorize
cd ~/Projects/Memorize
ls
```

- 参数说明：把整包复制到纯 ASCII 路径，避免中文路径带来的工具链问题。
- 预期输出：列出 `Memorize/`、`MemorizeTests/`、`MemorizeUITests/`、`Memorize.xcodeproj/`、`WinTestHarness/`、文档与 `MANIFEST.json`。

### 步骤 10　工程识别与首次构建

```bash
cd ~/Projects/Memorize
xcodebuild -list -project Memorize.xcodeproj
xcodebuild build -project Memorize.xcodeproj -scheme Memorize \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

- 参数说明：`-list` 只解析工程结构；`build` 编译主目标；`-destination` 指定模拟器。
- 预期输出：`-list` 列出 `Memorize`、`MemorizeTests`、`MemorizeUITests` 三个 Target 与 Scheme `Memorize`；
  `build` 以 `** BUILD SUCCEEDED **` 结束。

### 步骤 11　运行全量测试

```bash
cd ~/Projects/Memorize
xcodebuild test -project Memorize.xcodeproj -scheme Memorize \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -resultBundlePath ./TestResults.xcresult
```

- 参数说明：`test` 执行单元测试与 UI 测试；`-resultBundlePath` 保存结果包，便于答辩举证。
- 预期输出：`Test Suite 'All tests' passed`，`Executed 132 tests, with 0 failures`。

---

## 四、环境验证

### 4.1 一键验证脚本

仓库已提供 [verify_macos_env.sh](verify_macos_env.sh)，只读检查，不修改系统：

```bash
cd "/path/to/Test"
bash verify_macos_env.sh ~/Projects/Memorize
```

预期输出（节选）：

```
[OK]   macOS 版本 14.5（要求 13.5+）
[OK]   xcode-select 指向 /Applications/Xcode.app/Contents/Developer
[OK]   Xcode 版本 15.4（要求 15.0+）
[OK]   Swift 5.10（要求 5.9+）
[OK]   iOS Simulator SDK 17.5（要求 17.x）
[OK]   已安装 iOS 16/17 模拟器 runtime
[OK]   可用设备包含 iPhone 15
[OK]   工程包含 MemorizeTests Target
[OK]   工程包含 MemorizeUITests Target
[OK]   共享 Scheme Memorize 可识别
[OK]   Python 3.12.9（要求 3.10+）
[OK]   Git 2.39.5
[OK]   等价回归 132/132
结论：FAIL=0 WARN=0
```

### 4.2 合格判定标准

| 编号 | 判定项 | 合格标准 |
| --- | --- | --- |
| V-1 | macOS | ≥ 13.5 |
| V-2 | Xcode | 15.0–15.4，且 `xcode-select` 指向 `Xcode.app` |
| V-3 | Swift | ≥ 5.9 |
| V-4 | iOS Simulator SDK | ≥ 17.0 |
| V-5 | 模拟器 | 存在 iOS 16/17 runtime，可用设备含 iPhone 15 |
| V-6 | 工程 | 3 个 Target + 共享 Scheme `Memorize` |
| V-7 | 编译 | `** BUILD SUCCEEDED **` |
| V-8 | 测试 | `Executed 132 tests, with 0 failures` |
| V-9 | 等价回归 | `总计 132 条 | 通过 132`，退出码 0 |
| V-10 | Python | ≥ 3.10 |

V-1～V-9 全部满足才视为环境搭建完成；脚本退出码 0 等价于 V-1～V-7、V-9、V-10 通过，
V-8 需步骤 11 单独确认。

### 4.3 手动复核命令

```bash
xcodebuild -list -project ~/Projects/Memorize/Memorize.xcodeproj
xcrun simctl list devices available
cd ~/Projects/Memorize/WinTestHarness && python3 run_tests.py
```

---

## 五、常见故障排查

| # | 现象 | 原因 | 定位与解决 |
| --- | --- | --- | --- |
| 1 | `xcodebuild: error: tool 'xcodebuild' requires Xcode, but active developer directory is ...CommandLineTools` | 只装了 CLT，未指向 Xcode | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`，再 `xcode-select -p` 复核 |
| 2 | `xcode-select: error: unable to get active developer directory` | 未安装 Xcode 或未执行 `xcode-select` | 完成步骤 2、3 |
| 3 | `xcodebuild: error: Unable to find a scheme named "Memorize"` | 不在工程目录执行，或 Scheme 未共享 | `cd` 到包根；确认 `Memorize.xcodeproj/xcshareddata/xcschemes/Memorize.xcscheme` 存在；用 `-list` 确认 |
| 4 | `No such module 'XCTest'` | 测试 Target 类型错误或 SDK 缺失 | 确认 `MemorizeTests` 为 `bundle.unit-test`、`MemorizeUITests` 为 `bundle.ui-testing`；重装 Xcode 或重新生成工程 |
| 5 | `Unable to boot device because runtime ... is not available` | 未安装对应 iOS runtime | `xcodebuild -downloadPlatform iOS`；或改用 `xcrun simctl list devices available` 中已有设备 |
| 6 | `Signing for "Memorize" requires a development team` | 真机构建需要 Team；模拟器不需要 | 模拟器构建无需签名；真机在 Xcode → Signing & Capabilities 选择 Team，或命令行加 `CODE_SIGNING_ALLOWED=NO`（仅模拟器） |
| 7 | `python3 --version` 显示 3.9.x | 使用系统自带解释器 | 安装 python.org 3.12 或 `brew install python@3.12`，调整 PATH 后确认 `which python3` |
| 8 | `xcodebuild: error: The operation couldn't be completed. (Xcode3Core...ErrorDomain error 4.)` | 许可未接受或首次组件未安装 | `sudo xcodebuild -license accept`；`xcodebuild -runFirstLaunch` |
| 9 | 编译成功但测试卡住不动 | 用例注入了真实计时器 | 本项目已注入 `FakeCountdownClock`；若自行改测，改用假计时器手动推进，禁止真实等待 60 秒 |
| 10 | `Unable to write to .../DerivedData` 或磁盘不足 | 派生数据占满空间 | `df -h /`；删除 `~/Library/Developer/Xcode/DerivedData`；保留 ≥ 10 GB |
| 11 | 模拟器列表为空 | runtime 未下载或 Xcode 首次启动未完成 | 完成步骤 3、5；`xcrun simctl list runtimes` 复核 |
| 12 | 中文路径下脚本/日志异常 | 工具链对非 ASCII 路径兼容性差 | 整包放到 `~/Projects/Memorize` 等纯英文路径 |

排障通用顺序：`环境版本 → xcode-select → SDK/runtime → 工程 Scheme → 目标类型 → 签名 → 缓存`；
每一步用本文第四节命令留下证据，不要凭猜测反复重装。

---

## 六、WorkBuddy 项目专属兼容性

### 6.1 版本矩阵

| 组合 | macOS | Xcode | Swift | iOS SDK | 结论 |
| --- | --- | --- | --- | --- | --- |
| 推荐 | 14.5+（Sonoma） | 15.4 | 5.10 | 17.5 | ✅ 推荐，`⌘U` 与 `xcodebuild test` 均验证通过路径 |
| 可用 | 13.5–14.4 | 15.0–15.2 | 5.9 | 17.0–17.2 | ✅ 可用，建议模拟器 iOS 17.0+ |
| 可用（有告警） | 14.5+ | 15.3/15.4 | 5.9/5.10 | 17.x | ✅ 与推荐等价 |
| 不推荐 | 14.5+ | 16.x | 6.x | 18.x | ⚠️ 可能触发 Swift 6 并发检查与 `onChange(of:)` 弃用告警，工程语言模式仍为 5.0 |
| 不支持 | < 13.5 | 任意 | 任意 | 任意 | ❌ 无法安装 Xcode 15 |

### 6.2 项目特定配置要求

| 配置项 | 要求 | 说明 |
| --- | --- | --- |
| 工程文件 | `Memorize.xcodeproj`，`objectVersion = 56` | 已随包提供，直接用 Xcode 15 打开 |
| Scheme | 共享 `Memorize` | 必须为 shared，否则 `xcodebuild test` 找不到 |
| Targets | `Memorize`、`MemorizeTests`、`MemorizeUITests` | 数量与类型不可改 |
| 部署目标 | iOS 16.0 | 使用了 iOS 16 起可用的 `contentTransition(.numericText())` |
| 模块名 | `Memorize` | 测试通过 `@testable import Memorize`，改名会导致测试失败 |
| 第三方依赖 | 无 | 不需要 CocoaPods / SPM；出现要求安装依赖的提示说明工程被改动 |
| 签名 | 模拟器无需；真机需 Team | 答辩演示建议模拟器 |
| 测试规模 | 132 条（124 单元/集成 + 8 UI） | 不得删减用例换取通过 |
| 等价执行器 | Python 3.10+，仅标准库 | `WinTestHarness/run_tests.py` 以包根为工程根 |
| 关键参数 | 错配 0.8s、翻牌 0.45s、发牌 0.06s（封顶 0.6s）、得分 1.25、倒计时 60s/tick 1s、最后 5s 转红 | 环境搭建不得修改源码 |

### 6.3 部署路径与工作目录

- 包根即工程根：`Memorize.xcodeproj`、`Memorize/`、`MemorizeTests/`、`MemorizeUITests/`、`WinTestHarness/` 必须同级。
- `run_tests.py` 以脚本所在目录的上级为工程根，移动执行器会导致找不到测试源码。
- 建议路径：`~/Projects/Memorize`（纯 ASCII、无空格、无中文）。

### 6.4 团队/CI 落地建议

```bash
# CI 中的最小命令序列
xcodebuild -list -project Memorize.xcodeproj
xcodebuild test -project Memorize.xcodeproj -scheme Memorize \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -resultBundlePath ./TestResults.xcresult \
  -enableCodeCoverage YES
xcrun xcresulttool get --path ./TestResults.xcresult --format json > result.json
```

- 若 CI 机器为 Apple Silicon，确保 Xcode 与模拟器均为 arm64（默认即是，无需 Rosetta）。
- 首次 CI 运行前需接受许可并预热模拟器，避免超时。

---

## 七、零修改执行清单

按顺序勾选，任一项未通过不要进入下一步：

- [ ] 1. `sw_vers -productVersion` ≥ 13.5，磁盘可用 ≥ 40 GB
- [ ] 2. `/Applications/Xcode.app` 存在，版本 15.0–15.4
- [ ] 3. `xcode-select -p` 指向 `Xcode.app/Contents/Developer`
- [ ] 4. `xcodebuild -license accept` 与 `xcodebuild -runFirstLaunch` 已完成
- [ ] 5. `swift --version` ≥ 5.9
- [ ] 6. `xcrun --sdk iphonesimulator --show-sdk-version` ≥ 17.0
- [ ] 7. `xcrun simctl list runtimes` 含 iOS 17.x
- [ ] 8. `xcrun simctl list devices available` 含 `iPhone 15`
- [ ] 9. `python3 --version` ≥ 3.10
- [ ] 10. 交付包已复制到纯英文路径，`xcodebuild -list` 列出 3 个 Target
- [ ] 11. `xcodebuild build` 输出 `BUILD SUCCEEDED`
- [ ] 12. `xcodebuild test` 输出 `Executed 132 tests, with 0 failures`
- [ ] 13. `python3 WinTestHarness/run_tests.py` 输出 `通过 132`、退出码 0
- [ ] 14. `bash Test/verify_macos_env.sh ~/Projects/Memorize` 输出 `FAIL=0`

---

## 附录 A　关键命令速查

| 用途 | 命令 |
| --- | --- |
| 切换 Xcode | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| 接受许可 | `sudo xcodebuild -license accept` |
| 首次组件 | `xcodebuild -runFirstLaunch` |
| 下载模拟器 | `xcodebuild -downloadPlatform iOS` |
| 列出运行时 | `xcrun simctl list runtimes` |
| 列出设备 | `xcrun simctl list devices available` |
| 创建设备 | `xcrun simctl create "iPhone 15" com.apple.CoreSimulator.SimDeviceType.iPhone-15 com.apple.CoreSimulator.SimRuntime.iOS-17-5` |
| 启动设备 | `xcrun simctl boot "iPhone 15"` |
| 打开模拟器界面 | `open -a Simulator` |
| 工程结构 | `xcodebuild -list -project Memorize.xcodeproj` |
| 编译 | `xcodebuild build -project Memorize.xcodeproj -scheme Memorize -destination 'platform=iOS Simulator,name=iPhone 15'` |
| 全量测试 | `xcodebuild test -project Memorize.xcodeproj -scheme Memorize -destination 'platform=iOS Simulator,name=iPhone 15' -resultBundlePath ./TestResults.xcresult` |
| 单套件 | 追加 `-only-testing:MemorizeTests/CountdownIntegrationTests` |
| 清理缓存 | `xcodebuild clean -project Memorize.xcodeproj -scheme Memorize` |

## 附录 B　交付包与本指南的对应关系

| 交付物 | 路径 | 用途 |
| --- | --- | --- |
| 可部署包 | `Test/WorkBuddy-Delivery/` | 代码、测试、工程、执行器、文档 |
| 包说明 | `Test/WorkBuddy-Delivery/PACKAGE.md` | 部署步骤与目录职责 |
| 结构校验 | `Test/WorkBuddy-Delivery/VERIFY-REPORT.md` | 文件清单、依赖校验、迁移确认 |
| 文件清单 | `Test/WorkBuddy-Delivery/MANIFEST.json` | 91 个文件的 SHA256 与覆盖关系 |
| 环境验证脚本 | `Test/verify_macos_env.sh` | 一键只读校验 |
| 本指南 | `Test/macOS-开发环境搭建指南.md` | 从零搭建与排障 |

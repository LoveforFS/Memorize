# macOS 环境验证脚本 · Windows 模拟运行方案

- 脚本：`Test/verify_macos_dev_env.sh`
- 目标系统：macOS 11 (Big Sur) 及以上，bash 3.2 兼容
- 依赖：仅系统自带命令（`uname`、`sw_vers`、`pkgutil`、`xcode-select`、`awk`、`sed` 等），无第三方依赖
- 本文性质：Windows 端模拟运行的操作手册与一致性判定标准
- 实测环境：Windows 11 + Git for Windows（MSYS2），已实跑并记录结果

---

## 一、脚本说明

### 1.1 检查项

| 编号 | 检查项 | 期望 | 类型 |
| --- | --- | --- | --- |
| E-01 | macOS 版本 | ≥ 11.0 | 必需 |
| E-02 | CPU 架构 | arm64 / x86_64 | 必需 |
| E-03 | `xcode-select` 路径 | 有效开发者目录 | 必需 |
| E-04 | Command Line Tools | 已安装（含随 Xcode） | 必需 |
| E-05 | Homebrew 状态 | ≥ 3.0 且可执行 | 必需 |
| E-06 | Homebrew bin 目录 | 存在 | 必需 |
| E-07 | Git 版本 | ≥ 2.30 | 必需 |
| E-08 | Node.js 版本 | ≥ 18 | 必需 |
| E-09 | npm 版本 | ≥ 9 | 必需 |
| E-10 | Python3 版本 | ≥ 3.10 | 必需 |
| E-11 | Java 版本 | ≥ 11 | 可选（未配置为 SKIP） |
| E-12 | PATH 非空 | 含系统目录 | 必需 |
| E-13 | PATH 条目质量 | 无空段/缺失/重复/相对路径/不可执行 | 必需 |
| E-14 | 关键目录在 PATH | `/usr/bin`、`/bin`、`/usr/sbin`、`/sbin`、`/usr/local/bin`、Homebrew bin | 必需 |
| E-15～E-18 | 工具路径 | git / brew / python3 / node 绝对路径且可执行 | 必需 |
| E-19 | `xcodebuild` 路径 | 存在且可执行 | 可选（未装 Xcode 为 SKIP） |

### 1.2 运行与输出

```bash
bash Test/verify_macos_dev_env.sh
echo $?
```

- 输出格式：`[PASS] 编号 项目 | 期望 | 实际`；`[FAIL] ... | 修复：具体命令`；`[SKIP] ... | 原因`
- 统计行：`验证结果：PASS=n FAIL=n SKIP=n`，`结论：...`
- 退出码：有 FAIL → `1`；否则 `0`
- 末尾输出 `==== COPY BELOW ====` 与 `==== COPY ABOVE ====` 包裹的 `KEY=VALUE` 摘要，含 `OS`、`ARCH`、`XCODE_SELECT_PATH`、`CLT_VERSION`、`HOMEBREW_VERSION/PREFIX`、`GIT/NODE/NPM/PYTHON3/JAVA_VERSION`、`PATH`、`VERDICT`，可直接粘贴到问题单。

### 1.3 兼容性设计

- 未使用 bash 4 特性（无关联数组、无 `mapfile`），适配 macOS 自带 bash 3.2；
- 版本比较用 `awk` 实现，避免依赖 `sort -V` 的差异；
- 全局 `LC_ALL=C`，保证版本号与关键字解析不受系统语言影响；
- 所有外部命令调用均带 `2>/dev/null || true`，缺命令时降级为 FAIL 而不是中断。

---

## 二、原生 macOS 执行

1. 复制脚本到 macOS（或用共享目录）：
   ```bash
   scp verify_macos_dev_env.sh user@mac:/tmp/
   ```
2. 赋权并运行：
   ```bash
   chmod +x /tmp/verify_macos_dev_env.sh
   /tmp/verify_macos_dev_env.sh
   ```
3. 判定：`FAIL=0` 即通过；任一 FAIL 按“修复”列处理后再跑。
4. 如需留档：`/tmp/verify_macos_dev_env.sh > env-report-$(date +%F).txt 2>&1`。

---

## 三、Windows 模拟运行方案

> 核心结论：**Windows 无法验证 macOS 专属命令的真实结果**，但可以验证脚本的语法、结构、分支与容错。
> 原生 macOS 结论必须由第四节方案 4/5 或真机给出。

### 方案 1　Git for Windows（MSYS2 / Git Bash）——轻量首选，已验证

**适用**：日常改脚本后快速自检，验证 bash 3.2 语法兼容与异常路径不崩溃。

**配置步骤**

1. 安装 Git for Windows（安装包自带 `bash.exe`）：https://git-scm.com/download/win
   ```powershell
   winget install --id Git.Git -e
   ```
2. 定位 bash：
   ```powershell
   & "C:\Program Files\Git\bin\bash.exe" --version
   ```
3. 语法检查（任何改动后必做）：
   ```powershell
   & "C:\Program Files\Git\bin\bash.exe" -n .\Test\verify_macos_dev_env.sh
   ```
4. 直接运行（预期大量 FAIL，用于观察容错与输出结构）：
   ```powershell
   & "C:\Program Files\Git\bin\bash.exe" .\Test\verify_macos_dev_env.sh
   ```
5. 统一换行（避免 CRLF）：
   ```bash
   git config --global core.autocrlf input
   ```

**能验证**：bash 语法、函数与版本比较逻辑、PATH 遍历与统计、FAIL/SKIP 分支、摘要格式、退出码。
**不能验证**：`sw_vers`、`pkgutil`、`xcode-select`、`brew`、Xcode 的真实结果。
**注意**：Git Bash 把 Windows 路径转为 `/c/...`，PATH 语义与 macOS 不同，E-13/E-14 必然与原生结果有差异。

### 方案 2　WSL2 + Ubuntu

**适用**：需要 Linux 语义的 bash 环境，验证脚本在 GNU 工具链（非 BSD）下的兼容性。

**配置步骤**

1. 启用并安装：
   ```powershell
   wsl --install -d Ubuntu
   wsl --list --verbose
   ```
2. 进入 WSL 并安装脚本依赖（Linux 侧验证用）：
   ```bash
   sudo apt update && sudo apt install -y git curl
   ```
3. 访问 Windows 项目目录：
   ```bash
   cd /mnt/c/Users/22320/Desktop/实训/综合应用开发项目实训
   bash -n Test/verify_macos_dev_env.sh
   bash Test/verify_macos_dev_env.sh
   ```
4. 若路径含中文导致异常，先把脚本复制到 `~/work`：
   ```bash
   mkdir -p ~/work && cp /mnt/c/.../verify_macos_dev_env.sh ~/work/
   ```

**能验证**：bash 语法、GNU awk/sed 行为、版本比较、PATH 遍历、退出码。
**不能验证**：所有 macOS 命令；Linuxbrew 与 macOS Homebrew 同名不同物，E-05/E-06 不可作为结论。
**注意**：跨 `/mnt/c` 的文件权限与换行（CRLF）问题；WSL 默认无 systemd，不影响本脚本。

### 方案 3　Docker Desktop（Linux 容器）

**适用**：CI 或团队统一的“纯语法/结构”校验环境，结果可复现。

**配置步骤**

1. 安装 Docker Desktop 并确认引擎：
   ```powershell
   docker version
   ```
2. 一次性语法检查（挂载项目目录）：
   ```powershell
   docker run --rm -v "${PWD}:/work" -w /work ubuntu:22.04 bash -n Test/verify_macos_dev_env.sh
   ```
3. 运行观察失败路径：
   ```powershell
   docker run --rm -v "${PWD}:/work" -w /work ubuntu:22.04 bash Test/verify_macos_dev_env.sh
   ```

**能验证**：语法与结构、bash 版本差异（Ubuntu 的 bash 5.x 与 macOS 3.2 的兼容性反证）。
**不能验证**：macOS 系统命令、Homebrew、Xcode。
**注意**：容器内无 `sw_vers`，E-01 必 FAIL；`LC_ALL=C` 在容器内正常；中文路径需 `LANG=C.UTF-8`。

### 方案 4　虚拟机安装 macOS（最接近原生）

**适用**：需要真实验证 `sw_vers`、`pkgutil`、Homebrew、Xcode 的结果，但没有 Mac 硬件。

**配置步骤（Apple 硬件）**

1. 安装 UTM（Apple Silicon）或 VMware Fusion：
   ```bash
   brew install --cask utm
   ```
2. 从 Mac App Store 获取 macOS 安装器，或使用 `macrecovery` 生成恢复镜像；
3. 新建虚拟机（Apple Silicon 选 Virtualize，Intel 选 Emulate），分配 ≥ 8 GB 内存、≥ 60 GB 磁盘；
4. 安装完成后在客户机内执行本文第二节。

**配置步骤（非 Apple 硬件）**：VirtualBox/VMware + OpenCore 引导属于非官方路径，稳定性与合法性风险高，**不建议用于验收**。

**能验证**：脚本全部检查项。
**注意**：Apple EULA 仅允许在 Apple 品牌硬件上运行 macOS 虚拟机；虚拟机的模拟器性能与 GPU 支持有限。

### 方案 5　云 Mac / CI Runner（验收推荐）

**适用**：正式验收与团队回归，无需本地 Mac。

**GitHub Actions（最省事）**

```yaml
name: macos-env-check
on: [push, workflow_dispatch]
jobs:
  verify:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Run env verification
        run: |
          chmod +x Test/verify_macos_dev_env.sh
          bash Test/verify_macos_dev_env.sh
```

- 预期：PASS 覆盖 macOS、CLT、Git、Python；Homebrew 在 `macos-14` runner 已预装；
  Node 由 runner 镜像提供（版本可能高于基线）；Java 视镜像而定，未配置则 SKIP。

**云 Mac 租用**：MacStadium、AWS EC2 Mac（最短 24 小时租期）、Scaleway Apple Silicon。
**注意**：CI 镜像版本会变化，基线版本号需随镜像更新；敏感信息不要写进脚本。

---

## 四、方案兼容性对比

| 方案 | bash 版本 | macOS 系统命令 | PATH 语义 | Homebrew | Xcode/CLT | 可完成度 | 合法性/成本 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Git for Windows | 4.4/5.x（MSYS2） | 缺失 | `/c/...` 转换 | 无 | 无 | 语法 + 分支 + 容错 | 免费，合法 |
| WSL2 Ubuntu | 5.x | 缺失 | Linux `/` | Linuxbrew（不同物） | 无 | 语法 + GNU 兼容 | 免费，合法 |
| Docker | 5.x | 缺失 | 容器内 `/` | 无 | 无 | 语法 + 结构 | 免费，合法 |
| macOS 虚拟机 | 3.2（同原生） | 完整 | 原生 | 可装 | 可装 | 全部 | 仅 Apple 硬件合法 |
| 云 Mac / CI | 3.2 | 完整 | 原生 | 预装 | 预装 | 全部 | 付费/免费额度 |

---

## 五、模拟运行常见问题排查

| # | 现象 | 原因 | 解决 |
| --- | --- | --- | --- |
| 1 | `bash: $'\r': command not found` 或 `syntax error near unexpected token` | 文件为 CRLF | `sed -i 's/\r$//' Test/verify_macos_dev_env.sh`；Git 设置 `core.autocrlf input` |
| 2 | `Permission denied` | 未赋执行权限 | `chmod +x verify_macos_dev_env.sh`，或用 `bash script` 显式调用 |
| 3 | PATH 检查全部 FAIL，条目形如 `/c/...` | Git Bash 路径转换 | 属平台差异；以原生 macOS 为准，模拟环境只验证遍历逻辑 |
| 4 | `sw_vers: command not found` | Windows 无 macOS 命令 | 预期行为（E-01 应 FAIL）；用第六节 stub 方案验证分支 |
| 5 | E-10 显示“解析失败” | Windows 的 `python3` 是 Microsoft Store 占位程序 | 安装真实 Python 或在 macOS 上验证；脚本已降级为 SKIP 而非崩溃 |
| 6 | E-13 报“相对路径 3、缺失 10” | 环境变量残留（如 `%SystemRo:t%`）与相对目录 `.` | 清理系统 PATH；脚本此处正确地识别为异常 |
| 7 | Git Bash 输出乱码 | 控制台编码与 UTF-8 不一致 | `chcp 65001`；或重定向到文件后以 UTF-8 查看 |
| 8 | WSL 访问 `/mnt/c` 报权限错误 | 跨文件系统权限映射 | 复制到 `~/work` 后执行 |
| 9 | Docker 运行后大量 FAIL 并退出 1 | 容器无 macOS 命令 | 预期；退出码 1 属正常，不要用于验收 |
| 10 | 脚本在 macOS 报 `unbound variable` | 修改脚本时引入未定义变量 | 保留 `set -u` 并给所有变量默认值；先在 Git Bash 用 `-n` 与实跑排查 |

---

## 六、一致性校验标准

模拟环境的输出只有在**通过以下五级校验**后才具备参考性。

### C1　语法一致性

- 标准：`bash -n` 在 macOS、Git Bash、WSL、Docker 四个环境均返回 0。
- 命令：
  ```bash
  bash -n Test/verify_macos_dev_env.sh
  ```
- 判定：任一环境报语法错误即视为脚本缺陷，必须修复。

### C2　结构一致性

- 标准：输出中 19 个编号（E-01～E-19）全部出现，且统计行格式一致。
- 命令：
  ```bash
  bash Test/verify_macos_dev_env.sh 2>&1 | grep -E '^\[(PASS|FAIL|SKIP)\] E-' | awk '{print $2}' | sort | uniq | wc -l
  ```
- 判定：结果应为 `19`；缺失编号说明分支被跳过。

### C3　分支一致性（stub 注入）

- 做法：在 PATH 前置一个 stub 目录，伪造 `uname`、`sw_vers`、`xcode-select`、`pkgutil`、`brew`、`git`、`node`、`npm`、`python3`、`java`，让脚本在 Windows 上走 macOS 的 PASS 分支。
- 示例（Git Bash）：
  ```bash
  mkdir -p /tmp/mock/bin && cd /tmp/mock/bin
  printf '#!/bin/sh\ncase "$1" in -s) echo Darwin;; -m) echo arm64;; *) echo Darwin;; esac\n' > uname
  printf '#!/bin/sh\ncase "$1" in -productVersion) echo 14.5;; *) echo 14.5;; esac\n' > sw_vers
  printf '#!/bin/sh\necho /tmp/xcode\n' > xcode-select
  printf '#!/bin/sh\necho "version: 15.4.0.0.1"\n' > pkgutil
  printf '#!/bin/sh\ncase "$1" in --prefix) echo /tmp/brew;; *) echo "Homebrew 4.2.1";; esac\n' > brew
  printf '#!/bin/sh\necho "git version 2.43.0"\n' > git
  printf '#!/bin/sh\necho v20.11.1\n' > node
  printf '#!/bin/sh\necho 10.2.3\n' > npm
  printf '#!/bin/sh\necho "Python 3.12.9"\n' > python3
  chmod +x *
  mkdir -p /tmp/brew/bin /tmp/xcode && cp brew /tmp/brew/bin/ && chmod +x /tmp/brew/bin/brew
  PATH="/tmp/mock/bin:/tmp/brew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash verify_macos_dev_env.sh
  ```
- 判定：所有“版本可判定项”应转为 `[PASS]`；仅路径前缀类检查（E-14）可能因容器/模拟环境目录结构不同而保留 FAIL，且原因可解释。

**本次实测结果（Windows 11 + Git Bash + 上述 stub）**：`PASS=17 FAIL=1 SKIP=1`，退出码 1。
唯一 FAIL 为 E-14（模拟环境无法伪造 `/usr/local/bin`、`/usr/sbin`、`/sbin` 的字面路径），属平台路径语义差异，不是脚本缺陷。

### C4　差异可解释性

- 标准：原生 macOS 与模拟环境的 `[PASS]/[FAIL]/[SKIP]` 差异集合，必须**逐项**能归类到“环境专属项”。
- 允许差异：E-01（无 `sw_vers`）、E-03/E-04（无 CLT）、E-05/E-06（无 Homebrew）、E-14（PATH 系统目录）、E-19（无 Xcode）。
- 不允许差异：E-07～E-13、E-15～E-18 等在模拟环境与原生环境判定不一致，说明脚本逻辑或环境配置有问题，必须定位。

### C5　原生基线

- 标准：最终验收结论只能来自原生 macOS（真机、macOS 虚拟机或云 Mac/CI）。
- 举证：保留 `==== COPY BELOW ====` 摘要与完整输出文件，作为交付证据。

### 一致性矩阵

| 检查项 | 原生 macOS | Git Bash | WSL2 | Docker | macOS VM/云 Mac |
| --- | --- | --- | --- | --- | --- |
| E-01 macOS 版本 | ✅ | ✖ | ✖ | ✖ | ✅ |
| E-03/E-04 CLT | ✅ | ✖ | ✖ | ✖ | ✅ |
| E-05/E-06 Homebrew | ✅ | ✖ | ✖ | ✖ | ✅ |
| E-07 Git | ✅ | ✅ | ✅ | ✅ | ✅ |
| E-08/E-09 Node/npm | ✅ | ✅（若已装） | ✅（若已装） | ✖ | ✅ |
| E-10 Python | ✅ | ✅（真实解释器） | ✅ | ✅ | ✅ |
| E-11 Java | ✅/SKIP | ✅/SKIP | ✅/SKIP | ✖ | ✅/SKIP |
| E-12/E-13 PATH | ✅ | ✅（语义不同） | ✅ | ✅ | ✅ |
| E-14 关键目录 | ✅ | ✖ | ✖ | ✖ | ✅ |
| E-15～E-18 工具路径 | ✅ | ✅ | ✅ | ✅ | ✅ |
| E-19 xcodebuild | ✅/SKIP | ✖ | ✖ | ✖ | ✅ |

说明：✅ = 结果可作为参考；✖ = 结果不可作为结论（仅用于验证脚本不崩溃）。

---

## 七、推荐工作流

1. **改脚本时**：Git Bash `bash -n` + 实跑，确认无语法错误、无 `set -u` 崩溃、编号齐全（C1/C2）。
2. **提交前**：Docker 或 WSL2 跑一次，确认 GNU 工具链下行为一致（C1/C2）。
3. **需要分支证据时**：Git Bash + stub 注入，确认 PASS 分支可达（C3）。
4. **验收时**：GitHub Actions `macos-14` 或真实 Mac 跑一次，以原生输出为准（C5）。
5. **留档**：保存完整输出与 `COPY BELOW` 摘要，按 C4 填写差异说明。

---

## 八、实测记录与交付物

| 项 | 内容 |
| --- | --- |
| 脚本 | `Test/verify_macos_dev_env.sh`（bash 3.2 兼容，19 项检查） |
| 本机语法检查 | Git Bash `bash -n` → 退出码 0 |
| 本机裸跑（Windows 真实环境） | `PASS=9 FAIL=8 SKIP=2`，退出码 1；FAIL 均为 macOS 专属项，符合预期 |
| stub 模拟（伪造 macOS 命令） | `PASS=17 FAIL=1 SKIP=1`，退出码 1；唯一 FAIL 为 E-14 平台路径差异 |
| 原生 macOS 实机 | **未执行**（本机为 Windows，无 Mac 硬件与云 Mac 凭据） |
| 结论 | 脚本语法、结构、分支、容错均已在 Windows 模拟环境验证；原生命令结果需按第五/六节在 macOS 或 CI 上确认 |

> 注意：本文所有“PASS”均为**脚本逻辑分支验证**，不代表 macOS 环境本身合格。
> macOS 环境是否合格，只以原生 macOS 上 `FAIL=0` 的输出为准。

# Windows 环境 FAIL 项修复指引

- 依据：`Test/verify_macos_dev_env.sh` 在 Windows 11 + Git for Windows 的实测记录
- 实测基线：裸跑 `PASS=9 FAIL=8 SKIP=2`（退出码 1）；全套 stub 模拟 `PASS=17 FAIL=1 SKIP=1`（仅 E-14 为平台路径语义）
- 适用系统：Windows 10（1809+）/ Windows 11，PowerShell 5.1 及以上
- 原则：**能在 Windows 真实修好的项必须修好；macOS 专属项不伪造 PASS，只用可落地替代方案取得可参考结论**

---

## 一、FAIL 项总览

| 编号 | 检查项 | 实测输出 | 失败类型 | 处理结论 |
| --- | --- | --- | --- | --- |
| E-01 | macOS 版本 | `MINGW64_NT-10.0-26300（非 Darwin）` | 平台专属 | 不可本地修复；平台感知降级 + 远程/CI 取证 |
| E-03 | `xcode-select` 路径 | `未设置` | 平台专属 | 不可本地修复；同上 |
| E-04 | Command Line Tools | `未检测到` | 平台专属 | 不可本地修复；同上 |
| E-05 | Homebrew 状态 | `未安装或不可执行` | 平台专属 | Windows 用 winget 替代；脚本项以 stub/远程验证 |
| E-06 | Homebrew bin 目录 | `未安装` | 平台专属 | 同上 |
| E-13 | PATH 条目质量 | `缺失 10，相对路径 3` | **可真实修复（Windows 侧）** | 清理 User + Machine 两级 PATH；脚本项受 Git Bash 注入限制，详见 F-01 |
| E-14 | 关键目录在 PATH | `缺少 /usr/local/bin /bin /usr/sbin /sbin` | 平台语义 | 不可伪造；stub 或远程验证 |
| E-16 | `brew` 工具路径 | `未找到` | 平台专属 | winget 替代 + stub 验证 |
| E-10 | Python3 版本（历史 FAIL，已降级 SKIP） | `0.0.0` / `解析失败` | **可真实修复** | 关闭 Store 别名 + 复用已有 Python（或装 3.12）+ 补 `python3.exe` |

> 说明：E-10 在第一轮裸跑中为 FAIL（输出 `0.0.0`），脚本随后改为“解析失败→SKIP”，但根因属于本机真实环境问题，仍需修复。
> E-14 在 stub 模拟中仍是唯一 FAIL，属平台路径语义差异，不是脚本缺陷。

---

## 二、根因分类

| 类别 | 涉及项 | 根因 |
| --- | --- | --- |
| R1 平台命令不存在 | E-01、E-03、E-04、E-19 | Windows 没有 `sw_vers`、`xcode-select`、`pkgutil`、Xcode；脚本按 macOS 基线判定 |
| R2 包管理器生态不同 | E-05、E-06、E-16 | Homebrew 官方不支持 Windows，`brew` 不可能出现在 Windows PATH |
| R3 环境变量污染 | E-13 | User 级存在失效目录与重复项；Machine 级存在空段、相对路径 `.`、拆分裂变 `%SystemRo` + `t%\system32`，且 `C:\Windows\System32` 本体缺失 |
| R4 路径语义差异 | E-14 | 脚本按 macOS 目录布局（`/usr/local/bin` 等）做字面匹配；Windows 使用 `C:\...` |
| R5 解释器别名劫持 | E-10 | `python3` 命中 `%LOCALAPPDATA%\Microsoft\WindowsApps\python3.exe`（应用执行别名占位程序，无真实输出） |

---

## 三、通用前置检查（一次性执行）

> 本节及后文所有命令默认在**项目根目录**执行，即 `c:\Users\22320\Desktop\实训\综合应用开发项目实训`（含 `Test` 子目录）。
> 若不是该目录，先执行 `Set-Location 'c:\Users\22320\Desktop\实训\综合应用开发项目实训'`。

在 PowerShell 5.1 中运行：

```powershell
# 1. 版本与权限
$PSVersionTable.PSVersion.ToString()
[Security.Principal.WindowsIdentity]::GetCurrent().Name
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# 2. 包管理器
winget --version

# 3. Git 与 Git Bash
git --version
Test-Path "C:\Program Files\Git\bin\bash.exe"

# 4. PATH 长度与条目数
$u = [Environment]::GetEnvironmentVariable('Path','User')
$m = [Environment]::GetEnvironmentVariable('Path','Machine')
"User 长度=$($u.Length) 条目=$((($u -split ';') | Where-Object { $_ }).Count)"
"Machine 长度=$($m.Length) 条目=$((($m -split ';') | Where-Object { $_ }).Count)"
```

- 预期：`5.1.x` 及以上；`winget` 有版本号；`git` 有版本；`Test-Path` 为 `True`。
- 若 `winget` 不存在：Windows 10 需从 https://github.com/microsoft/winget-cli/releases 下载 `Microsoft.DesktopAppInstaller_*.msixbundle` 安装，或改用 `choco` 手动安装包。
- 判定标准：以上 4 项均满足才继续；有缺失先按对应小节安装。

---

## 四、逐项修复指引

### F-01　E-13 PATH 条目质量（可真实修复）

**现象**：`[FAIL] E-13 PATH 条目质量 | 缺失 10，相对路径 3`

**根因**（本机 2026-11-09 实测）：

| 层级 | 实测异常 |
| --- | --- |
| User（814 字符） | 原始 24 段、空段 2 处、有效条目 22 条；失效 1 条：`...\Programs\Ollama`；重复 2 组：`DevEco Studio\bin`、`AppData\Roaming\npm`（清理后 19 条，已实测） |
| Machine（655 字符） | 原始 22 段、空段 1 处、有效条目 21 条；拆分裂变 2 段：`%SystemRo` 与 `t%\system32`（原应为 `%SystemRoot%\system32`）；失效 1 条：`...\Oracle\Java\javapath`；重复 2 组：`jdk-21\bin`、`AppData\Roaming\npm`；**且 `C:\Windows\System32` 本体缺失**（只剩 `C:\WINDOWS\System32\Wbem` 等子目录，清理后 17 条，已实测） |

> 关键前提：`[Environment]::SetEnvironmentVariable` 写入的是 **REG_SZ**（实测确认，不是 `REG_EXPAND_SZ`），
> 因此写回的条目**必须是已展开的绝对路径**；若写回 `%SystemRoot%\system32` 这类带 `%…%` 的字面量，
> 新进程的 PATH 将不会展开它，会直接导致 `cmd`/`where` 等系统命令找不到。下文脚本已按此修正。

**方案**：先清理用户级（普通权限），再清理系统级（管理员）。两侧都必须先备份；系统级只删空段、拆分裂变段、失效项与重复项，保留其余。

**前置检查（只读，已过滤空段）**

```powershell
function Show-PathEntry([string]$scope) {
  $v = [Environment]::GetEnvironmentVariable('Path', $scope)
  "== $scope 长度=$($v.Length) =="
  $v -split ';' | Where-Object { $_ } | ForEach-Object {
    $x = [Environment]::ExpandEnvironmentVariables($_)
    [pscustomobject]@{
      Entry   = $_
      Exists  = Test-Path -LiteralPath $x
      Relative= -not ($_ -match '^[A-Za-z]:\\' -or $_ -match '^%')
    }
  } | Format-Table -AutoSize
}
Show-PathEntry 'User'
Show-PathEntry 'Machine'
```

- 预期：出现 `Exists=False`、`Relative=True` 或重复条目；空段不再触发 `Test-Path` 报错。
- 判定标准：若所有条目 `Exists=True`、`Relative=False` 且无重复，说明该作用域已干净（结合步骤 F 的计数结果确认）。

**步骤 A　备份（必须，普通权限）**

```powershell
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$dir = "$env:USERPROFILE\Desktop\path-backup-$ts"
New-Item -ItemType Directory -Path $dir | Out-Null
[Environment]::GetEnvironmentVariable('Path','User')    | Set-Content "$dir\user-path.txt"    -Encoding UTF8
[Environment]::GetEnvironmentVariable('Path','Machine') | Set-Content "$dir\machine-path.txt" -Encoding UTF8
"备份目录：$dir"
```

- 预期：桌面出现 `path-backup-yyyyMMdd-HHmmss` 目录与 `user-path.txt`、`machine-path.txt`。

**步骤 B　清理用户级 PATH**

```powershell
$u = [Environment]::GetEnvironmentVariable('Path','User')
$seen = @{}
$kept = foreach ($e in ($u -split ';')) {
  if ([string]::IsNullOrWhiteSpace($e)) { continue }                   # 空段
  if ($e -notmatch '^[A-Za-z]:\\' -and $e -notmatch '^%') { continue } # 相对路径
  $x = [Environment]::ExpandEnvironmentVariables($e)
  if (-not (Test-Path -LiteralPath $x)) { continue }                   # 失效目录/坏变量
  $k = $x.TrimEnd('\').ToLower()
  if ($seen.ContainsKey($k)) { continue }                              # 重复
  $seen[$k] = $true
  $x.TrimEnd('\')                                                      # 写回已展开路径（REG_SZ 不回展开）
}
"保留 $($kept.Count) 条"
$kept
[Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
```

- 预期：本机实测从 22 条降到 19 条，列表中无 `...\Programs\Ollama`、无 `DevEco Studio\bin` 与 `npm` 重复项；写入命令无报错。
- 判定标准：`$kept` 中每条均满足“绝对路径 + 目录存在 + 不重复 + 不含 `%` 变量”。

**步骤 C　清理系统级 PATH（管理员 PowerShell）**

1. 以管理员身份打开 PowerShell：开始菜单搜索 “Windows PowerShell” → 右键 → 以管理员身份运行。
2. 先备份（若步骤 A 已在管理员会话执行可跳过）：确认 `machine-path.txt` 存在。
3. 预览清理（不写入）：
   ```powershell
   $m = [Environment]::GetEnvironmentVariable('Path','Machine')
   $parts = $m -split ';'
   # 删除拆分裂变的两段
   $parts = $parts | Where-Object { $_ -notmatch '^%SystemRo$' -and $_ -notmatch '^t%\\system32$' }
   # 精确判断 System32 本体是否存在（不能用子串匹配，C:\WINDOWS\System32\Wbem 会误判为已存在）
   $sys32 = [Environment]::ExpandEnvironmentVariables('%SystemRoot%\System32')
   $sys32Key = $sys32.TrimEnd('\').ToLower()
   $hasSys32 = $parts | Where-Object {
     ([Environment]::ExpandEnvironmentVariables($_).TrimEnd('\').ToLower()) -eq $sys32Key
   }
   "System32 本体存在：$([bool]$hasSys32)（目标 $sys32）"
   if (-not $hasSys32) { $parts = @($sys32) + $parts }
   $seen = @{}
   $clean = foreach ($e in $parts) {
     if ([string]::IsNullOrWhiteSpace($e)) { continue }
     if ($e -notmatch '^[A-Za-z]:\\' -and $e -notmatch '^%') { continue }
     $x = [Environment]::ExpandEnvironmentVariables($e)
     if (-not (Test-Path -LiteralPath $x)) { continue }
     $k = $x.TrimEnd('\').ToLower()
     if ($seen.ContainsKey($k)) { continue }
     $seen[$k] = $true
     $x.TrimEnd('\')                                                    # 写回已展开路径
   }
   "保留 $($clean.Count) 条，原 $((($m -split ';') | Where-Object { $_ }).Count) 条"
   $clean
   ```
   - 预期：本机实测 `System32 本体存在：False` → 自动补入 `C:\Windows\system32`；输出 17 条，无 `%SystemRo`、无 `t%\system32`、无重复、无失效 `Oracle\Java\javapath`。
   - **判定标准**：输出中不出现 `%SystemRo`、`t%\system32`、`Oracle\Java\javapath` 与重复项，且**明确包含 `C:\Windows\System32` 本体**（不只看 `...\System32\Wbem`）。
4. 确认无误后写入：
   ```powershell
   [Environment]::SetEnvironmentVariable('Path', ($clean -join ';'), 'Machine')
   ```
   - 预期：无报错。
   - **风险提示**：系统级 PATH 影响全局，务必先备份；若不确定，可只执行步骤 B，并在结果中记录“系统级遗留”。

**步骤 D　新开终端验证**

```powershell
# 必须新开终端，旧会话不会继承修改
$u = [Environment]::GetEnvironmentVariable('Path','User')
$m = [Environment]::GetEnvironmentVariable('Path','Machine')
"User=$($u.Length) Machine=$($m.Length)"
# 系统命令必须仍能找到（验证 System32 本体已回到 PATH）
where.exe cmd
where.exe where
# 工具命令
where.exe git
where.exe node
where.exe python
# 确认写回值不含未展开的 % 变量
[bool]($u -match '%')
[bool]($m -match '%')
```

- 预期：`where.exe cmd` 输出 `C:\Windows\System32\cmd.exe`；`git`、`node`、`python` 均能定位；最后两行为 `False`。
- **判定标准**：`cmd` 可解析、`False` 两行齐全、列表中无失效项，三者同时满足才算步骤 D 通过。

**步骤 E　重跑脚本（观察指标变化，不作为 PASS 判据）**

```powershell
& "C:\Program Files\Git\bin\bash.exe" ".\Test\verify_macos_dev_env.sh" 2>&1 | Select-String "E-12|E-13|E-14"
```

- **实测结论（本机）**：清理后 E-13 仍为 `[FAIL]`，但指标由 `空段 0，缺失 10，重复 0，相对路径 3`
  改善为 `空段 0，缺失 1，重复 2~5，相对路径 0`；E-14 仍为 FAIL（R4 平台语义，见 F-03）。
- **为什么 E-13 在 Git Bash 下无法归零**（实测最小 PATH 复现）：
  - `缺失 1` 恒为 `/c/Users/<用户>/bin`：MSYS 启动时自动把 `$HOME/bin` 加进 bash 的 PATH，该目录默认不存在；
  - `重复 2` 恒为 `/mingw64/bin` 与 `/usr/bin`：MSYS 注入的目录与 Windows PATH 转换后的条目重合；
  - 若 User 与 Machine 存在同名工具目录（如 `jdk-21\bin`、`Roaming\npm`），进程级 PATH 会再叠加 2 组重复。
  - 因此脚本 E-13 的最终判定**不具 Windows 代表性**，必须用步骤 F 的“分作用域判定”作为权威结论。
- **判定标准**：相对路径必须归零、缺失必须收敛到 1（MSYS 固有项）；否则回到步骤 B/C 定位残留。

**步骤 F　Windows 侧权威判定（分作用域，推荐作为验收证据）**

```powershell
function Test-PathScopeClean([string]$scope) {
  $v = [Environment]::GetEnvironmentVariable('Path', $scope)
  $raw = $v -split ';'
  $empty = ($raw | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count
  $rel = 0; $miss = 0; $dup = 0; $var = 0
  $seen = @{}
  foreach ($e in $raw) {
    if ([string]::IsNullOrWhiteSpace($e)) { continue }
    if ($e -notmatch '^[A-Za-z]:\\' -and $e -notmatch '^%') { $rel++; continue }
    if ($e -match '%') { $var++ }
    $x = [Environment]::ExpandEnvironmentVariables($e)
    if (-not (Test-Path -LiteralPath $x)) { $miss++; continue }
    $k = $x.TrimEnd('\').ToLower()
    if ($seen.ContainsKey($k)) { $dup++ } else { $seen[$k] = $true }
  }
  $bad = $empty + $rel + $miss + $dup
  $verdict = if ($bad -eq 0) { 'PASS' } else { 'FAIL' }
  [pscustomobject]@{ Scope=$scope; 空段=$empty; 相对路径=$rel; 缺失=$miss; 重复=$dup; 含变量=$var; 结果=$verdict }
}
Test-PathScopeClean 'User'
Test-PathScopeClean 'Machine'
```

- 修复前（本机实测）：`User 空段2/缺失1/重复2 → FAIL`，`Machine 空段1/相对1/缺失2/重复2/含变量1 → FAIL`。
- **预期结果**：修复后两个作用域均为 `结果 = PASS`（空段、相对路径、缺失、重复全部为 0）。
- **判定标准**：只有两行都为 `PASS` 才算 E-13 的 Windows 侧修复完成；
  若 `含变量 > 0`，说明仍有 `%…%` 条目未展开，需按步骤 B/C 重写为绝对路径。
- **回滚（User）**：
  ```powershell
  [Environment]::SetEnvironmentVariable('Path', (Get-Content "$env:USERPROFILE\Desktop\path-backup-<时间戳>\user-path.txt" -Raw).Trim(), 'User')
  ```
- **回滚（Machine，管理员）**：
  ```powershell
  [Environment]::SetEnvironmentVariable('Path', (Get-Content "$env:USERPROFILE\Desktop\path-backup-<时间戳>\machine-path.txt" -Raw).Trim(), 'Machine')
  ```

---

### F-02　E-10 Python3（可真实修复）

**现象**：第一轮 `[FAIL] E-10 Python3 版本 | 实际 0.0.0`；修正后为 `[SKIP] python3 存在但无法解析版本`。

**根因**（本机 2026-11-09 实测）：
- `where.exe python3` 只有一条：`...\Microsoft\WindowsApps\python3.exe`（应用执行别名占位程序），执行返回码 **9009**、无输出；
- `where.exe python` 有真实解释器：`D:\miniconda3\python.exe`，`python --version` = `Python 3.12.9`；
- 即：**系统里已有可用的 Python 3.12，缺的只是名为 `python3` 的可执行文件**。python.org 的 Windows 安装包只生成 `python.exe` 与 `py.exe`，**不会**生成 `python3.exe`；因此“装完 Python 就有 python3”是错误假设。

**方案**：关闭别名 → 复用已有 Python（或新装 3.12）→ 在该解释器同目录补一个 `python3.exe`。

**前置检查**

```powershell
where.exe python3
where.exe python
python --version
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WindowsApps" -Filter "python*" -ErrorAction SilentlyContinue | Select-Object Name, Length
```

- 预期：`python3` 指向 `WindowsApps` 且体积为 0–2 KB（占位程序）；`python` 能解析到真实解释器并输出版本。
- 判定：若 `python --version` ≥ 3.10，走方案 A；否则走方案 B。

**步骤**

1. 关闭别名（图形界面，Win10/11 通用）：
   - Win11：设置 → 应用 → 高级应用设置 → 应用执行别名 → 关闭 `python.exe`、`python3.exe`；
   - Win10：设置 → 应用 → 应用和功能 → 应用执行别名 → 关闭同名项。
   - 预期：列表中两项状态变为“关闭”。
2. 准备真实 Python（二选一）：
   - **方案 A（已有 Python ≥ 3.10，推荐）**：无需安装，直接用 `where.exe python` 给出的目录，例如 `D:\miniconda3`。
   - **方案 B（无可用 Python）**：
     ```powershell
     winget install -e --id Python.Python.3.12 --source winget
     ```
     预期：`Successfully installed`；若 winget 不可用，从 https://www.python.org/downloads/windows/ 下载 3.12.x，勾选 “Add python.exe to PATH”。
3. 补 `python3.exe`（在所选 Python 目录内复制，保持 DLL 同目录）：
   ```powershell
   $pyDir = Split-Path (where.exe python | Select-Object -First 1)
   Copy-Item -LiteralPath "$pyDir\python.exe" -Destination "$pyDir\python3.exe" -Force
   Test-Path -LiteralPath "$pyDir\python3.exe"
   ```
   预期：`True`。该操作是新增文件，不改动原 `python.exe`，删除 `python3.exe` 即可回滚。
4. **新开**终端后验证（顺序很关键，别名未关闭时 WindowsApps 会先命中）：
   ```powershell
   where.exe python3
   python3 --version
   python3 -c "import sys; print(sys.executable)"
   ```
   预期：首行不再是 `WindowsApps`，而是所选目录（如 `D:\miniconda3\python3.exe`）；版本 `Python 3.12.x`。
5. 重跑脚本：
   ```powershell
   & "C:\Program Files\Git\bin\bash.exe" ".\Test\verify_macos_dev_env.sh" 2>&1 | Select-String "E-10"
   ```

- **预期结果**：`[PASS] E-10 Python3 版本 | 期望 >= 3.10 | 实际 3.12.x`。
- **判定标准**：`python3 --version` ≥ 3.10 且退出码 0，同时脚本 E-10 为 PASS；三者缺一不算修复。
- **回滚**：删除新增文件 `Remove-Item "$pyDir\python3.exe"`；若走了方案 B，可 `winget uninstall Python.Python.3.12`；需要时重新打开别名。若曾手动改 PATH，按 F-01 备份恢复。

---

### F-03　E-14 关键目录在 PATH（不可伪造，给替代验证）

**现象**：`[FAIL] E-14 | 缺少 /usr/local/bin /bin /usr/sbin /sbin`

**根因**：脚本按 macOS 目录布局做字面匹配；Windows 不存在这些 Unix 路径。**不得**在 Windows 系统 PATH 中伪造这些路径，否则会污染环境且仍无法代表 macOS。

**替代方案 A（推荐，零成本）**：stub 逻辑验证（只证明脚本分支正确，不代表环境合格）。

```bash
# 在 Git Bash 中执行，仅当前会话生效
mkdir -p /tmp/mock/bin
printf '#!/bin/sh\ncase "$1" in -s) echo Darwin;; -m) echo arm64;; *) echo Darwin;; esac\n' > /tmp/mock/bin/uname
printf '#!/bin/sh\ncase "$1" in -productVersion) echo 14.5;; *) echo 14.5;; esac\n' > /tmp/mock/bin/sw_vers
chmod +x /tmp/mock/bin/*
PATH="/tmp/mock/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash ./Test/verify_macos_dev_env.sh
```

- 本机实测：`[PASS] E-01 macOS 版本 | 实际 14.5`、`[PASS] E-14 关键目录在 PATH | 全部存在`；
  由于该 `PATH` 只含 Unix 目录，Git/Node/Java 等 Windows 工具会被隔离，E-07～E-18 出现大量 FAIL 属预期。
- 判定标准：仅可证明“E-01/E-14 的逻辑分支可控”；**不得**据此宣称 macOS 环境合格，也不得把本次 FAIL 数当作环境结论。

**替代方案 B（要真实结论）**：GitHub Actions `macos-14` 或远程 Mac，见第六节。

- **判定标准**：远程环境中 `FAIL=0` 且 E-14 为 PASS，才算该项闭环。

---

### F-04　E-05 / E-06 / E-16 Homebrew（Windows 替代为 winget）

**现象**：`Homebrew 未安装或不可执行`、`brew 未找到`。

**根因**：Homebrew 官方仅支持 macOS/Linux；Windows 无原生实现。

**方案**：Windows 用 winget 管理同类工具，脚本中 Homebrew 相关项以“平台不适用”记录；需要脚本层不报错时用 stub。

**前置检查**

```powershell
winget --version
winget source list
```

**步骤**

1. 安装项目实际需要的工具（替代 brew 的职责）：
   ```powershell
   winget install -e --id Git.Git --source winget
   winget install -e --id OpenJS.NodeJS.LTS --source winget
   winget install -e --id Python.Python.3.12 --source winget
   winget install -e --id Microsoft.OpenJDK.17 --source winget
   ```
   预期：每条输出 `Successfully installed` 或以“已安装”结束。
2. 验证：
   ```powershell
   winget list --id Git.Git
   winget list --id OpenJS.NodeJS.LTS
   git --version
   node --version
   npm --version
   java -version
   ```
   预期：全部返回版本号。
3. 脚本层如需消音，只对 E-05/E-06/E-16 套用第五节的平台感知降级；**不要**伪造 `brew` 可执行文件：
   E-06 还要求 `brew --prefix` 指向真实存在的目录，伪 `brew` 只会制造新的假 PASS。

- **预期结果**：Windows 侧工具齐备；脚本 E-05/E-06/E-16 在 Windows 仍为 FAIL/SKIP，属 R2，已记录。
- **判定标准**：`winget list` 能查到对应包且命令可执行；macOS 的 Homebrew 结论只能由远程/原生环境给出。
- **不建议**：WSL2 内装 Linuxbrew 后宣称“Homebrew 已通过”，两者包格式与路径不同，不可作为 macOS 结论。

---

### F-05　E-01 macOS 版本（平台专属）

**现象**：`实际 MINGW64_NT-10.0-26300（非 Darwin）`

**根因**：`uname` 在 Git Bash 返回 MSYS 内核标识，Windows 没有 `sw_vers`。

**方案**：Windows 上做“平台感知降级”（可选脚本补丁，见第五节），把 E-01 改为 `[SKIP] 平台不适用`，并补充 Windows 等价检查。

**前置检查**：无需，Windows 信息可直接读取。

**步骤（验证本机 Windows 版本，作为对照记录）**

```powershell
$os = Get-CimInstance Win32_OperatingSystem
[pscustomobject]@{
  Caption = $os.Caption
  Version = $os.Version
  Build   = $os.BuildNumber
  Arch    = $env:PROCESSOR_ARCHITECTURE
} | Format-List
```

- 预期：本机实测 `Microsoft Windows 11 家庭版 中文版`、`10.0.26300`、`AMD64`（版本号与 SKU 以实际为准）。
- **判定标准**：能输出 Windows 版本与架构即完成“对照记录”；macOS 版本判定必须到远程/原生环境执行。
- **回滚**：不涉及修改。

---

### F-06　E-03 / E-04 Command Line Tools（平台专属）

**现象**：`xcode-select 未设置`、`Command Line Tools 未检测到`

**根因**：Windows 没有 Xcode 与 `xcode-select`；`pkgutil` 也不存在。

**方案**：Windows 若确实需要 C/C++ 工具链，安装 Visual Studio Build Tools（与 macOS CLT 职责相近，但不能替代 Xcode 结论）。

**前置检查**

```powershell
Get-Command cl.exe -ErrorAction SilentlyContinue
Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
```

- 预期：本机当前为 `cl` 未找到、`vswhere.exe` 为 `False`（`vswin.exe` 不是安装器自带文件，不要用它判断）。

**步骤**

```powershell
winget install -e --id Microsoft.VisualStudio.2022.BuildTools --source winget --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

- 预期：安装完成；`cl.exe` 可通过 “x64 Native Tools Command Prompt” 调用。
- **判定标准**：Windows 侧 C 工具链可用；E-03/E-04 仍为平台差异，必须在 macOS 上判定。
- **回滚**：`winget uninstall Microsoft.VisualStudio.2022.BuildTools`。

---

### F-07　E-19 xcodebuild（SKIP，无 FAIL）

**现象**：`[SKIP] 未安装 Xcode`。

**处理**：Windows 不可安装 Xcode，保持 SKIP；原生测试通过 GitHub Actions `macos-14` 执行第六节的 `xcodebuild test`。

---

## 五、脚本平台感知（可选增强）

若希望 Windows 本地不再出现“必然 FAIL”的噪声，可在脚本开头加入平台分支（不改动任何检查逻辑，只改判定标签）：

```bash
# 放在 set -u 之后
HOST_OS="$(uname -s 2>/dev/null || echo unknown)"

# E-01 处改为：
if [ "$HOST_OS" != "Darwin" ]; then
  skip 'E-01 macOS 版本' "当前平台 $HOST_OS 不适用；Windows 对照见《Windows-FAIL修复指引》"
else
  # 原 macOS 判定逻辑
fi
```

- 预期：Windows 下 E-01/E-03/E-04/E-05/E-06/E-19 变 `[SKIP]`，E-07～E-18 照常判定。
  （上面的代码只演示 E-01 一处；E-03、E-04、E-05、E-06、E-19 需各自套用同一 `if [ "$HOST_OS" != "Darwin" ]` 模式。）
- **判定标准**：SKIP 项均有“平台不适用”说明，不出现“伪造 PASS”。
- 注意：此补丁会改变交付脚本的 macOS 基线行为，需在原生 macOS 回归一次（`FAIL=0`）后再提交。

---

## 六、取得真实 macOS 结论的替代路径（Windows 本地可操作）

### 6.1 GitHub Actions（推荐，无需 Mac）

**前置检查**

```powershell
winget --version
git --version
winget list --id GitHub.cli
```

**步骤**

1. 安装 GitHub CLI：
   ```powershell
   winget install -e --id GitHub.cli --source winget
   gh --version
   ```
2. 登录并按提示完成浏览器授权：
   ```powershell
   gh auth login
   gh auth status
   ```
3. 在仓库中添加工作流 `.github/workflows/macos-env-check.yml`：
   ```yaml
   name: macos-env-check
   on: [workflow_dispatch]
   jobs:
     verify:
       runs-on: macos-14
       steps:
         - uses: actions/checkout@v4
         - run: chmod +x Test/verify_macos_dev_env.sh
         - run: bash Test/verify_macos_dev_env.sh
   ```
4. 推送并触发：
   ```powershell
   git add .github/workflows/macos-env-check.yml
   git commit -m "ci: add macOS env verification"
   git push
   gh workflow run macos-env-check
   gh run watch
   ```
5. 查看日志：
   ```powershell
   gh run view --log | Select-String "E-01|E-14|验证结果"
   ```

- **预期结果**：日志中 `E-01`、`E-03`、`E-14` 为 `[PASS]`，末尾 `PASS=n FAIL=0`。
- **判定标准**：`FAIL=0` 且 `VERDICT=PASS`；下载日志与 `COPY BELOW` 摘要归档。
- **注意**：runner 镜像的 Homebrew/Node/Java 版本随镜像变化，基线版本号可能需同步更新；本项目的 Git 提交按既定约束执行，是否推送由项目负责人决定。

### 6.2 远程 Mac / 云 Mac

```powershell
# PowerShell 5.1 不支持 "<" 文件重定向，必须用管道
Get-Content -LiteralPath ".\Test\verify_macos_dev_env.sh" -Raw | ssh user@mac-host "bash -s"
```

- 预期：远端直接输出验证结果；`FAIL=0` 即环境合格。
- 判定标准：远端输出与本地脚本为同一文件（可先比对 SHA256）。
- 前置：Remote Mac 需开启“远程登录”，Windows 端 `ssh` 由 Git for Windows 或系统 OpenSSH 提供（`Test-Path "$env:WINDIR\System32\OpenSSH\ssh.exe"`）。

---

## 七、全量复验流程

1. 完成 F-01、F-02（Windows 真实可修项）。
2. 执行 F-04 的 winget 安装（Windows 工具齐备）。
3. 新开终端，运行：
   ```powershell
   & "C:\Program Files\Git\bin\bash.exe" ".\Test\verify_macos_dev_env.sh" 2>&1 | Tee-Object -FilePath ".\windows-env-check.txt"
   ```
4. 对照判定：
   | 项目 | 判定 |
   | --- | --- |
   | E-07～E-09、E-11、E-12、E-15、E-17、E-18 | 应全部 `[PASS]` |
   | E-13 | 脚本仍为 `[FAIL]`（Git Bash 注入所致，缺失收敛为 1、相对路径为 0）；Windows 侧以 F-01 步骤 F 两作用域 `PASS` 为验收 |
   | E-01/E-03/E-04/E-05/E-06/E-16/E-19 | Windows 下允许 `[FAIL]/[SKIP]`，但必须归入 R1/R2 |
   | E-14 | Windows 下允许 FAIL，归入 R4 |
   | 退出码 | Windows 允许为 1；不得通过改脚本伪造 0 |
5. 将 `windows-env-check.txt` 与远程/CI 的 `macos-env-check` 日志一并归档，作为“平台差异 + 原生合格”的双证据。

---

## 八、常见问题

| 问题 | 原因 | 处理 |
| --- | --- | --- |
| `winget` 不存在 | Win10 未装 App Installer | 安装 `Microsoft.DesktopAppInstaller` msixbundle，或用 choco/官网安装包 |
| 修改 PATH 后命令消失 | 误删了 `C:\Windows\System32` 等必要目录 | 用 F-01 备份恢复；系统级 PATH 不要手工编辑 |
| `SetEnvironmentVariable` 后当前窗口无效 | 环境变量只对新进程生效 | 关闭并新开终端验证 |
| `python3` 仍指向 WindowsApps | 别名未关闭或 PATH 顺序未变 | 关闭“应用执行别名”，`where.exe python3` 复核 |
| 用户 PATH 超过长度限制 | 注册表值过长 | 合并重复项；必要时把稳定工具移到系统级 PATH（需管理员并先备份） |
| Git Bash 输出乱码 | 控制台编码 | `chcp 65001` 或输出到文件用 UTF-8 查看 |
| 误以为 stub 结果等于环境合格 | 概念混淆 | stub 只验证脚本逻辑；结论以第六节 `FAIL=0` 为准 |
| 清理后 E-13 仍 `[FAIL]` | Git Bash/MSYS 自动注入 `/usr/bin`、`$HOME/bin`，并叠加跨作用域重复 | 属平台固有，不可消除；以 F-01 步骤 F 的分作用域 `PASS` 作为 Windows 侧验收 |
| 写回 PATH 后系统命令找不到 | 用 `%SystemRoot%\system32` 字面量写入，但 `SetEnvironmentVariable` 存为 REG_SZ 不展开 | 必须写已展开的 `C:\Windows\System32`（F-01 步骤 C 已处理） |

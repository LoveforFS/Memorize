#!/bin/bash
# =============================================================================
# Memorize 原生验收执行器（macOS）
# 对应任务：P0-1 原生编译与全量测试 + P1-1 证据采集
#
# 作用：一条命令完成"环境前置检查 -> xcodebuild -list -> 全量 xcodebuild test
#       (132 条) -> 结果解析 -> 证据文件生成"，产物可直接粘贴进 P1-1 的 4 个锚点。
#
# 用法：
#   bash run_native_acceptance.sh                      # 默认使用 ../../day8
#   bash run_native_acceptance.sh /path/to/day8        # 指定工程根
#   DEVICE_NAME="iPhone 15 Pro" bash run_native_acceptance.sh
#   bash run_native_acceptance.sh --selftest           # 只自检解析逻辑，无需 Xcode
#
# 退出码：0 = 132/132 且 0 失败 0 跳过；1 = 判定未通过；2 = 环境前置不满足
#
# 设计约束（与项目提示词一致）：
#   - 只读解析，不制造、不修饰任何结果；判定以 xcodebuild 实际输出为准。
#   - 本脚本不修改 App 源码、不改测试、不动 day8 目录内任何文件。
#   - 所有产物写入 Test/native_acceptance/evidence/<时间戳>/，不污染 day8。
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELFTEST=0
ROOT_ARG=""

for a in "$@"; do
  case "$a" in
    --selftest) SELFTEST=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) ROOT_ARG="$a" ;;
  esac
done

# ---------------------------------------------------------------------------
# 日志结果解析：从 xcodebuild 输出中提取总用例数 / 失败数 / 跳过数
# 输入：日志文件路径；输出：total|failures|skipped|bundleCount
# 说明：xcodebuild 会为每个嵌套 suite 打印 Executed 行，因此不能简单累加；
#       按 MemorizeTests.xctest / MemorizeUITests.xctest 两个 bundle 分别取最大值。
# ---------------------------------------------------------------------------
parse_log() {
  awk '
    BEGIN { u=0; uf=0; ui=0; uif=0; alln=0; allf=0; alls=0; cur="" }
    /Test Suite '\''/ {
      if ($0 ~ /MemorizeUITests\.xctest/) { cur="ui" }
      else if ($0 ~ /MemorizeTests\.xctest/) { cur="unit" }
    }
    /Executed [0-9]+ tests?, with/ {
      n=""; f=""; s=0
      if (match($0, /Executed [0-9]+ tests?/)) {
        t=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",t); n=t+0
      }
      if (match($0, /with [0-9]+ tests? skipped/)) {
        t=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",t); s=t+0
      }
      if (match($0, /[0-9]+ failures?/)) {
        t=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",t); f=t+0
      }
      if (n != "") {
        alln=n; allf=f
        if (s > alls) { alls=s }
        if (cur=="unit" && n>u) { u=n; uf=f }
        if (cur=="ui"   && n>ui){ ui=n; uif=f }
      }
    }
    END {
      if (u+ui > 0) {
        cnt=0; if (u>0) cnt++; if (ui>0) cnt++
        printf "%d|%d|%d|%d\n", u+ui, uf+uif, alls, cnt
      } else {
        printf "%d|%d|%d|0\n", alln, allf, alls
      }
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# 自检：用内置样例日志验证解析逻辑（Windows 侧亦可通过）
# ---------------------------------------------------------------------------
run_selftest() {
  TMPD="$(mktemp -d 2>/dev/null || echo "/tmp/memorize-selftest-$$")"
  mkdir -p "$TMPD"
  cat > "$TMPD/pass.log" <<'EOF'
Test Suite 'GameModelTests' passed at 2026-11-10 10:00:00.000.
	 Executed 28 tests, with 0 failures (0 unexpected) in 0.120 (0.130) seconds
Test Suite 'MemorizeTests.xctest' passed at 2026-11-10 10:00:05.000.
	 Executed 124 tests, with 0 failures (0 unexpected) in 1.200 (1.300) seconds
Test Suite 'All tests' passed at 2026-11-10 10:00:05.100.
	 Executed 124 tests, with 0 failures (0 unexpected) in 1.200 (1.300) seconds
Test Suite 'GameFlowUITests' passed at 2026-11-10 10:01:00.000.
	 Executed 5 tests, with 0 failures (0 unexpected) in 20.000 (20.100) seconds
Test Suite 'MemorizeUITests.xctest' passed at 2026-11-10 10:01:30.000.
	 Executed 8 tests, with 0 failures (0 unexpected) in 30.000 (30.100) seconds
Test Suite 'All tests' passed at 2026-11-10 10:01:30.100.
	 Executed 8 tests, with 0 failures (0 unexpected) in 30.000 (30.100) seconds
** TEST SUCCEEDED **
EOF
  cat > "$TMPD/fail.log" <<'EOF'
Test Suite 'MemorizeTests.xctest' failed at 2026-11-10 10:00:05.000.
	 Executed 124 tests, with 1 failure (0 unexpected) in 1.200 (1.300) seconds
Test Suite 'MemorizeUITests.xctest' passed at 2026-11-10 10:01:30.000.
	 Executed 8 tests, with 0 failures (0 unexpected) in 30.000 (30.100) seconds
** TEST FAILED **
EOF
  cat > "$TMPD/skip.log" <<'EOF'
Test Suite 'MemorizeTests.xctest' passed at 2026-11-10 10:00:05.000.
	 Executed 124 tests, with 3 tests skipped and 0 failures (0 unexpected) in 1.200 (1.300) seconds
Test Suite 'MemorizeUITests.xctest' passed at 2026-11-10 10:01:30.000.
	 Executed 8 tests, with 0 failures (0 unexpected) in 30.000 (30.100) seconds
** TEST SUCCEEDED **
EOF
  FAILN=0
  check() { # $1=name $2=actual $3=expected
    if [ "$2" = "$3" ]; then printf '[OK]   %s -> %s\n' "$1" "$2"
    else printf '[FAIL] %s -> 期望 %s，实际 %s\n' "$1" "$3" "$2"; FAILN=$((FAILN+1)); fi
  }
  check "通过样例 132/0/0/2" "$(parse_log "$TMPD/pass.log")" "132|0|0|2"
  check "失败样例 132/1/0/2" "$(parse_log "$TMPD/fail.log")" "132|1|0|2"
  check "跳过样例 132/0/3/2" "$(parse_log "$TMPD/skip.log")" "132|0|3|2"
  rm -rf "$TMPD" 2>/dev/null || true
  echo "------------------------------------------------------------"
  if [ "$FAILN" -eq 0 ]; then echo "自检结论：解析逻辑 PASS（3/3）"; exit 0; fi
  echo "自检结论：解析逻辑 FAIL（$FAILN 项）"; exit 1
}

if [ "$SELFTEST" -eq 1 ]; then
  echo "==== 解析逻辑自检（不需要 Xcode，可在任意平台运行）===="
  run_selftest
fi

# ---------------------------------------------------------------------------
# 项目根定位
# ---------------------------------------------------------------------------
if [ -n "$ROOT_ARG" ]; then
  ROOT="$ROOT_ARG"
else
  # 自动探测：脚本可能在 Test/native_acceptance/、Test/ 或交付包根目录下被调用
  ROOT=""
  for c in "$SCRIPT_DIR/../../day8" "$SCRIPT_DIR/../day8" "$SCRIPT_DIR/.." "."; do
    if [ -d "$c/Memorize.xcodeproj" ]; then ROOT="$c"; break; fi
  done
fi
ROOT="$(cd "$ROOT" 2>/dev/null && pwd || echo "")"

if [ -z "$ROOT" ] || [ ! -d "$ROOT/Memorize.xcodeproj" ]; then
  echo "[FAIL] 未找到 Memorize.xcodeproj，请传入 day8 或交付包根目录"
  echo "       当前解析：${ROOT:-<空>}"
  exit 2
fi

TS="$(date +%Y%m%d-%H%M%S)"
EVID="$SCRIPT_DIR/evidence/$TS"
LOG="$EVID/xcodebuild-test.log"
LISTLOG="$EVID/xcodebuild-list.log"
XCRESULT="$EVID/TestResults.xcresult"
EVIDMD="$EVID/native-evidence.md"
DEVICE_NAME="${DEVICE_NAME:-iPhone 15}"

echo "============================================================"
echo "Memorize 原生验收"
echo "工程根：$ROOT"
echo "证据目录：$EVID"
echo "设备：$DEVICE_NAME"
echo "============================================================"

# ---------------------------------------------------------------------------
# 1. 环境前置（只读）
# ---------------------------------------------------------------------------
PREFAIL=0
need() { if eval "$2" >/dev/null 2>&1; then printf '[OK]   %s\n' "$1"; else printf '[FAIL] %s\n' "$1"; PREFAIL=$((PREFAIL+1)); fi; }

need "xcodebuild 可用" "command -v xcodebuild"
need "xcrun 可用" "command -v xcrun"
need "xcode-select 指向 Xcode.app" "xcode-select -p | grep -q 'Xcode.*\.app/Contents/Developer'"
OS_VER="$(sw_vers -productVersion 2>/dev/null || echo 0.0)"
XC_VER="$(xcodebuild -version 2>/dev/null | head -1 || echo 'Xcode 未知')"
case "$XC_VER" in Xcode*) ;; *) XC_VER="Xcode 未知" ;; esac
SWIFT_VER="$(swift --version 2>/dev/null | head -1 | sed -n 's/.*Swift version \([0-9.]*\).*/\1/p')"
SDK_VER="$(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || echo 未知)"
echo "       macOS $OS_VER | $XC_VER | Swift ${SWIFT_VER:-未知} | iOS SDK $SDK_VER"

if [ "$PREFAIL" -gt 0 ]; then
  echo "------------------------------------------------------------"
  echo "前置检查未通过（$PREFAIL 项），未执行测试。"
  echo "请先按 Test/macOS-开发环境搭建指南.md 或 verify_macos_dev_env.sh 修复。"
  exit 2
fi
mkdir -p "$EVID"

# 设备解析：默认 iPhone 15，缺失则自动回退到任意可用 iPhone
if ! xcrun simctl list devices available 2>/dev/null | grep -q "$DEVICE_NAME ("; then
  FALLBACK="$(xcrun simctl list devices available 2>/dev/null | grep -m1 -o 'iPhone [0-9A-Za-z ]*(' | sed 's/($//;s/[[:space:]]*$//')"
  if [ -n "${FALLBACK:-}" ]; then
    echo "[WARN] 未找到「$DEVICE_NAME」，自动改用「${FALLBACK% (}」"
    DEVICE_NAME="$(printf '%s' "$FALLBACK" | sed 's/[[:space:]]*($//')"
  else
    echo "[FAIL] 无可用 iPhone 模拟器，请先 xcodebuild -downloadPlatform iOS"
    exit 2
  fi
fi

# ---------------------------------------------------------------------------
# 2. 工程自检：xcodebuild -list
# ---------------------------------------------------------------------------
echo "------------------------------------------------------------"
echo "[1/3] xcodebuild -list"
xcodebuild -list -project "$ROOT/Memorize.xcodeproj" > "$LISTLOG" 2>&1
LIST_RC=$?
if [ "$LIST_RC" -ne 0 ]; then
  echo "[FAIL] xcodebuild -list 失败，详见 $LISTLOG"
  sed -n '1,20p' "$LISTLOG"
  exit 2
fi
T_OK=0; T_UNIT=0; T_UI=0; T_SCHEME=0
grep -qE '^[[:space:]]+Memorize$' "$LISTLOG" && T_OK=1
grep -q 'MemorizeTests' "$LISTLOG" && T_UNIT=1
grep -q 'MemorizeUITests' "$LISTLOG" && T_UI=1
grep -q 'Memorize' "$LISTLOG" && T_SCHEME=1
printf '[%s] Target Memorize\n' "$([ $T_OK -eq 1 ] && echo OK || echo FAIL)"
printf '[%s] Target MemorizeTests\n' "$([ $T_UNIT -eq 1 ] && echo OK || echo FAIL)"
printf '[%s] Target MemorizeUITests\n' "$([ $T_UI -eq 1 ] && echo OK || echo FAIL)"
printf '[%s] Scheme Memorize\n' "$([ $T_SCHEME -eq 1 ] && echo OK || echo FAIL)"

# ---------------------------------------------------------------------------
# 3. 全量测试（UI 测试较慢，整体预留 20 分钟）
# ---------------------------------------------------------------------------
echo "------------------------------------------------------------"
echo "[2/3] xcodebuild test（132 条，UI 用例耗时较长，请勿中断）"
DD="${TMPDIR:-/tmp}/memorize-derived-$TS"
set -o pipefail
START_EPOCH=$(date +%s)
xcodebuild test \
  -project "$ROOT/Memorize.xcodeproj" \
  -scheme Memorize \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -resultBundlePath "$XCRESULT" \
  -derivedDataPath "$DD" 2>&1 | tee "$LOG"
TEST_RC=$?
END_EPOCH=$(date +%s)
DURATION=$((END_EPOCH - START_EPOCH))

PARSED="$(parse_log "$LOG")"
# 摘录两个测试 bundle 各自的汇总行原文（不能取最后一行：末尾是 UI bundle 的 8 条）
RAW_SUMMARY="$(awk '
  BEGIN { u=0; ui=0; lu=""; lui=""; last="" }
  /Test Suite '\''/ {
    if ($0 ~ /MemorizeUITests\.xctest/) cur="ui"
    else if ($0 ~ /MemorizeTests\.xctest/) cur="unit"
  }
  /Executed [0-9]+ tests?, with/ {
    line=$0; gsub(/^[[:space:]]+/,"",line)
    if (match($0, /Executed [0-9]+ tests?/)) {
      t=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",t); n=t+0
      if (cur=="unit" && n>u) { u=n; lu=line }
      if (cur=="ui"   && n>ui){ ui=n; lui=line }
      last=line
    }
  }
  END {
    if (u>0 || ui>0) {
      out=""
      if (u>0)  out = "MemorizeTests: " lu
      if (ui>0) out = (out=="" ? "" : out " | ") "MemorizeUITests: " lui
      print out
    } else if (last != "") { print last }
  }
' "$LOG" 2>/dev/null)"
RAW_SUMMARY="${RAW_SUMMARY:-未在日志中找到 Executed 汇总行}"
TOTAL="$(printf '%s' "$PARSED" | cut -d'|' -f1)"
FAILS="$(printf '%s' "$PARSED" | cut -d'|' -f2)"
SKIPS="$(printf '%s' "$PARSED" | cut -d'|' -f3)"
BUNDLES="$(printf '%s' "$PARSED" | cut -d'|' -f4)"

if grep -q '\*\* TEST FAILED \*\*' "$LOG"; then STATUS="TEST FAILED"
elif grep -q '\*\* TEST SUCCEEDED \*\*' "$LOG"; then STATUS="TEST SUCCEEDED"
else STATUS="未识别（退出码 $TEST_RC）"; fi

echo "------------------------------------------------------------"
echo "[3/3] 结果解析"
echo "  汇总行：Executed $TOTAL tests, with $FAILS failures, $SKIPS skipped"
echo "  状态标记：$STATUS（xcodebuild 退出码 $TEST_RC，耗时 ${DURATION}s）"
echo "  识别到 $BUNDLES 个测试 bundle"

VERDICT="未通过"
VERDICT_LABEL="未通过"
if [ "$TOTAL" = "132" ] && [ "$FAILS" = "0" ] && [ "$SKIPS" = "0" ] \
   && [ "$STATUS" = "TEST SUCCEEDED" ] && [ "$TEST_RC" -eq 0 ]; then
  VERDICT="通过"
  VERDICT_LABEL="已完成"
fi
echo "  判定：$VERDICT"

# ---------------------------------------------------------------------------
# 4. 生成证据文件（可直接粘贴到 P1-1 的 4 个锚点）
# ---------------------------------------------------------------------------
HW_MODEL="$(sysctl -n hw.model 2>/dev/null || echo 未知)"
if command -v shasum >/dev/null 2>&1; then
  LOG_SHA="$(shasum -a 256 "$LOG" 2>/dev/null | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  LOG_SHA="$(sha256sum "$LOG" 2>/dev/null | awk '{print $1}')"
else
  LOG_SHA=""
fi
cat > "$EVIDMD" <<EOF
# 原生验收证据（自动生成，勿手改数字）

> 生成方式：bash Test/native_acceptance/run_native_acceptance.sh
> 采集时间：$(date '+%Y-%m-%d %H:%M:%S %Z')
> 说明：以下数据全部来自本次 xcodebuild 实际输出；若判定为"未通过"，不得作为通过证据使用。

## 一、执行环境

| 项 | 值 |
| --- | --- |
| 主机 | $HW_MODEL |
| macOS | $OS_VER |
| Xcode | $XC_VER |
| Swift | ${SWIFT_VER:-未知} |
| iOS Simulator SDK | $SDK_VER |
| 模拟器设备 | $DEVICE_NAME |

## 二、工程自检

- 命令：\`xcodebuild -list -project Memorize.xcodeproj\`
- 结果：Target Memorize=$( [ $T_OK -eq 1 ] && echo 识别 || echo 缺失 )、MemorizeTests=$( [ $T_UNIT -eq 1 ] && echo 识别 || echo 缺失 )、MemorizeUITests=$( [ $T_UI -eq 1 ] && echo 识别 || echo 缺失 )、Scheme Memorize=$( [ $T_SCHEME -eq 1 ] && echo 识别 || echo 缺失 )
- 原始输出：\`$(basename "$LISTLOG")\`

## 三、全量测试

- 命令：
  \`\`\`
  xcodebuild test -project Memorize.xcodeproj -scheme Memorize -destination 'platform=iOS Simulator,name=$DEVICE_NAME' -resultBundlePath ./TestResults.xcresult
  \`\`\`
- 终端摘要（日志原文，按 bundle 摘录）：\`$RAW_SUMMARY\`
- 解析结果：总计 \`$TOTAL\` 条 / 失败 \`$FAILS\` / 跳过 \`$SKIPS\` / 识别 bundle \`$BUNDLES\` 个
- 状态标记：\`$STATUS\`
- 退出码：\`$TEST_RC\`；耗时：\`${DURATION}s\`
- 判定：**$VERDICT**（132 / 0 / 0 / TEST SUCCEEDED / 退出码 0）

## 四、归档路径

| 产物 | 路径 | 备注 |
| --- | --- | --- |
| 测试日志 | \`$LOG\` | 完整 xcodebuild 输出 |
| 日志 SHA256 | \`${LOG_SHA:-未计算}\` | 用于证明证据文件未被替换 |
| 结果包 | \`$XCRESULT\` | 用 Xcode 打开可逐条查看 |
| 工程自检日志 | \`$LISTLOG\` | |
| DerivedData | \`$DD\` | 临时目录，无需归档 |

## 五、回填片段（复制即用）

**A. day8/README.md §5.2 末尾追加：**
\`\`\`markdown
**原生执行记录（$(date '+%Y-%m-%d')）**：在 $HW_MODEL（macOS $OS_VER / $XC_VER）的 $DEVICE_NAME 模拟器上执行上条命令，
合计 $TOTAL 条（失败 $FAILS / 跳过 $SKIPS），\`$STATUS\`，退出码 $TEST_RC，耗时 ${DURATION}s。
日志原文：\`$RAW_SUMMARY\`
结果包：\`Test/native_acceptance/evidence/$TS/TestResults.xcresult\`
\`\`\`

**B. day8/答辩PPT大纲.md 第 13 页「测试执行与验证证据」追加一行：**
\`\`\`markdown
- 原生证据（$(date '+%Y-%m-%d')）：xcodebuild test 在 $DEVICE_NAME 上 $VERDICT，日志原文 \`$RAW_SUMMARY\`；结果包见 evidence/$TS/。
\`\`\`

**C. Test/复核报告-第八天.md R-03 状态：**
\`\`\`markdown
- **当前状态（$VERDICT_LABEL）**：已于 $(date '+%Y-%m-%d') 在 $DEVICE_NAME（$XC_VER / iOS SDK $SDK_VER）执行原生测试，
  \`$RAW_SUMMARY\`，\`$STATUS\`，退出码 $TEST_RC。
\`\`\`

**D. day8/苏信忠-实训日报-第八天.docx 遗留项：** 填写"原生验收：$VERDICT（$TOTAL/$FAILS/$SKIPS，$STATUS）"，并附第四节的日志与结果包路径。
EOF

echo "------------------------------------------------------------"
echo "证据文件：$EVIDMD"
if [ "$VERDICT" = "通过" ]; then
  echo "结论：P0-1 原生验收通过，可按 $EVIDMD 第五节回填 4 处证据。"
  echo "下一步：按 day8/录屏拍摄清单.md 录制 P0-2（超时一镜到底）。"
  exit 0
fi
echo "结论：未通过。请按日志逐条修复后重跑本脚本，禁止下调断言或跳过用例。"
echo "排查顺序：编译错误 -> 模拟器/签名 -> UI 元素定位 -> 时序竞态（见执行手册第四节）"
exit 1

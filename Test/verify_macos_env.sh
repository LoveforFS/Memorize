#!/usr/bin/env bash
# Memorize / WorkBuddy 项目 macOS 开发环境验证脚本
# 用法：bash verify_macos_env.sh [项目根目录]
# 说明：只读检查，不修改系统；退出码 0 表示全部合格，1 表示存在不合格项。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${1:-$SCRIPT_DIR/WorkBuddy-Delivery}"
if [ ! -d "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$SCRIPT_DIR/../day8"
fi

FAILED=0
WARNED=0

pass() { printf "[OK]   %s\n" "$*"; }
fail() { printf "[FAIL] %s\n" "$*"; FAILED=$((FAILED + 1)); }
warn() { printf "[WARN] %s\n" "$*"; WARNED=$((WARNED + 1)); }

echo "============================================================"
echo "Memorize / WorkBuddy macOS 环境验证"
echo "项目根目录：$PROJECT_ROOT"
echo "============================================================"

# 1. macOS 版本（要求 13.5 及以上）
OS_VER="$(sw_vers -productVersion 2>/dev/null || echo "0.0")"
if printf '%s\n' "$OS_VER" | awk -F. '{ exit !($1 >= 14 || ($1 == 13 && $2 >= 5)) }'; then
  pass "macOS 版本 $OS_VER（要求 13.5+）"
else
  fail "macOS 版本 $OS_VER，低于 13.5，无法安装 Xcode 15"
fi

# 2. Xcode 选择路径
DEV_DIR="$(xcode-select -p 2>/dev/null || echo "")"
case "$DEV_DIR" in
  *Xcode*.app/Contents/Developer) pass "xcode-select 指向 $DEV_DIR" ;;
  "") fail "未安装 Xcode 或未执行 xcode-select" ;;
  *) fail "xcode-select 指向 $DEV_DIR，不是 Xcode.app（仅装了 Command Line Tools）" ;;
esac

# 3. Xcode 版本（要求 15.x）
if command -v xcodebuild >/dev/null 2>&1; then
  XC_VER="$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')"
  XC_MAJOR="${XC_VER%%.*}"
  if [ "${XC_MAJOR:-0}" -ge 15 ]; then
    pass "Xcode 版本 $XC_VER（要求 15.0+）"
  else
    fail "Xcode 版本 $XC_VER，低于 15.0"
  fi
else
  fail "找不到 xcodebuild"
fi

# 4. Swift 版本（要求 5.9+）
if command -v swift >/dev/null 2>&1; then
  SWIFT_VER="$(swift --version 2>/dev/null | head -1)"
  SWIFT_NUM="$(printf '%s' "$SWIFT_VER" | sed -n 's/.*Swift version \([0-9.]*\).*/\1/p')"
  if printf '%s\n' "${SWIFT_NUM:-0.0}" | awk -F. '{ exit !($1 >= 6 || ($1 == 5 && $2 >= 9)) }'; then
    pass "Swift $SWIFT_NUM（要求 5.9+）"
  else
    fail "Swift ${SWIFT_NUM:-未知}，低于 5.9"
  fi
else
  fail "找不到 swift"
fi

# 5. iOS 模拟器 SDK（要求 17.x）
SDK_VER="$(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || echo "")"
SDK_MAJOR="${SDK_VER%%.*}"
if [ "${SDK_MAJOR:-0}" -ge 17 ]; then
  pass "iOS Simulator SDK $SDK_VER（要求 17.x）"
else
  fail "iOS Simulator SDK ${SDK_VER:-缺失}，要求 17.x"
fi

# 6. 模拟器 runtime 与 iPhone 15 设备
if xcrun simctl list runtimes 2>/dev/null | grep -q "iOS 1[67]"; then
  pass "已安装 iOS 16/17 模拟器 runtime"
else
  fail "缺少 iOS 16/17 模拟器 runtime（可执行 xcodebuild -downloadPlatform iOS）"
fi
if xcrun simctl list devices available 2>/dev/null | grep -q "iPhone 15"; then
  pass "可用设备包含 iPhone 15"
else
  warn "未找到 iPhone 15 设备，请用 xcrun simctl list devices available 选用其他设备"
fi

# 7. 工程结构（3 个 Target + 共享 Scheme）
PROJ="$PROJECT_ROOT/Memorize.xcodeproj"
if [ -d "$PROJ" ]; then
  LIST_OUT="$(xcodebuild -list -project "$PROJ" 2>/dev/null || true)"
  if printf '%s' "$LIST_OUT" | grep -q "MemorizeTests"; then pass "工程包含 MemorizeTests Target"; else fail "工程缺少 MemorizeTests Target"; fi
  if printf '%s' "$LIST_OUT" | grep -q "MemorizeUITests"; then pass "工程包含 MemorizeUITests Target"; else fail "工程缺少 MemorizeUITests Target"; fi
  if printf '%s' "$LIST_OUT" | grep -q "Memorize"; then pass "共享 Scheme Memorize 可识别"; else fail "无法识别 Scheme Memorize"; fi
else
  fail "缺少 Memorize.xcodeproj（$PROJ）"
fi

# 8. Python 3.10+（等价执行器）
if command -v python3 >/dev/null 2>&1; then
  PY_OK="$(python3 -c 'import sys; print(1 if sys.version_info[:2] >= (3,10) else 0)' 2>/dev/null || echo 0)"
  PY_VER="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || echo "0.0.0")"
  if [ "$PY_OK" = "1" ]; then pass "Python $PY_VER（要求 3.10+）"; else fail "Python $PY_VER，低于 3.10"; fi
else
  fail "找不到 python3"
fi

# 9. Git
if command -v git >/dev/null 2>&1; then
  pass "Git $(git --version | awk '{print $3}')"
else
  fail "找不到 git"
fi

# 10. 等价回归（可跳过）
HARNESS="$PROJECT_ROOT/WinTestHarness/run_tests.py"
if [ -f "$HARNESS" ] && command -v python3 >/dev/null 2>&1; then
  HARNESS_OUT="$(cd "$PROJECT_ROOT/WinTestHarness" && python3 run_tests.py 2>&1 | tail -3)"
  if printf '%s' "$HARNESS_OUT" | grep -q "通过 132"; then
    pass "等价回归 132/132"
  else
    fail "等价回归未达到 132/132"
  fi
else
  warn "未找到 WinTestHarness/run_tests.py，跳过等价回归"
fi

echo "============================================================"
echo "结论：FAIL=$FAILED WARN=$WARNED"
echo "============================================================"
if [ "$FAILED" -gt 0 ]; then
  echo "存在不合格项，请按《macOS-开发环境搭建指南》排查。"
  exit 1
fi
echo "环境满足 Memorize / WorkBuddy 项目要求。"
echo "下一步：xcodebuild test -project Memorize.xcodeproj -scheme Memorize -destination 'platform=iOS Simulator,name=iPhone 15'"
exit 0

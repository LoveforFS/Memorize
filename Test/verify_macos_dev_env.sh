#!/usr/bin/env bash
# ============================================================================
# macOS 开发环境完整性验证脚本
# 适用：macOS 11 (Big Sur) 及以上；bash 3.2 兼容；仅使用系统自带命令，无第三方依赖
# 用法：bash verify_macos_dev_env.sh
# 退出码：0 = 全部通过（或仅有可跳过项）；1 = 存在 [FAIL]
# ============================================================================

set -u
export LC_ALL=C 2>/dev/null || true

# ----- 可调整的版本基线（若团队标准变化，只改这里） --------------------------
MIN_MACOS="11.0"
MIN_GIT="2.30"
MIN_BREW="3.0"
MIN_NODE="18"
MIN_NPM="9"
MIN_PYTHON="3.10"
MIN_JAVA="11"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# ----- 输出 ------------------------------------------------------------------
pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '[PASS] %s | 期望 %s | 实际 %s\n' "$1" "$2" "$3"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '[FAIL] %s | 期望 %s | 实际 %s | 修复：%s\n' "$1" "$2" "$3" "$4"; }
skip() { SKIP_COUNT=$((SKIP_COUNT + 1)); printf '[SKIP] %s | %s\n' "$1" "$2"; }
title() { printf '\n== %s ==\n' "$1"; }

# 版本比较：$1 实际 >= $2 要求 时返回 0
ver_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    n = split(a, A, "."); m = split(b, B, ".")
    for (i = 1; i <= (n > m ? n : m); i++) {
      x = A[i] + 0; y = B[i] + 0
      if (x > y) exit 0
      if (x < y) exit 1
    }
    exit 0
  }'
}

# 提取命令输出中的第一个 x.y.z 版本号
first_version() { printf '%s' "$1" | sed -n 's/.*[^0-9]\([0-9][0-9.]*[0-9]\).*/\1/p' | head -1; }

# 工具路径有效性
check_tool_path() {
  local id="$1" name="$2" p=""
  p="$(command -v "$name" 2>/dev/null || true)"
  if [ -z "$p" ]; then
    fail "$id 工具路径 $name" "可执行文件在 PATH 中" "未找到" "安装 $name 并确认其 bin 目录已加入 PATH"
    return
  fi
  case "$p" in
    /*) ;;
    *) fail "$id 工具路径 $name" "绝对路径" "$p" "检查 PATH 中是否存在相对路径条目"; return ;;
  esac
  if [ ! -x "$p" ]; then
    fail "$id 工具路径 $name" "可执行" "$p 不可执行" "执行 chmod +x \"$p\" 或重新安装"
  else
    pass "$id 工具路径 $name" "存在且可执行" "$p"
  fi
}

printf '============================================================\n'
printf 'macOS 开发环境完整性验证\n'
printf '脚本时间：%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
printf '============================================================\n'

# ========================= 1. 操作系统 ====================================
title '1. 操作系统与架构'
OS_NAME="$(uname -s 2>/dev/null || echo unknown)"
if [ "$OS_NAME" = "Darwin" ]; then
  OS_VER="$(sw_vers -productVersion 2>/dev/null || echo 0.0)"
  OS_BUILD="$(sw_vers -buildVersion 2>/dev/null || echo unknown)"
  if ver_ge "$OS_VER" "$MIN_MACOS"; then
    pass 'E-01 macOS 版本' ">= $MIN_MACOS" "$OS_VER ($OS_BUILD)"
  else
    fail 'E-01 macOS 版本' ">= $MIN_MACOS" "$OS_VER" '系统设置 → 通用 → 软件更新，升级到 Big Sur 或更高'
  fi
else
  fail 'E-01 macOS 版本' ">= $MIN_MACOS" "$OS_NAME（非 Darwin）" '本脚本需在 macOS 原生环境执行；Windows 模拟方案见配套文档'
  OS_VER="n/a"
  OS_BUILD="n/a"
fi

ARCH="$(uname -m 2>/dev/null || echo unknown)"
case "$ARCH" in
  arm64) pass 'E-02 CPU 架构' "arm64" "$ARCH" ;;
  x86_64) pass 'E-02 CPU 架构' "x86_64" "$ARCH" ;;
  *) fail 'E-02 CPU 架构' "arm64 或 x86_64" "$ARCH" '确认硬件与系统安装完整' ;;
esac

# ========================= 2. Command Line Tools ==========================
title '2. Xcode Command Line Tools'
CLT_PATH="$(xcode-select -p 2>/dev/null || true)"
if [ -n "$CLT_PATH" ] && [ -d "$CLT_PATH" ]; then
  pass 'E-03 xcode-select 路径' "有效开发者目录" "$CLT_PATH"
else
  fail 'E-03 xcode-select 路径' "有效开发者目录" "${CLT_PATH:-未设置}" '执行 xcode-select --install；若已装 Xcode 则 sudo xcode-select -s /Applications/Xcode.app/Contents/Developer'
fi

CLT_VER=""
if command -v pkgutil >/dev/null 2>&1; then
  CLT_VER="$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/^version:/{print $2}' | head -1)"
fi
if [ -n "$CLT_VER" ]; then
  pass 'E-04 Command Line Tools' "已安装" "$CLT_VER"
elif [ -n "$CLT_PATH" ] && [ -d "$CLT_PATH" ]; then
  pass 'E-04 Command Line Tools' "已安装（随 Xcode）" "$CLT_PATH"
else
  fail 'E-04 Command Line Tools' "已安装" "未检测到" 'xcode-select --install'
fi

# ========================= 3. Homebrew =====================================
title '3. Homebrew 包管理器'
BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
BREW_VER="$(brew --version 2>/dev/null | head -1 | sed -n 's/Homebrew \(.*\)/\1/p')"
if [ -n "$BREW_PREFIX" ] && [ -x "$BREW_PREFIX/bin/brew" ]; then
  if ver_ge "${BREW_VER:-0}" "$MIN_BREW"; then
    pass 'E-05 Homebrew 状态' ">= $MIN_BREW 且可用" "$BREW_VER（prefix: $BREW_PREFIX）"
  else
    fail 'E-05 Homebrew 状态' ">= $MIN_BREW 且可用" "${BREW_VER:-未知版本}（prefix: $BREW_PREFIX）" 'brew update && brew upgrade'
  fi
else
  fail 'E-05 Homebrew 状态' ">= $MIN_BREW 且可用" "未安装或不可执行" '安装：/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
fi
if [ -n "$BREW_PREFIX" ] && [ -d "$BREW_PREFIX/bin" ]; then
  pass 'E-06 Homebrew bin 目录' "存在" "$BREW_PREFIX/bin"
else
  fail 'E-06 Homebrew bin 目录' "存在" "${BREW_PREFIX:-未安装}" '重新安装 Homebrew 或执行 brew doctor 检查'
fi

# ========================= 4. Git =========================================
title '4. Git'
if command -v git >/dev/null 2>&1; then
  GIT_VER="$(git --version 2>/dev/null | sed -n 's/^git version \([0-9.]*[0-9]\).*/\1/p')"
  if ver_ge "$GIT_VER" "$MIN_GIT"; then
    pass 'E-07 Git 版本' ">= $MIN_GIT" "$GIT_VER"
  else
    fail 'E-07 Git 版本' ">= $MIN_GIT" "${GIT_VER:-未知}" 'brew install git 并调整 PATH 优先级'
  fi
else
  GIT_VER="未安装"
  fail 'E-07 Git 版本' ">= $MIN_GIT" "未安装" 'xcode-select --install 或 brew install git'
fi

# ========================= 5. Node.js / npm ===============================
title '5. Node.js 与 npm'
if command -v node >/dev/null 2>&1; then
  NODE_VER="$(node --version 2>/dev/null | sed 's/^v//')"
  if ver_ge "$NODE_VER" "$MIN_NODE"; then
    pass 'E-08 Node.js 版本' ">= $MIN_NODE" "$NODE_VER"
  else
    fail 'E-08 Node.js 版本' ">= $MIN_NODE" "$NODE_VER" 'brew install node@20 或 nvm install --lts'
  fi
else
  NODE_VER="未安装"
  fail 'E-08 Node.js 版本' ">= $MIN_NODE" "未安装" 'brew install node 或 nvm install --lts'
fi
if command -v npm >/dev/null 2>&1; then
  NPM_VER="$(npm --version 2>/dev/null)"
  if ver_ge "$NPM_VER" "$MIN_NPM"; then
    pass 'E-09 npm 版本' ">= $MIN_NPM" "$NPM_VER"
  else
    fail 'E-09 npm 版本' ">= $MIN_NPM" "$NPM_VER" 'npm install -g npm@latest'
  fi
else
  NPM_VER="未安装"
  fail 'E-09 npm 版本' ">= $MIN_NPM" "未安装" '随 Node.js 安装；确认 node 安装后重启终端'
fi

# ========================= 6. Python ======================================
title '6. Python'
if command -v python3 >/dev/null 2>&1; then
  PY_RAW="$(python3 --version 2>&1 || true)"
  PY_VER="$(printf '%s' "$PY_RAW" | sed -n 's/^Python \([0-9][0-9.]*[0-9]\).*/\1/p')"
  if [ -z "$PY_VER" ]; then
    PY_VER="解析失败"
    skip 'E-10 Python3 版本' "python3 存在但无法解析版本：$PY_RAW"
  elif ver_ge "$PY_VER" "$MIN_PYTHON"; then
    pass 'E-10 Python3 版本' ">= $MIN_PYTHON" "$PY_VER"
  else
    fail 'E-10 Python3 版本' ">= $MIN_PYTHON" "$PY_VER" 'brew install python@3.12；确认 which python3 指向 3.12'
  fi
else
  PY_VER="未安装"
  fail 'E-10 Python3 版本' ">= $MIN_PYTHON" "未安装" '安装 python.org 3.12 安装包或 brew install python@3.12'
fi

# ========================= 7. Java（可选） ================================
title '7. Java（可选组件）'
if command -v java >/dev/null 2>&1; then
  JAVA_VER="$(java -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9][0-9._]*\)".*/\1/p')"
  JAVA_VER="${JAVA_VER:-未知}"
  if [ "$JAVA_VER" = "未知" ]; then
    skip 'E-11 Java 版本' '已安装但版本解析失败，请手动执行 java -version 核对'
  elif ver_ge "$JAVA_VER" "$MIN_JAVA"; then
    pass 'E-11 Java 版本' ">= $MIN_JAVA" "$JAVA_VER"
  else
    fail 'E-11 Java 版本' ">= $MIN_JAVA" "$JAVA_VER" 'brew install openjdk@17 并配置 JAVA_HOME'
  fi
else
  JAVA_VER="未配置（可选）"
  skip 'E-11 Java 版本' '未配置，非本项目必需；如需使用：brew install openjdk@17'
fi

# ========================= 8. PATH 合法性 =================================
title '8. PATH 配置合法性'
PATH_VALUE="${PATH:-}"
if [ -z "$PATH_VALUE" ]; then
  fail 'E-12 PATH 非空' "包含系统目录" "PATH 为空" 'export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"'
else
  pass 'E-12 PATH 非空' "包含系统目录" "长度 ${#PATH_VALUE}"
fi

EMPTY_SEG=0
MISSING_SEG=0
DUP_SEG=0
BAD_PERM=0
REL_SEG=0
SEEN="|"
PATH_LIST=""
IFS=: read -r -a PATH_DIRS <<< "$PATH_VALUE"
for d in ${PATH_DIRS[@]+"${PATH_DIRS[@]}"}; do
  PATH_LIST="$PATH_LIST$d:"
  if [ -z "$d" ]; then
    EMPTY_SEG=$((EMPTY_SEG + 1))
    continue
  fi
  case "$d" in
    /*) ;;
    *) REL_SEG=$((REL_SEG + 1)) ;;
  esac
  if [ ! -d "$d" ]; then
    MISSING_SEG=$((MISSING_SEG + 1))
  elif [ ! -x "$d" ]; then
    BAD_PERM=$((BAD_PERM + 1))
  fi
  case "$SEEN" in
    *"|$d|"*) DUP_SEG=$((DUP_SEG + 1)) ;;
    *) SEEN="$SEEN$d|" ;;
  esac
done
if [ "$EMPTY_SEG" -eq 0 ] && [ "$MISSING_SEG" -eq 0 ] && [ "$DUP_SEG" -eq 0 ] \
  && [ "$BAD_PERM" -eq 0 ] && [ "$REL_SEG" -eq 0 ]; then
  pass 'E-13 PATH 条目质量' "无空段/缺失/重复/相对路径/不可执行" \
    "共 $(printf '%s' "$PATH_VALUE" | awk -F: '{print NF}') 段"
else
  fail 'E-13 PATH 条目质量' "无空段/缺失/重复/相对路径/不可执行" \
    "空段 $EMPTY_SEG，缺失 $MISSING_SEG，重复 $DUP_SEG，相对路径 $REL_SEG，不可执行 $BAD_PERM" \
    '编辑 ~/.zshrc 或 /etc/paths，删除空段、相对路径与失效条目并去重，重开终端'
fi

# 关键目录是否在 PATH
KEY_DIRS=("/usr/local/bin" "/usr/bin" "/bin" "/usr/sbin" "/sbin")
[ -n "$BREW_PREFIX" ] && KEY_DIRS+=("$BREW_PREFIX/bin")
KEY_MISSING=""
for k in "${KEY_DIRS[@]}"; do
  case ":$PATH_VALUE:" in
    *":$k:"*) ;;
    *) KEY_MISSING="$KEY_MISSING $k" ;;
  esac
done
if [ -z "$KEY_MISSING" ]; then
  pass 'E-14 关键目录在 PATH' "系统目录与包管理器目录齐全" "全部存在"
else
  fail 'E-14 关键目录在 PATH' "包含系统与 Homebrew 目录" "缺少:$KEY_MISSING" \
    '在 ~/.zshrc 追加 export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"（Apple Silicon 另加 /opt/homebrew/bin）'
fi

# ========================= 9. 工具链路径有效性 ============================
title '9. 常用工具链路径有效性'
check_tool_path 'E-15' 'git'
check_tool_path 'E-16' 'brew'
check_tool_path 'E-17' 'python3'
if command -v node >/dev/null 2>&1; then
  check_tool_path 'E-18' 'node'
else
  skip 'E-18 工具路径 node' '未安装，见 E-08'
fi
if command -v xcodebuild >/dev/null 2>&1; then
  check_tool_path 'E-19' 'xcodebuild'
else
  skip 'E-19 工具路径 xcodebuild' '未安装 Xcode，见 E-03/E-04'
fi

# ========================= 10. 摘要 ======================================
printf '\n============================================================\n'
printf '验证结果：PASS=%d FAIL=%d SKIP=%d\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf '结论：环境满足基线要求\n'
else
  printf '结论：存在 %d 项不合格，请按上方“修复”列处理\n' "$FAIL_COUNT"
fi
printf '============================================================\n'

printf '\n==== COPY BELOW（环境配置摘要）====\n'
printf 'TIMESTAMP=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
printf 'SCRIPT_VERSION=1.0\n'
printf 'OS=%s\n' "$OS_NAME"
printf 'OS_VERSION=%s\n' "$OS_VER"
printf 'OS_BUILD=%s\n' "$OS_BUILD"
printf 'ARCH=%s\n' "$ARCH"
printf 'XCODE_SELECT_PATH=%s\n' "${CLT_PATH:-none}"
printf 'CLT_VERSION=%s\n' "${CLT_VER:-none}"
printf 'HOMEBREW_VERSION=%s\n' "${BREW_VER:-none}"
printf 'HOMEBREW_PREFIX=%s\n' "${BREW_PREFIX:-none}"
printf 'GIT_VERSION=%s\n' "${GIT_VER:-none}"
printf 'NODE_VERSION=%s\n' "${NODE_VER:-none}"
printf 'NPM_VERSION=%s\n' "${NPM_VER:-none}"
printf 'PYTHON3_VERSION=%s\n' "${PY_VER:-none}"
printf 'JAVA_VERSION=%s\n' "${JAVA_VER:-none}"
printf 'PATH_ENTRY_COUNT=%s\n' "$(printf '%s' "$PATH_VALUE" | awk -F: '{print NF}')"
printf 'PATH=%s\n' "$PATH_VALUE"
printf 'VERDICT=%s\n' "$([ "$FAIL_COUNT" -eq 0 ] && echo PASS || echo FAIL)"
printf '==== COPY ABOVE ====\n'

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0

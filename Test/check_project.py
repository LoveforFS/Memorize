# -*- coding: utf-8 -*-
"""全项目整体复核脚本（在 Test 目录内运行，只读检查 day1-day8）。

输出：
1. 控制台分级结果（PASS / WARN / FAIL）；
2. Test/check_results.json 结构化明细。
"""

import json
import os
import re
import subprocess
import zipfile
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEST_DIR = os.path.join(ROOT, "Test")
DAY8 = os.path.join(ROOT, "day8")
W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"

results = {"pass": [], "warn": [], "fail": [], "details": {}}


def ok(name, detail=""):
    results["pass"].append({"item": name, "detail": detail})


def warn(name, detail=""):
    results["warn"].append({"item": name, "detail": detail})


def fail(name, detail=""):
    results["fail"].append({"item": name, "detail": detail})


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def swift_files(base):
    out = []
    for dirpath, _, files in os.walk(base):
        for f in files:
            if f.endswith(".swift"):
                out.append(os.path.join(dirpath, f))
    return sorted(out)


def strip_comments(text):
    text = re.sub(r"//.*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return text


# ---------------------------------------------------------------------------
# 1. 目录与结转完整性
# ---------------------------------------------------------------------------
inventory = {}
for d in range(1, 9):
    p = os.path.join(ROOT, "day%d" % d)
    if not os.path.isdir(p):
        fail("day%d 目录存在" % d, p)
        continue
    files = [os.path.join(dp, f) for dp, _, fs in os.walk(p) for f in fs]
    inventory["day%d" % d] = {
        "files": len(files),
        "swift": len([f for f in files if f.endswith(".swift")]),
        "docx": [os.path.basename(f) for f in files if f.endswith(".docx")],
    }
results["details"]["inventory"] = inventory

required_dirs = ["Memorize", "MemorizeTests", "MemorizeUITests", "WinTestHarness"]
missing = [d for d in required_dirs if not os.path.isdir(os.path.join(DAY8, d))]
if missing:
    fail("day8 四个核心目录齐全", "缺少：" + ",".join(missing))
else:
    ok("day8 四个核心目录齐全", "共 %d 个文件" % inventory.get("day8", {}).get("files", 0))

day8_business_files = swift_files(os.path.join(DAY8, "Memorize")) + \
    swift_files(os.path.join(DAY8, "MemorizeTests")) + \
    swift_files(os.path.join(DAY8, "MemorizeUITests"))
if len(day8_business_files) == 27:
    ok("day8 业务与测试 Swift 文件数量", "27 个（业务 15 + 单元/集成 10 + UI 2）")
else:
    warn("day8 Swift 文件数量", "实际 %d 个，预期 27" % len(day8_business_files))

# Xcode 工程文件（R-02 交付要求）
proj_path = os.path.join(DAY8, "Memorize.xcodeproj", "project.pbxproj")
scheme_path = os.path.join(DAY8, "Memorize.xcodeproj", "xcshareddata", "xcschemes",
                           "Memorize.xcscheme")
if os.path.isfile(proj_path) and os.path.isfile(scheme_path):
    proj_text = read(proj_path)
    checks = {
        "3 个 Target": proj_text.count("isa = PBXNativeTarget;") == 3,
        "27 个 BuildFile": proj_text.count("isa = PBXBuildFile;") == 27,
        "应用 Target": "com.apple.product-type.application" in proj_text,
        "单元测试 Target": "com.apple.product-type.bundle.unit-test" in proj_text,
        "UI 测试 Target": "com.apple.product-type.bundle.ui-testing" in proj_text,
        "共享 Scheme": "MemorizeTests.xctest" in read(scheme_path),
    }
    if all(checks.values()):
        ok("Xcode 工程文件", "project.pbxproj 与共享 Scheme 存在且结构完整")
    else:
        fail("Xcode 工程文件", json.dumps(checks, ensure_ascii=False))
else:
    fail("Xcode 工程文件存在", "缺少 project.pbxproj 或 Memorize.xcscheme")

# 排除日报：day8 根目录仅允许规定产物
root_files = [f for f in os.listdir(DAY8) if os.path.isfile(os.path.join(DAY8, f))]
allowed_root = {"README.md", "演示脚本.md", "答辩PPT大纲.md", "项目核心文档.md",
                "WorkBuddy交接提示词.md", "录屏拍摄清单.md", "学习笔记-第八天.md",
                "苏信忠-实训日报-第八天.docx"}
extra = [f for f in root_files if f not in allowed_root]
if extra:
    fail("day8 根目录无历史日报或多余文件", "多余：" + ",".join(extra))
else:
    ok("day8 根目录无历史日报或多余文件", ",".join(sorted(root_files)))

# ---------------------------------------------------------------------------
# 2. 类型定义、重复声明与空实现
# ---------------------------------------------------------------------------
type_pattern = re.compile(r"(?:struct|class|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)")
declared = {}
for path in day8_business_files:
    for name in type_pattern.findall(strip_comments(read(path))):
        declared.setdefault(name, []).append(os.path.relpath(path, DAY8))
dups = {k: v for k, v in declared.items() if len(v) > 1}
if dups:
    fail("无重复类型声明", json.dumps(dups, ensure_ascii=False))
else:
    ok("无重复类型声明", "共 %d 个类型" % len(declared))

empty_bodies = []
for path in day8_business_files:
    text = strip_comments(read(path))
    for m in re.finditer(r"func\s+[A-Za-z_][A-Za-z0-9_]*\s*\([^)]*\)\s*(?:->[^{]+)?\{\s*\}", text):
        empty_bodies.append(os.path.relpath(path, DAY8) + ":" + m.group(0)[:40])
if empty_bodies:
    warn("存在空函数体", "; ".join(empty_bodies))
else:
    ok("无空函数体", "未发现 func 空实现")

# ---------------------------------------------------------------------------
# 3. 测试用例数量与映射
# ---------------------------------------------------------------------------
expected_suites = {
    "GameModelTests": 28, "GameViewModelTests": 11, "MismatchTimerTests": 10,
    "AspectVGridTests": 9, "AnimationTimingTests": 9,
    "GameAnimationCoordinatorTests": 10, "AnimationIntegrationTests": 13,
    "CardifyStyleTests": 8, "PieGeometryTests": 10,
    "CountdownIntegrationTests": 16, "GameFlowUITests": 5,
    "AnimationFlowUITests": 3,
}
actual = {}
for path in day8_business_files:
    rel = os.path.relpath(path, DAY8).replace("\\", "/")
    if rel.startswith("MemorizeTests/") or rel.startswith("MemorizeUITests/"):
        n = len(re.findall(r"func\s+test[A-Za-z0-9_]*\s*\(", strip_comments(read(path))))
        actual[os.path.basename(path).replace(".swift", "")] = n
suite_diff = {k: (actual.get(k), v) for k, v in expected_suites.items() if actual.get(k) != v}
if suite_diff:
    fail("12 个套件用例数与文档一致", json.dumps(suite_diff, ensure_ascii=False))
else:
    ok("12 个套件用例数与文档一致", "合计 %d 条" % sum(actual.values()))
results["details"]["suites"] = {
    "actual": actual, "expected": expected_suites, "total": sum(actual.values())}

# 执行器结果文件
result_json = os.path.join(DAY8, "WinTestHarness", "test_results.json")
if os.path.isfile(result_json):
    data = json.loads(read(result_json))
    summary = data.get("summary", {})
    cov = data.get("coverage", {})
    if summary.get("total") == 132 and summary.get("passed") == 132 and \
            summary.get("failed") == 0 and summary.get("skipped") == 0 and cov.get("ok") is True:
        ok("test_results.json 结果", "132/132，coverage.ok=true")
    else:
        fail("test_results.json 结果", json.dumps(summary, ensure_ascii=False))
else:
    fail("test_results.json 存在", result_json)

# ---------------------------------------------------------------------------
# 4. README 四模块与路径一致性
# ---------------------------------------------------------------------------
readme_path = os.path.join(DAY8, "README.md")
readme = read(readme_path)
sections = ["架构分层说明", "模块与功能点对照映射表", "Step-by-step 项目构建", "测试执行流程"]
missing_sections = [s for s in sections if s not in readme]
if missing_sections:
    fail("README 四个核心模块", "缺少：" + ",".join(missing_sections))
else:
    ok("README 四个核心模块", "均存在")

ref_paths = set(re.findall(r"`(Memorize(?:Tests|UITests)?/[^`\s]+|WinTestHarness/[^`\s]+)`", readme))
ref_paths = {p for p in ref_paths if "*" not in p}
missing_paths = []
for rel in ref_paths:
    p = os.path.join(DAY8, rel.rstrip("/"))
    if not os.path.exists(p):
        missing_paths.append(rel)
if missing_paths:
    fail("README 引用路径存在", "缺失：" + ",".join(missing_paths))
else:
    ok("README 引用路径存在", "共 %d 个路径引用" % len(ref_paths))

readme_stale = [t for t in ["day7", "day6", "D7 模块"] if t in readme]
if readme_stale:
    warn("README 无历史日期引用", ",".join(readme_stale))
else:
    ok("README 无历史日期引用", "未发现 day6/day7 字样")

# ---------------------------------------------------------------------------
# 5. 文档产物完整性（日报 title/date/总量）
# ---------------------------------------------------------------------------
cn = {2: "二", 3: "三", 4: "四", 5: "五", 6: "六", 7: "七", 8: "八"}
expected_totals = {4: "54", 5: "63", 6: "98", 7: "132", 8: "132"}
expected_dates = {
    2: "2026 年 11 月 3 日", 3: "2026 年 11 月 4 日", 4: "2026 年 11 月 5 日",
    5: "2026 年 11 月 5 日", 6: "2026 年 11 月 6 日", 7: "2026 年 11 月 7 日",
    8: "2026 年 11 月 8 日",
}
docx_report = {}
docx_date_map = {}
for d in range(2, 9):
    p = os.path.join(ROOT, "day%d" % d, "苏信忠-实训日报-第%s天.docx" % cn[d])
    if not os.path.isfile(p):
        fail("day%d 日报存在" % d, p)
        continue
    try:
        with zipfile.ZipFile(p) as z:
            xml = z.read("word/document.xml").decode("utf-8")
    except Exception as e:
        fail("day%d 日报可解析" % d, str(e))
        continue
    title = "实训日报（第%s天）" % cn[d]
    dates = set(re.findall(r"2026\s*年\s*\d+\s*月\s*\d+\s*日", xml))
    docx_date_map["day%d" % d] = sorted(dates)
    checks = {"title": title in xml, "date": expected_dates[d] in dates}
    if d in expected_totals:
        checks["total"] = ("%s 条" % expected_totals[d]) in xml
    docx_report["day%d" % d] = checks
    if all(checks.values()):
        ok("day%d 日报内容" % d, "标题/日期/用例总数均匹配")
    else:
        fail("day%d 日报内容" % d, json.dumps(checks, ensure_ascii=False))
results["details"]["docx"] = docx_report
results["details"]["docx_dates"] = docx_date_map

# 日期重复属于文档标注一致性问题，单独提示
seen = {}
for day, dates in docx_date_map.items():
    for dt in dates:
        seen.setdefault(dt, []).append(day)
dups_dates = {k: v for k, v in seen.items() if len(v) > 1}
if dups_dates:
    warn("日报日期无重复", json.dumps(dups_dates, ensure_ascii=False))
else:
    ok("日报日期无重复", "D2–D8 各自独立")

for rel in ["README.md", "演示脚本.md", "答辩PPT大纲.md"]:
    p = os.path.join(DAY8, rel)
    if os.path.isfile(p) and os.path.getsize(p) > 2000:
        ok("day8 文档 %s" % rel, "%d 字节" % os.path.getsize(p))
    else:
        fail("day8 文档 %s" % rel, "缺失或内容过少")

# ---------------------------------------------------------------------------
# 6. 可访问性标识与 UI 用例一致性
# ---------------------------------------------------------------------------
view_ids = set()
for path in swift_files(os.path.join(DAY8, "Memorize", "Views")):
    for m in re.findall(r'accessibilityIdentifier\("([^"]+)"\)', read(path)):
        view_ids.add(m)
ui_literals = set()
for path in swift_files(os.path.join(DAY8, "MemorizeUITests")):
    t = read(path)
    ui_literals.update(re.findall(r'staticTexts\["([^"]+)"\]', t))
    ui_literals.update(re.findall(r'buttons\["([^"#]+)"\]', t))
    ui_literals.update(re.findall(r'matching\(identifier:\s*"([^"\\]+)"\)', t))
ui_literals = {x for x in ui_literals if x not in ("再来一局", "")}
missing_ids = []
for lit in sorted(ui_literals):
    if lit in view_ids:
        continue
    if lit.startswith("theme-") and any(v.startswith("theme-") for v in view_ids):
        continue
    if lit.startswith("card-") and any(v.startswith("card-") for v in view_ids):
        continue
    if lit == "Memorize" or "：" in lit or "…" in lit or "卡片" in lit:
        continue  # 文案类断言，不是可访问性标识
    missing_ids.append(lit)
if missing_ids:
    fail("UI 用例引用的可访问性标识均存在", "缺失：" + ",".join(missing_ids))
else:
    ok("UI 用例引用的可访问性标识均存在", "共 %d 个" % len(ui_literals))

# ---------------------------------------------------------------------------
# 7. 关键数值与文档一致
# ---------------------------------------------------------------------------
gv = read(os.path.join(DAY8, "Memorize", "ViewModels", "GameViewModel.swift"))
timing = read(os.path.join(DAY8, "Memorize", "Views", "AnimationTiming.swift"))
cardify = read(os.path.join(DAY8, "Memorize", "Views", "Cardify.swift"))
pie = read(os.path.join(DAY8, "Memorize", "Views", "Pie.swift"))
clock = read(os.path.join(DAY8, "Memorize", "ViewModels", "CountdownClock.swift"))
constant_checks = {
    "翻回延迟 0.8 秒": "TimeInterval = 0.8" in gv,
    "倒计时默认 60 秒": "static let duration = 60" in clock,
    "倒计时周期 1 秒": "tickInterval: TimeInterval = 1" in clock,
    "翻牌时长 0.45 秒": "flipDuration: Double = 0.45" in timing,
    "发牌错峰 0.06 秒": "dealStagger: Double = 0.06" in timing,
    "发牌错峰封顶 0.6 秒": "dealMaxStagger: Double = 0.6" in timing,
    "圆角 12%": "0.12" in cardify,
    "环宽 10%": "0.1" in pie,
}
bad_constants = [k for k, v in constant_checks.items() if not v]
if bad_constants:
    fail("关键参数与文档一致", "不一致：" + ",".join(bad_constants))
else:
    ok("关键参数与文档一致", "8 项参数全部匹配")

doc_numbers = {
    "README 含 132 条": "132" in readme,
    "演示脚本含 60 秒": "60 秒" in read(os.path.join(DAY8, "演示脚本.md")),
    "答辩大纲含 0.45 秒": "0.45 秒" in read(os.path.join(DAY8, "答辩PPT大纲.md")),
    "答辩大纲含 0.8 秒": "0.8 秒" in read(os.path.join(DAY8, "答辩PPT大纲.md")),
}
if not all(doc_numbers.values()):
    fail("文档数值与源码一致", json.dumps(doc_numbers, ensure_ascii=False))
else:
    ok("文档数值与源码一致", "4 项抽查通过")

# ---------------------------------------------------------------------------
# 8. 遗留标记与 Git 状态
# ---------------------------------------------------------------------------
todos = []
for path in swift_files(DAY8):
    for i, line in enumerate(read(path).splitlines(), 1):
        if re.search(r"TODO|FIXME|XXX", line):
            todos.append("%s:%d %s" % (os.path.relpath(path, DAY8), i, line.strip()))
if todos:
    warn("无 TODO/FIXME 标记", "; ".join(todos))
else:
    ok("无 TODO/FIXME 标记", "源码中未发现")

try:
    status = subprocess.run(["git", "-C", ROOT, "status", "--porcelain"],
                            capture_output=True, text=True, timeout=30).stdout.strip()
    results["details"]["git_status"] = status
    dirty = [l for l in status.splitlines()
             if "~$" not in l and not l.startswith("?? Test/")]
    if dirty:
        warn("Git 工作区干净", "存在未提交变更：" + " | ".join(dirty))
    else:
        ok("Git 工作区干净", "除 Test 复核目录外无未提交变更")
except Exception as e:
    warn("Git 状态检查", str(e))

out_path = os.path.join(TEST_DIR, "check_results.json")
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(results, f, ensure_ascii=False, indent=2)

print("=" * 60)
for item in results["pass"]:
    print("[PASS]", item["item"], "-", item["detail"])
for item in results["warn"]:
    print("[WARN]", item["item"], "-", item["detail"])
for item in results["fail"]:
    print("[FAIL]", item["item"], "-", item["detail"])
print("=" * 60)
print("PASS=%d WARN=%d FAIL=%d" % (len(results["pass"]), len(results["warn"]), len(results["fail"])))
print("结果文件：", out_path)

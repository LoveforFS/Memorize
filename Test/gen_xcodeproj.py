# -*- coding: utf-8 -*-
"""生成 day8/Memorize.xcodeproj（经典 PBX 工程格式）与共享 Scheme。

在 Windows 上无法运行 xcodebuild，本脚本只保证：
1. 工程结构完整（3 个 Target、Products、Sources 阶段、依赖关系）；
2. 所有 Swift 文件按目录精确挂载，无遗漏、无重复；
3. UUID 唯一、括号平衡、引用闭包完整；
4. 输出可直接被 Xcode 15 打开的 project.pbxproj 与共享 Scheme。
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DAY8 = os.path.join(ROOT, "day8")
PROJ_DIR = os.path.join(DAY8, "Memorize.xcodeproj")
SCHEME_DIR = os.path.join(PROJ_DIR, "xcshareddata", "xcschemes")

APP_DIR = os.path.join(DAY8, "Memorize")
UNIT_DIR = os.path.join(DAY8, "MemorizeTests")
UI_DIR = os.path.join(DAY8, "MemorizeUITests")


def swift_files(base):
    out = []
    for dp, _, fs in os.walk(base):
        for f in sorted(fs):
            if f.endswith(".swift"):
                out.append(os.path.join(dp, f))
    return sorted(out)


# ---------------------------------------------------------------------------
# UUID 分配
# ---------------------------------------------------------------------------
IDS = {
    "PROJECT": "D80000000000000000000001",
    "MAIN_GROUP": "D80000000000000000000002",
    "PRODUCTS_GROUP": "D80000000000000000000003",
    "APP_GROUP": "D80000000000000000000004",
    "MODELS_GROUP": "D80000000000000000000005",
    "VMS_GROUP": "D80000000000000000000006",
    "VIEWS_GROUP": "D80000000000000000000007",
    "UNIT_GROUP": "D80000000000000000000008",
    "UI_GROUP": "D80000000000000000000009",
    "APP_TARGET": "D80000000000000000000010",
    "UNIT_TARGET": "D80000000000000000000011",
    "UI_TARGET": "D80000000000000000000012",
    "APP_PRODUCT": "D80000000000000000000013",
    "UNIT_PRODUCT": "D80000000000000000000014",
    "UI_PRODUCT": "D80000000000000000000015",
    "PROJECT_CFG": "D80000000000000000000016",
    "APP_CFG": "D80000000000000000000017",
    "UNIT_CFG": "D80000000000000000000018",
    "UI_CFG": "D80000000000000000000019",
    "PROJECT_DEBUG": "D80000000000000000000020",
    "PROJECT_RELEASE": "D80000000000000000000021",
    "APP_DEBUG": "D80000000000000000000022",
    "APP_RELEASE": "D80000000000000000000023",
    "UNIT_DEBUG": "D80000000000000000000024",
    "UNIT_RELEASE": "D80000000000000000000025",
    "UI_DEBUG": "D80000000000000000000026",
    "UI_RELEASE": "D80000000000000000000027",
    "APP_SOURCES": "D80000000000000000000028",
    "APP_FRAMEWORKS": "D80000000000000000000029",
    "APP_RESOURCES": "D80000000000000000000030",
    "UNIT_SOURCES": "D80000000000000000000031",
    "UNIT_FRAMEWORKS": "D80000000000000000000032",
    "UNIT_RESOURCES": "D80000000000000000000033",
    "UI_SOURCES": "D80000000000000000000034",
    "UI_FRAMEWORKS": "D80000000000000000000035",
    "UI_RESOURCES": "D80000000000000000000036",
    "UNIT_PROXY": "D80000000000000000000037",
    "UNIT_DEP": "D80000000000000000000038",
    "UI_PROXY": "D80000000000000000000039",
    "UI_DEP": "D80000000000000000000040",
}

seq_file = [0]
seq_build = [0]


def next_file_ref():
    seq_file[0] += 1
    return "E8000000000000000000%04d" % seq_file[0]


def next_build_ref():
    seq_build[0] += 1
    return "B8000000000000000000%04d" % seq_build[0]


app_files = swift_files(APP_DIR)
unit_files = swift_files(UNIT_DIR)
ui_files = swift_files(UI_DIR)

# 校验文件清单与预期一致
assert len(app_files) == 15, "应用源文件数量异常：%d" % len(app_files)
assert len(unit_files) == 10, "单元测试文件数量异常：%d" % len(unit_files)
assert len(ui_files) == 2, "UI 测试文件数量异常：%d" % len(ui_files)

file_refs = {}   # (section, relpath) -> id
build_refs = {}  # relpath -> id


def rel(path, base):
    return os.path.relpath(path, base).replace("\\", "/")


for path in app_files:
    key = ("app", rel(path, APP_DIR))
    file_refs[key] = next_file_ref()
    build_refs["app:" + key[1]] = next_build_ref()
for path in unit_files:
    key = ("unit", os.path.basename(path))
    file_refs[key] = next_file_ref()
    build_refs["unit:" + key[1]] = next_build_ref()
for path in ui_files:
    key = ("ui", os.path.basename(path))
    file_refs[key] = next_file_ref()
    build_refs["ui:" + key[1]] = next_build_ref()


def name_of(key):
    return key[1].split("/")[-1]


def file_comment(key):
    return name_of(key)


# ---------------------------------------------------------------------------
# 各 section 文本
# ---------------------------------------------------------------------------
def build_file_section():
    lines = ["/* Begin PBXBuildFile section */"]
    for path in app_files:
        p = rel(path, APP_DIR)
        key = ("app", p)
        lines.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
                     % (build_refs["app:" + p], name_of(key), file_refs[key], file_comment(key)))
    for path in unit_files:
        key = ("unit", os.path.basename(path))
        lines.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
                     % (build_refs["unit:" + key[1]], name_of(key), file_refs[key], file_comment(key)))
    for path in ui_files:
        key = ("ui", os.path.basename(path))
        lines.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
                     % (build_refs["ui:" + key[1]], name_of(key), file_refs[key], file_comment(key)))
    lines.append("/* End PBXBuildFile section */")
    return "\n".join(lines)


def file_ref_section():
    lines = ["/* Begin PBXFileReference section */"]
    for path in app_files:
        key = ("app", rel(path, APP_DIR))
        lines.append('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
                     'path = %s; sourceTree = "<group>"; };' % (file_refs[key], name_of(key), name_of(key)))
    for path in unit_files:
        key = ("unit", os.path.basename(path))
        lines.append('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
                     'path = %s; sourceTree = "<group>"; };' % (file_refs[key], name_of(key), name_of(key)))
    for path in ui_files:
        key = ("ui", os.path.basename(path))
        lines.append('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
                     'path = %s; sourceTree = "<group>"; };' % (file_refs[key], name_of(key), name_of(key)))
    lines.append('\t\t%s /* Memorize.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; '
                 'includeInIndex = 0; path = Memorize.app; sourceTree = BUILT_PRODUCTS_DIR; };' % IDS["APP_PRODUCT"])
    lines.append('\t\t%s /* MemorizeTests.xctest */ = {isa = PBXFileReference; explicitFileType = '
                 'wrapper.cfbundle; includeInIndex = 0; path = MemorizeTests.xctest; '
                 'sourceTree = BUILT_PRODUCTS_DIR; };' % IDS["UNIT_PRODUCT"])
    lines.append('\t\t%s /* MemorizeUITests.xctest */ = {isa = PBXFileReference; explicitFileType = '
                 'wrapper.cfbundle; includeInIndex = 0; path = MemorizeUITests.xctest; '
                 'sourceTree = BUILT_PRODUCTS_DIR; };' % IDS["UI_PRODUCT"])
    lines.append("/* End PBXFileReference section */")
    return "\n".join(lines)


def group_section():
    norm = lambda p: p.replace("\\", "/")
    models = [("app", "Models/" + os.path.basename(p)) for p in app_files if "/Models/" in norm(p)]
    vms = [("app", "ViewModels/" + os.path.basename(p)) for p in app_files if "/ViewModels/" in norm(p)]
    views = [("app", "Views/" + os.path.basename(p)) for p in app_files if "/Views/" in norm(p)]
    unit_keys = [("unit", os.path.basename(p)) for p in unit_files]
    ui_keys = [("ui", os.path.basename(p)) for p in ui_files]

    def refs(keys):
        return "\n".join('\t\t\t\t%s /* %s */,' % (file_refs[k], name_of(k)) for k in keys)

    lines = ["/* Begin PBXGroup section */"]
    lines.append("\t\t%s = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
                 % (IDS["MAIN_GROUP"],
                    "\n".join(["\t\t\t\t%s /* Memorize */," % IDS["APP_GROUP"],
                               "\t\t\t\t%s /* MemorizeTests */," % IDS["UNIT_GROUP"],
                               "\t\t\t\t%s /* MemorizeUITests */," % IDS["UI_GROUP"],
                               "\t\t\t\t%s /* Products */," % IDS["PRODUCTS_GROUP"]])))
    lines.append("\t\t%s /* Memorize */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n%s\n%s\n%s\n\t\t\t);\n"
                 "\t\t\tpath = Memorize;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
                 % (IDS["APP_GROUP"],
                    "\t\t\t\t%s /* MemorizeApp.swift */," % file_refs[("app", "MemorizeApp.swift")],
                    "\t\t\t\t%s /* Models */," % IDS["MODELS_GROUP"],
                    "\t\t\t\t%s /* ViewModels */," % IDS["VMS_GROUP"],
                    "\t\t\t\t%s /* Views */," % IDS["VIEWS_GROUP"]))
    lines.append("\t\t%s /* Models */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n\t\t\tpath = Models;\n"
                 "\t\t\tsourceTree = \"<group>\";\n\t\t};" % (IDS["MODELS_GROUP"], refs(models)))
    lines.append("\t\t%s /* ViewModels */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n\t\t\tpath = ViewModels;\n"
                 "\t\t\tsourceTree = \"<group>\";\n\t\t};" % (IDS["VMS_GROUP"], refs(vms)))
    lines.append("\t\t%s /* Views */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n\t\t\tpath = Views;\n"
                 "\t\t\tsourceTree = \"<group>\";\n\t\t};" % (IDS["VIEWS_GROUP"], refs(views)))
    lines.append("\t\t%s /* MemorizeTests */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n"
                 "\t\t\tpath = MemorizeTests;\n\t\t\tsourceTree = \"<group>\";\n\t\t};" % (IDS["UNIT_GROUP"], refs(unit_keys)))
    lines.append("\t\t%s /* MemorizeUITests */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n"
                 "\t\t\tpath = MemorizeUITests;\n\t\t\tsourceTree = \"<group>\";\n\t\t};" % (IDS["UI_GROUP"], refs(ui_keys)))
    lines.append("\t\t%s /* Products */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
                 "\t\t\t\t%s /* Memorize.app */,\n\t\t\t\t%s /* MemorizeTests.xctest */,\n"
                 "\t\t\t\t%s /* MemorizeUITests.xctest */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
                 % (IDS["PRODUCTS_GROUP"], IDS["APP_PRODUCT"], IDS["UNIT_PRODUCT"], IDS["UI_PRODUCT"]))
    lines.append("/* End PBXGroup section */")
    return "\n".join(lines)


def build_phase(kind, pid, files_refs, comment):
    lines = ["/* Begin %s section */" % kind]
    if kind == "PBXSourcesBuildPhase":
        lines.append("\t\t%s /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
                     "\t\t\tfiles = (\n%s\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};" % (pid, files_refs))
    else:
        lines.append("\t\t%s /* %s */ = {\n\t\t\tisa = %s;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
                     "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};" % (pid, comment, kind))
    lines.append("/* End %s section */" % kind)
    return "\n".join(lines)


def sources_refs(prefix, files, base):
    return "\n".join('\t\t\t\t%s /* %s in Sources */,' % (build_refs[prefix + ":" + (rel(p, base) if prefix == "app"
                                                                                      else os.path.basename(p))],
                                                           os.path.basename(p)) for p in files)


def native_target_section():
    lines = ["/* Begin PBXNativeTarget section */"]
    lines.append('\t\t%s /* Memorize */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = %s;\n'
                 '\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Frameworks */,\n\t\t\t\t%s /* Resources */,\n'
                 '\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = Memorize;\n'
                 '\t\t\tproductName = Memorize;\n\t\t\tproductReference = %s /* Memorize.app */;\n'
                 '\t\t\tproductType = "com.apple.product-type.application";\n\t\t};'
                 % (IDS["APP_TARGET"], IDS["APP_CFG"], IDS["APP_SOURCES"], IDS["APP_FRAMEWORKS"], IDS["APP_RESOURCES"],
                    IDS["APP_PRODUCT"]))
    lines.append('\t\t%s /* MemorizeTests */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = %s;\n'
                 '\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Frameworks */,\n\t\t\t\t%s /* Resources */,\n'
                 '\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t\t%s /* PBXTargetDependency */,\n'
                 '\t\t\t);\n\t\t\tname = MemorizeTests;\n\t\t\tproductName = MemorizeTests;\n'
                 '\t\t\tproductReference = %s /* MemorizeTests.xctest */;\n'
                 '\t\t\tproductType = "com.apple.product-type.bundle.unit-test";\n\t\t};'
                 % (IDS["UNIT_TARGET"], IDS["UNIT_CFG"], IDS["UNIT_SOURCES"], IDS["UNIT_FRAMEWORKS"],
                    IDS["UNIT_RESOURCES"], IDS["UNIT_DEP"], IDS["UNIT_PRODUCT"]))
    lines.append('\t\t%s /* MemorizeUITests */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = %s;\n'
                 '\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Frameworks */,\n\t\t\t\t%s /* Resources */,\n'
                 '\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t\t%s /* PBXTargetDependency */,\n'
                 '\t\t\t);\n\t\t\tname = MemorizeUITests;\n\t\t\tproductName = MemorizeUITests;\n'
                 '\t\t\tproductReference = %s /* MemorizeUITests.xctest */;\n'
                 '\t\t\tproductType = "com.apple.product-type.bundle.ui-testing";\n\t\t};'
                 % (IDS["UI_TARGET"], IDS["UI_CFG"], IDS["UI_SOURCES"], IDS["UI_FRAMEWORKS"],
                    IDS["UI_RESOURCES"], IDS["UI_DEP"], IDS["UI_PRODUCT"]))
    lines.append("/* End PBXNativeTarget section */")
    return "\n".join(lines)


def project_section():
    return """/* Begin PBXProject section */
\t\t%s /* Project object */ = {
\t\t\tisa = PBXProject;
\t\t\tattributes = {
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {
\t\t\t\t\t%s = {
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t};
\t\t\t\t\t%s = {
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t\tTestTargetID = %s;
\t\t\t\t\t};
\t\t\t\t\t%s = {
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t\tTestTargetID = %s;
\t\t\t\t\t};
\t\t\t\t};
\t\t\t};
\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject "Memorize" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = %s;
\t\t\tproductRefGroup = %s /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t%s /* Memorize */,
\t\t\t\t%s /* MemorizeTests */,
\t\t\t\t%s /* MemorizeUITests */,
\t\t\t);
\t\t};
/* End PBXProject section */""" % (IDS["PROJECT"], IDS["APP_TARGET"], IDS["UNIT_TARGET"], IDS["APP_TARGET"],
                                   IDS["UI_TARGET"], IDS["APP_TARGET"], IDS["PROJECT_CFG"],
                                   IDS["MAIN_GROUP"], IDS["PRODUCTS_GROUP"], IDS["APP_TARGET"],
                                   IDS["UNIT_TARGET"], IDS["UI_TARGET"])


def dependency_section():
    return """/* Begin PBXContainerItemProxy section */
\t\t%s /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = %s /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = %s;
\t\t\tremoteInfo = Memorize;
\t\t};
\t\t%s /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = %s /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = %s;
\t\t\tremoteInfo = Memorize;
\t\t};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
\t\t%s /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = %s /* Memorize */;
\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;
\t\t};
\t\t%s /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = %s /* Memorize */;
\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;
\t\t};
/* End PBXTargetDependency section */""" % (
        IDS["UNIT_PROXY"], IDS["PROJECT"], IDS["APP_TARGET"],
        IDS["UI_PROXY"], IDS["PROJECT"], IDS["APP_TARGET"],
        IDS["UNIT_DEP"], IDS["APP_TARGET"], IDS["UNIT_PROXY"],
        IDS["UI_DEP"], IDS["APP_TARGET"], IDS["UI_PROXY"])


def config_blocks():
    project_debug = """\t\t%s /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t};
\t\t\tname = Debug;
\t\t};""" % IDS["PROJECT_DEBUG"]
    project_release = """\t\t%s /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t};
\t\t\tname = Release;
\t\t};""" % IDS["PROJECT_RELEASE"]

    app_common = """\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.suxinzhong.memorize;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";"""

    unit_common = """\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@loader_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.suxinzhong.memorizeTests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/Memorize.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Memorize";"""

    ui_common = """\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@loader_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.suxinzhong.memorizeUITests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tTEST_TARGET_NAME = Memorize;"""

    def target_cfg(cid, name, settings):
        return "\t\t%s /* %s */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\n\t\t\t};\n\t\t\tname = %s;\n\t\t};" % (cid, name, settings, name)

    lines = ["/* Begin XCBuildConfiguration section */", project_debug, project_release]
    lines.append(target_cfg(IDS["APP_DEBUG"], "Debug", app_common))
    lines.append(target_cfg(IDS["APP_RELEASE"], "Release", app_common))
    lines.append(target_cfg(IDS["UNIT_DEBUG"], "Debug", unit_common))
    lines.append(target_cfg(IDS["UNIT_RELEASE"], "Release", unit_common))
    lines.append(target_cfg(IDS["UI_DEBUG"], "Debug", ui_common))
    lines.append(target_cfg(IDS["UI_RELEASE"], "Release", ui_common))
    lines.append("/* End XCBuildConfiguration section */")
    return "\n".join(lines)


def config_list_section():
    def lst(cid, debug_id, release_id, label):
        return ("\t\t%s /* Build configuration list for %s */ = {\n\t\t\tisa = XCConfigurationList;\n"
                "\t\t\tbuildConfigurations = (\n\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);\n"
                "\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};"
                % (cid, label, debug_id, release_id))

    return "\n".join([
        "/* Begin XCConfigurationList section */",
        lst(IDS["PROJECT_CFG"], IDS["PROJECT_DEBUG"], IDS["PROJECT_RELEASE"], 'PBXProject "Memorize"'),
        lst(IDS["APP_CFG"], IDS["APP_DEBUG"], IDS["APP_RELEASE"], "PBXNativeTarget \"Memorize\""),
        lst(IDS["UNIT_CFG"], IDS["UNIT_DEBUG"], IDS["UNIT_RELEASE"], "PBXNativeTarget \"MemorizeTests\""),
        lst(IDS["UI_CFG"], IDS["UI_DEBUG"], IDS["UI_RELEASE"], "PBXNativeTarget \"MemorizeUITests\""),
        "/* End XCConfigurationList section */",
    ])


framework_phase = "\n".join([
    build_phase("PBXFrameworksBuildPhase", IDS["APP_FRAMEWORKS"], None, "Frameworks"),
    build_phase("PBXFrameworksBuildPhase", IDS["UNIT_FRAMEWORKS"], None, "Frameworks"),
    build_phase("PBXFrameworksBuildPhase", IDS["UI_FRAMEWORKS"], None, "Frameworks"),
])
resource_phase = "\n".join([
    build_phase("PBXResourcesBuildPhase", IDS["APP_RESOURCES"], None, "Resources"),
    build_phase("PBXResourcesBuildPhase", IDS["UNIT_RESOURCES"], None, "Resources"),
    build_phase("PBXResourcesBuildPhase", IDS["UI_RESOURCES"], None, "Resources"),
])
source_phase = "\n".join([
    build_phase("PBXSourcesBuildPhase", IDS["APP_SOURCES"], sources_refs("app", app_files, APP_DIR), "Sources"),
    build_phase("PBXSourcesBuildPhase", IDS["UNIT_SOURCES"], sources_refs("unit", unit_files, UNIT_DIR), "Sources"),
    build_phase("PBXSourcesBuildPhase", IDS["UI_SOURCES"], sources_refs("ui", ui_files, UI_DIR), "Sources"),
])

object_sections = "\n\n".join([
    build_file_section(),
    file_ref_section(),
    framework_phase,
    group_section(),
    native_target_section(),
    project_section(),
    resource_phase,
    source_phase,
    dependency_section(),
    config_blocks(),
    config_list_section(),
])

pbxproj = """// !$*UTF8*$!
{
\tarchiveVersion = 1;
\tclasses = {
\t};
\tobjectVersion = 56;
\tobjects = {

%s
\t};
\trootObject = %s /* Project object */;
}
""" % (object_sections, IDS["PROJECT"])

# ---------------------------------------------------------------------------
# 共享 Scheme
# ---------------------------------------------------------------------------
scheme = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%s"
               BuildableName = "Memorize.app"
               BlueprintName = "Memorize"
               ReferencedContainer = "container:Memorize.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%s"
               BuildableName = "MemorizeTests.xctest"
               BlueprintName = "MemorizeTests"
               ReferencedContainer = "container:Memorize.xcodeproj">
            </BuildableReference>
         </TestableReference>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%s"
               BuildableName = "MemorizeUITests.xctest"
               BlueprintName = "MemorizeUITests"
               ReferencedContainer = "container:Memorize.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%s"
            BuildableName = "Memorize.app"
            BlueprintName = "Memorize"
            ReferencedContainer = "container:Memorize.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%s"
            BuildableName = "Memorize.app"
            BlueprintName = "Memorize"
            ReferencedContainer = "container:Memorize.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"/>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
""" % (IDS["APP_TARGET"], IDS["UNIT_TARGET"], IDS["UI_TARGET"], IDS["APP_TARGET"], IDS["APP_TARGET"])

os.makedirs(SCHEME_DIR, exist_ok=True)
proj_path = os.path.join(PROJ_DIR, "project.pbxproj")
scheme_path = os.path.join(SCHEME_DIR, "Memorize.xcscheme")
with open(proj_path, "w", encoding="utf-8", newline="\n") as f:
    f.write(pbxproj)
with open(scheme_path, "w", encoding="utf-8", newline="\n") as f:
    f.write(scheme)

# ---------------------------------------------------------------------------
# 结构自检
# ---------------------------------------------------------------------------
defined = set(re.findall(r"^\t\t([0-9A-F]{24})\s", pbxproj, flags=re.M))
dups = re.findall(r"^\t\t([0-9A-F]{24})\s", pbxproj, flags=re.M)
assert len(dups) == len(set(dups)), "存在重复 UUID"
referenced = set(re.findall(r"[0-9A-F]{24}", pbxproj))
undefined = referenced - defined - {IDS["PROJECT"]}
assert not undefined, "存在未定义引用：" + ",".join(sorted(undefined))
assert pbxproj.count("{") == pbxproj.count("}"), "花括号不平衡"
assert pbxproj.count("(") == pbxproj.count(")"), "圆括号不平衡"

# 对象数量与目标归属核对
assert pbxproj.count("isa = PBXBuildFile;") == len(app_files) + len(unit_files) + len(ui_files), "BuildFile 数量不匹配"
assert pbxproj.count("isa = PBXFileReference;") == len(app_files) + len(unit_files) + len(ui_files) + 3, "FileReference 数量不匹配"
assert pbxproj.count("isa = PBXNativeTarget;") == 3, "Target 数量不匹配"
assert pbxproj.count("isa = PBXSourcesBuildPhase;") == 3, "Sources 阶段数量不匹配"
assert pbxproj.count("productType = \"com.apple.product-type.application\";") == 1, "应用 Target 缺失"
assert pbxproj.count("productType = \"com.apple.product-type.bundle.unit-test\";") == 1, "单元测试 Target 缺失"
assert pbxproj.count("productType = \"com.apple.product-type.bundle.ui-testing\";") == 1, "UI 测试 Target 缺失"

# 每个 Swift 文件必须且只能挂载一次 Sources
for files in (app_files, unit_files, ui_files):
    for path in files:
        base = os.path.basename(path)
        assert pbxproj.count("%s in Sources */ = {isa = PBXBuildFile;" % base) == 1, "重复或缺失挂载：" + base

# Scheme 必须是合法 XML，且包含 3 个可构建目标 + 2 个测试包
import xml.etree.ElementTree as ET
root = ET.fromstring(scheme)
assert root.tag == "Scheme", "Scheme 根节点异常"
build_refs = root.findall(".//TestAction/Testables/TestableReference")
assert len(build_refs) == 2, "测试包数量异常：%d" % len(build_refs)
ids_in_scheme = {node.get("BlueprintIdentifier") for node in root.iter("BuildableReference")}
assert ids_in_scheme == {IDS["APP_TARGET"], IDS["UNIT_TARGET"], IDS["UI_TARGET"]}, "Scheme 目标引用异常"


# ---------------------------------------------------------------------------
# OpenStep 属性列表解析校验：确认 project.pbxproj 语法可被解析
# ---------------------------------------------------------------------------
def parse_openstep(text):
    tokens = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch in " \t\r\n":
            i += 1
        elif text.startswith("//", i):
            i = text.find("\n", i)
            i = n if i < 0 else i + 1
        elif text.startswith("/*", i):
            end = text.find("*/", i)
            assert end >= 0, "注释未闭合"
            i = end + 2
        elif ch in "{}()=;,":
            tokens.append(ch)
            i += 1
        elif ch == '"':
            j = i + 1
            buf = []
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    buf.append(text[j + 1])
                    j += 2
                else:
                    buf.append(text[j])
                    j += 1
            assert j < n, "字符串未闭合"
            tokens.append(("str", "".join(buf)))
            i = j + 1
        else:
            j = i
            while j < n and text[j] not in " \t\r\n{}()=;,/\"":
                j += 1
            tokens.append(("str", text[i:j]))
            i = j

    pos = [0]

    def next_token():
        assert pos[0] < len(tokens), "属性列表意外结束"
        token = tokens[pos[0]]
        pos[0] += 1
        return token

    def parse_value():
        token = next_token()
        if token == "{":
            result = {}
            while True:
                key = next_token()
                if key == "}":
                    return result
                assert isinstance(key, tuple), "字典键必须是字符串"
                assert next_token() == "=", "字典缺少等号"
                result[key[1]] = parse_value()
                assert next_token() == ";", "字典缺少分号"
        if token == "(":
            result = []
            while True:
                token = next_token()
                if token == ")":
                    return result
                pos[0] -= 1
                result.append(parse_value())
                token = next_token()
                if token == ")":
                    return result
                assert token == ",", "数组缺少逗号"
        assert isinstance(token, tuple), "非法值：" + repr(token)
        return token[1]

    parsed = parse_value()
    assert pos[0] == len(tokens), "属性列表存在多余内容"
    return parsed


plist = parse_openstep(pbxproj)
assert isinstance(plist, dict), "根节点必须是字典"
assert plist["archiveVersion"] == "1"
assert plist["objectVersion"] == "56"
objects = plist["objects"]
assert isinstance(objects, dict), "objects 必须是字典"
assert len(objects) == len(defined), "解析出的对象数量与定义数量不一致"
assert all(isinstance(o, dict) and o.get("isa") for o in objects.values()), "存在缺少 isa 的对象"
assert plist["rootObject"] in objects, "rootObject 未指向有效对象"
assert objects[plist["rootObject"]]["isa"] == "PBXProject", "rootObject 不是 PBXProject"

print("project:", proj_path, os.path.getsize(proj_path), "bytes")
print("scheme :", scheme_path, os.path.getsize(scheme_path), "bytes")
print("objects:", len(objects), "app files:", len(app_files), "unit:", len(unit_files), "ui:", len(ui_files))
print("UUID check: unique + all references defined + braces balanced")
print("plist check: OpenStep syntax parsed, rootObject -> PBXProject")
print("targets: app + unit + ui, scheme testables: 2")

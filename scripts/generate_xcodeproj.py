#!/usr/bin/env python3
"""Generate Keshijizhang.xcodeproj from the source tree. No Xcode required."""

import hashlib
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Keshijizhang"
PROJECT = ROOT / "Keshijizhang.xcodeproj"
TARGET_NAME = "Keshijizhang"


def oid(seed: str) -> str:
    return hashlib.md5(seed.encode("utf-8")).hexdigest()[:24].upper()


def quote(value: str) -> str:
    if value.startswith("("):
        return value
    if value.isascii() and all(ch.isalnum() or ch in "._/$" for ch in value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


class Node:
    def __init__(self, path: Path, rel: Path):
        self.path = path
        self.rel = rel
        self.name = path.name
        self.children = []
        self.ref_id = oid(f"ref:{rel.as_posix()}")
        self.build_id = oid(f"build:{rel.as_posix()}")
        self.group_id = oid(f"group:{rel.as_posix()}")


def build_tree(directory: Path, rel: Path) -> Node:
    node = Node(directory, rel)
    entries = sorted(directory.iterdir(), key=lambda p: (p.is_file(), p.name.lower()))
    for entry in entries:
        if entry.name.startswith("."):
            continue
        child_rel = rel / entry.name
        if entry.is_dir():
            if entry.suffix == ".xcassets":
                node.children.append(Node(entry, child_rel))
            else:
                node.children.append(build_tree(entry, child_rel))
        elif entry.suffix == ".swift":
            node.children.append(Node(entry, child_rel))
    return node


def walk(node: Node):
    yield node
    for child in node.children:
        if child.path.is_dir() and child.path.suffix != ".xcassets":
            yield from walk(child)
        else:
            yield child


def main():
    tree = build_tree(SOURCE, Path("Keshijizhang"))
    files = [node for node in walk(tree) if node.path.is_file() or node.path.suffix == ".xcassets"]
    swift_files = [node for node in files if node.path.suffix == ".swift"]
    resources = [node for node in files if node.path.suffix == ".xcassets"]

    project_id = oid("project")
    target_id = oid("target")
    sources_phase = oid("phase:sources")
    resources_phase = oid("phase:resources")
    frameworks_phase = oid("phase:frameworks")
    product_ref = oid("product")
    main_group = oid("group:main")
    products_group = oid("group:products")
    debug_project = oid("config:project:debug")
    release_project = oid("config:project:release")
    debug_target = oid("config:target:debug")
    release_target = oid("config:target:release")
    project_list = oid("list:project")
    target_list = oid("list:target")

    lines = []
    w = lines.append
    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")
    w("")
    w("/* Begin PBXBuildFile section */")
    for node in swift_files + resources:
        w(f"\t\t{node.build_id} /* {node.name} in {'Sources' if node.path.suffix == '.swift' else 'Resources'} */ = {{isa = PBXBuildFile; fileRef = {node.ref_id} /* {node.name} */; }};")
    w("/* End PBXBuildFile section */")
    w("")
    w("/* Begin PBXFileReference section */")
    for node in swift_files:
        w(f"\t\t{node.ref_id} /* {node.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(node.name)}; sourceTree = \"<group>\"; }};")
    for node in resources:
        w(f"\t\t{node.ref_id} /* {node.name} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {quote(node.name)}; sourceTree = \"<group>\"; }};")
    w(f"\t\t{product_ref} /* {TARGET_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {TARGET_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    w("/* End PBXFileReference section */")
    w("")
    w("/* Begin PBXFrameworksBuildPhase section */")
    w(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXFrameworksBuildPhase section */")
    w("")
    w("/* Begin PBXGroup section */")

    def emit_group(node: Node):
        child_ids = []
        for child in node.children:
            if child.path.is_dir() and child.path.suffix != ".xcassets":
                child_ids.append((child.group_id, child.name))
            else:
                child_ids.append((child.ref_id, child.name))
        w(f"\t\t{node.group_id} /* {node.name} */ = {{")
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for cid, name in child_ids:
            w(f"\t\t\t\t{cid} /* {name} */,")
        w("\t\t\t);")
        w(f"\t\t\tpath = {quote(node.name)};")
        w('\t\t\tsourceTree = "<group>";')
        w("\t\t};")
        for child in node.children:
            if child.path.is_dir() and child.path.suffix != ".xcassets":
                emit_group(child)

    emit_group(tree)
    w(f"\t\t{products_group} /* Products */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{product_ref} /* {TARGET_NAME}.app */,")
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w('\t\t\tsourceTree = "<group>";')
    w("\t\t};")
    w(f"\t\t{main_group} = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{tree.group_id} /* Keshijizhang */,")
    w(f"\t\t\t\t{products_group} /* Products */,")
    w("\t\t\t);")
    w('\t\t\tsourceTree = "<group>";')
    w("\t\t};")
    w("/* End PBXGroup section */")
    w("")
    w("/* Begin PBXNativeTarget section */")
    w(f"\t\t{target_id} /* {TARGET_NAME} */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {target_list} /* Build configuration list for PBXNativeTarget \"{TARGET_NAME}\" */;")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{sources_phase} /* Sources */,")
    w(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
    w(f"\t\t\t\t{resources_phase} /* Resources */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = (")
    w("\t\t\t);")
    w("\t\t\tdependencies = (")
    w("\t\t\t);")
    w(f"\t\t\tname = {TARGET_NAME};")
    w(f"\t\t\tproductName = {TARGET_NAME};")
    w(f"\t\t\tproductReference = {product_ref} /* {TARGET_NAME}.app */;")
    w('\t\t\tproductType = "com.apple.product-type.application";')
    w("\t\t};")
    w("/* End PBXNativeTarget section */")
    w("")
    w("/* Begin PBXProject section */")
    w(f"\t\t{project_id} /* Project object */ = {{")
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastSwiftUpdateCheck = 1600;")
    w("\t\t\t\tLastUpgradeCheck = 1600;")
    w("\t\t\t\tTargetAttributes = {")
    w(f"\t\t\t\t\t{target_id} = {{")
    w("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    w("\t\t\t\t\t};")
    w("\t\t\t\t};")
    w("\t\t\t};")
    w(f"\t\t\tbuildConfigurationList = {project_list} /* Build configuration list for PBXProject \"{TARGET_NAME}\" */;")
    w('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    w('\t\t\tdevelopmentRegion = "zh-Hans";')
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (")
    w("\t\t\t\ten,")
    w("\t\t\t\tBase,")
    w('\t\t\t\t"zh-Hans",')
    w("\t\t\t);")
    w(f"\t\t\tmainGroup = {main_group};")
    w(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
    w('\t\t\tprojectDirPath = "";')
    w('\t\t\tprojectRoot = "";')
    w("\t\t\ttargets = (")
    w(f"\t\t\t\t{target_id} /* {TARGET_NAME} */,")
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")
    w("")
    w("/* Begin PBXResourcesBuildPhase section */")
    w(f"\t\t{resources_phase} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for node in resources:
        w(f"\t\t\t\t{node.build_id} /* {node.name} in Resources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")
    w("")
    w("/* Begin PBXSourcesBuildPhase section */")
    w(f"\t\t{sources_phase} /* Sources */ = {{")
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for node in swift_files:
        w(f"\t\t\t\t{node.build_id} /* {node.name} in Sources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")
    w("")

    common_project = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    }
    debug_project_settings = {
        **common_project,
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }
    release_project_settings = {
        **common_project,
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "VALIDATE_PRODUCT": "YES",
    }
    common_target = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_CFBundleDisplayName": "课时记账",
        "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UIStatusBarStyle": "UIStatusBarStyleDefault",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.example.keshijizhang",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SDKROOT": "iphoneos",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO",
        "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_STRICT_CONCURRENCY": "minimal",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1",
    }
    debug_target_settings = {
        **common_target,
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }
    release_target_settings = {
        **common_target,
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
    }

    def emit_config(cid, name, settings):
        w(f"\t\t{cid} /* {name} */ = {{")
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        for key in sorted(settings):
            w(f"\t\t\t\t{key} = {quote(settings[key])};")
        w("\t\t\t};")
        w(f"\t\t\tname = {name};")
        w("\t\t};")

    w("/* Begin XCBuildConfiguration section */")
    emit_config(debug_project, "Debug", debug_project_settings)
    emit_config(release_project, "Release", release_project_settings)
    emit_config(debug_target, "Debug", debug_target_settings)
    emit_config(release_target, "Release", release_target_settings)
    w("/* End XCBuildConfiguration section */")
    w("")
    w("/* Begin XCConfigurationList section */")
    w(f"\t\t{project_list} /* Build configuration list for PBXProject \"{TARGET_NAME}\" */ = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{debug_project} /* Debug */,")
    w(f"\t\t\t\t{release_project} /* Release */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
    w(f"\t\t{target_list} /* Build configuration list for PBXNativeTarget \"{TARGET_NAME}\" */ = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{debug_target} /* Debug */,")
    w(f"\t\t\t\t{release_target} /* Release */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
    w("/* End XCConfigurationList section */")
    w("\t};")
    w(f"\trootObject = {project_id} /* Project object */;")
    w("}")
    w("")

    PROJECT.mkdir(exist_ok=True)
    (PROJECT / "project.pbxproj").write_text("\n".join(lines), encoding="utf-8")

    scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    ref = f"""
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "{TARGET_NAME}.app"
               BlueprintName = "{TARGET_NAME}"
               ReferencedContainer = "container:{TARGET_NAME}.xcodeproj"
"""
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
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
            <BuildableReference{ref}>
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
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
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference{ref}>
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference{ref}>
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    (scheme_dir / f"{TARGET_NAME}.xcscheme").write_text(scheme, encoding="utf-8")
    print(f"Wrote {PROJECT} with {len(swift_files)} Swift files")
    print("target", target_id)


if __name__ == "__main__":
    main()

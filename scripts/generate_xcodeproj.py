#!/usr/bin/env python3
"""Generates Vault.xcodeproj.

The project uses Xcode 16+ folder-synchronized groups, so every Swift file and
asset inside a target's folders is picked up automatically: you only need to
re-run this script if you add a target or change target-level structure.

    python3 scripts/generate_xcodeproj.py
"""

import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "Vault.xcodeproj")


def oid(*parts: str) -> str:
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def q(value: str) -> str:
    """Quote a pbxproj string when needed."""
    safe = all(c.isalnum() or c in "._/" for c in value)
    if value and safe and not value.startswith("$("):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


TARGETS = [
    {
        "name": "Vault",
        "product": "Vault.app",
        "type": "com.apple.product-type.application",
        "file_type": "wrapper.application",
        "folders": ["Vault", "Shared", "SharedIntents"],
        "xcconfig": "Vault.xcconfig",
        "embeds": ["VaultWidgets", "VaultShare"],
    },
    {
        "name": "VaultWidgets",
        "product": "VaultWidgets.appex",
        "type": "com.apple.product-type.app-extension",
        "file_type": "wrapper.app-extension",
        "folders": ["VaultWidgets", "Shared", "SharedIntents"],
        "xcconfig": "VaultWidgets.xcconfig",
        "embeds": [],
    },
    {
        "name": "VaultShare",
        "product": "VaultShare.appex",
        "type": "com.apple.product-type.app-extension",
        "file_type": "wrapper.app-extension",
        "folders": ["VaultShare", "Shared"],
        "xcconfig": "VaultShare.xcconfig",
        "embeds": [],
    },
]

CONFIG_FILES = [
    "Signing.xcconfig", "Base.xcconfig", "Vault.xcconfig", "VaultWidgets.xcconfig", "VaultShare.xcconfig",
    "Vault-Info.plist", "VaultWidgets-Info.plist", "VaultShare-Info.plist",
] + sorted("Entitlements/" + f for f in os.listdir(os.path.join(ROOT, "Config", "Entitlements")))

FILE_TYPES = {".xcconfig": "text.xcconfig", ".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements"}
SYNC_FOLDERS = ["Vault", "Shared", "SharedIntents", "VaultWidgets", "VaultShare"]

PROJECT_SETTINGS = {
    "Debug": {
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    },
    "Release": {
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "VALIDATE_PRODUCT": "YES",
        "MTL_ENABLE_DEBUG_INFO": "NO",
    },
}


def build() -> str:
    objs: dict[str, dict[str, str]] = {}

    def add(section: str, ident: str, body: str) -> None:
        objs.setdefault(section, {})[ident] = body

    project_id = oid("project")
    main_group = oid("group", "main")
    products_group = oid("group", "products")
    config_group = oid("group", "config")

    # Config file references
    config_refs = {}
    for name in CONFIG_FILES:
        ref = oid("fileref", "config", name)
        config_refs[name] = ref
        add("PBXFileReference", ref,
            f"{{isa = PBXFileReference; lastKnownFileType = {FILE_TYPES[os.path.splitext(name)[1]]}; path = {q(name)}; sourceTree = \"<group>\"; }}")

    # Synchronized folders
    sync_ids = {}
    for folder in SYNC_FOLDERS:
        ident = oid("sync", folder)
        sync_ids[folder] = ident
        add("PBXFileSystemSynchronizedRootGroup", ident,
            f"{{isa = PBXFileSystemSynchronizedRootGroup; path = {q(folder)}; sourceTree = \"<group>\"; }}")

    # Products
    product_refs = {}
    for t in TARGETS:
        ref = oid("product", t["name"])
        product_refs[t["name"]] = ref
        add("PBXFileReference", ref,
            f"{{isa = PBXFileReference; explicitFileType = {q(t['file_type'])}; includeInIndex = 0; path = {q(t['product'])}; sourceTree = BUILT_PRODUCTS_DIR; }}")

    # Groups
    children = ",\n\t\t\t\t".join([sync_ids[f] for f in SYNC_FOLDERS] + [config_group, products_group])
    add("PBXGroup", main_group, f"{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{children},\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}}")
    pchildren = ",\n\t\t\t\t".join(product_refs[t["name"]] for t in TARGETS)
    add("PBXGroup", products_group, f"{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{pchildren},\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}}")
    cchildren = ",\n\t\t\t\t".join(config_refs[n] for n in CONFIG_FILES)
    add("PBXGroup", config_group, f"{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{cchildren},\n\t\t\t);\n\t\t\tpath = Config;\n\t\t\tsourceTree = \"<group>\";\n\t\t}}")

    # Targets
    target_ids = {t["name"]: oid("target", t["name"]) for t in TARGETS}
    for t in TARGETS:
        name = t["name"]
        phases = []
        for phase in ("Sources", "Frameworks", "Resources"):
            pid = oid("phase", name, phase)
            phases.append(pid)
            add(f"PBX{phase}BuildPhase", pid,
                f"{{\n\t\t\tisa = PBX{phase}BuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}}")
        deps = []
        if t["embeds"]:
            embed_files = []
            for ext in t["embeds"]:
                bf = oid("buildfile", name, "embed", ext)
                embed_files.append(bf)
                add("PBXBuildFile", bf,
                    f"{{isa = PBXBuildFile; fileRef = {product_refs[ext]}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }}")
                proxy = oid("proxy", name, ext)
                add("PBXContainerItemProxy", proxy,
                    f"{{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {project_id};\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {target_ids[ext]};\n\t\t\tremoteInfo = {ext};\n\t\t}}")
                dep = oid("dependency", name, ext)
                deps.append(dep)
                add("PBXTargetDependency", dep,
                    f"{{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {target_ids[ext]};\n\t\t\ttargetProxy = {proxy};\n\t\t}}")
            pid = oid("phase", name, "embed")
            phases.append(pid)
            files = ",\n\t\t\t\t".join(embed_files)
            add("PBXCopyFilesBuildPhase", pid,
                f"{{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n\t\t\t\t{files},\n\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}}")

        configs = []
        for cfg in ("Debug", "Release"):
            cid = oid("config", name, cfg)
            configs.append(cid)
            add("XCBuildConfiguration", cid,
                f"{{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbaseConfigurationReference = {config_refs[t['xcconfig']]};\n\t\t\tbuildSettings = {{\n\t\t\t}};\n\t\t\tname = {cfg};\n\t\t}}")
        clist = oid("configlist", name)
        add("XCConfigurationList", clist,
            f"{{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{configs[0]},\n\t\t\t\t{configs[1]},\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}}")

        phase_list = ",\n\t\t\t\t".join(phases)
        dep_list = "".join(f"\n\t\t\t\t{d}," for d in deps)
        sync_list = ",\n\t\t\t\t".join(sync_ids[f] for f in t["folders"])
        add("PBXNativeTarget", target_ids[name],
            f"{{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {clist};\n\t\t\tbuildPhases = (\n\t\t\t\t{phase_list},\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = ({dep_list}\n\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{sync_list},\n\t\t\t);\n\t\t\tname = {name};\n\t\t\tpackageProductDependencies = (\n\t\t\t);\n\t\t\tproductName = {name};\n\t\t\tproductReference = {product_refs[name]};\n\t\t\tproductType = {q(t['type'])};\n\t\t}}")

    # Project configs
    pconfigs = []
    for cfg, settings in PROJECT_SETTINGS.items():
        cid = oid("config", "project", cfg)
        pconfigs.append(cid)
        body = "".join(f"\n\t\t\t\t{k} = {q(v)};" for k, v in sorted(settings.items()))
        add("XCBuildConfiguration", cid,
            f"{{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbaseConfigurationReference = {config_refs['Base.xcconfig']};\n\t\t\tbuildSettings = {{{body}\n\t\t\t}};\n\t\t\tname = {cfg};\n\t\t}}")
    plist = oid("configlist", "project")
    add("XCConfigurationList", plist,
        f"{{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{pconfigs[0]},\n\t\t\t\t{pconfigs[1]},\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}}")

    target_attrs = "".join(f"\n\t\t\t\t\t{target_ids[t['name']]} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;\n\t\t\t\t\t}};" for t in TARGETS)
    tlist = ",\n\t\t\t\t".join(target_ids[t["name"]] for t in TARGETS)
    add("PBXProject", project_id,
        f"{{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2600;\n\t\t\t\tLastUpgradeCheck = 2600;\n\t\t\t\tTargetAttributes = {{{target_attrs}\n\t\t\t\t}};\n\t\t\t}};\n\t\t\tbuildConfigurationList = {plist};\n\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n\t\t\tmainGroup = {main_group};\n\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {products_group};\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n\t\t\t\t{tlist},\n\t\t\t);\n\t\t}}")

    out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 77;", "\tobjects = {"]
    for section in sorted(objs):
        out.append("")
        out.append(f"/* Begin {section} section */")
        for ident in sorted(objs[section]):
            out.append(f"\t\t{ident} = {objs[section][ident]};")
        out.append(f"/* End {section} section */")
    out += ["\t};", f"\trootObject = {project_id};", "}", ""]
    return "\n".join(out), target_ids


def scheme(target_ids: dict[str, str]) -> str:
    app = target_ids["Vault"]
    ref = f"""<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app}"
               BuildableName = "Vault.app"
               BlueprintName = "Vault"
               ReferencedContainer = "container:Vault.xcodeproj">
            </BuildableReference>"""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
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
         {ref}
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
         {ref}
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


def main() -> None:
    pbxproj, target_ids = build()
    os.makedirs(os.path.join(PROJECT, "xcshareddata", "xcschemes"), exist_ok=True)
    with open(os.path.join(PROJECT, "project.pbxproj"), "w") as f:
        f.write(pbxproj)
    with open(os.path.join(PROJECT, "xcshareddata", "xcschemes", "Vault.xcscheme"), "w") as f:
        f.write(scheme(target_ids))
    os.makedirs(os.path.join(PROJECT, "project.xcworkspace"), exist_ok=True)
    with open(os.path.join(PROJECT, "project.xcworkspace", "contents.xcworkspacedata"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')
    print("Wrote", PROJECT)


if __name__ == "__main__":
    main()

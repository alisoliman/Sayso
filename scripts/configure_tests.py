#!/usr/bin/env python3
"""Idempotently configure Sayso XCTest targets and its shared scheme.

Uses macOS plutil to read the Xcode project; no third-party package is required.
Keeps the app and tests on the iOS 27.0 deployment floor.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Sayso.xcodeproj"
PBXPROJ = PROJECT / "project.pbxproj"
MINIMUM_IOS_VERSION = "27.0"


def identifier(name: str) -> str:
    return hashlib.sha256(f"Sayso/{name}".encode()).hexdigest()[:24].upper()


def atom(value: object) -> str:
    value = str(value)
    if re.fullmatch(r"[A-Za-z0-9_./]+", value):
        return value
    return json.dumps(value, ensure_ascii=False)


def openstep(value: object, indent: int = 0) -> str:
    pad = "\t" * indent
    child = pad + "\t"
    if isinstance(value, dict):
        return "{\n" + "".join(
            f"{child}{atom(key)} = {openstep(item, indent + 1)};\n"
            for key, item in value.items()
        ) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join(
            f"{child}{openstep(item, indent + 1)},\n" for item in value
        ) + pad + ")"
    return atom(value)


def append_once(values: list, item: str) -> None:
    if item not in values:
        values.append(item)


def app_versions(objects: dict, app: dict, configuration: str) -> dict:
    """Match the app configuration; absent version settings inherit from the project."""
    app_config = next(
        objects[config_id]
        for config_id in objects[app["buildConfigurationList"]]["buildConfigurations"]
        if objects[config_id]["name"] == configuration
    )
    settings = app_config["buildSettings"]
    return {key: settings[key] for key in ["CURRENT_PROJECT_VERSION", "MARKETING_VERSION"]
            if key in settings}


def main() -> None:
    data = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-", str(PBXPROJ)
    ]))
    objects = data["objects"]
    project = objects[data["rootObject"]]
    app_id = next(key for key, obj in objects.items()
                  if obj.get("isa") == "PBXNativeTarget" and obj.get("name") == "Sayso")
    app = objects[app_id]
    main_group = objects[project["mainGroup"]]
    products = objects[project["productRefGroup"]]

    for config_id in objects[app["buildConfigurationList"]]["buildConfigurations"]:
        settings = objects[config_id]["buildSettings"]
        settings.update({
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": "Sayso.xcodeproj/Sayso-Info.plist",
            "INFOPLIST_KEY_NSMicrophoneUsageDescription":
                "Sayso uses your microphone to turn your voice into text on this iPhone.",
            "IPHONEOS_DEPLOYMENT_TARGET": MINIMUM_IOS_VERSION,
            "TARGETED_DEVICE_FAMILY": "1",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SUPPORTS_MACCATALYST": "NO",
            "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
        })
        settings.pop("INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad", None)

    app_info_path = PROJECT / "Sayso-Info.plist"
    app_info = plistlib.loads(app_info_path.read_bytes()) if app_info_path.exists() else {}
    app_info.update({
            "CFBundleURLTypes": [{
                "CFBundleTypeRole": "Editor",
                "CFBundleURLName": "solimanali.Sayso",
                "CFBundleURLSchemes": ["sayso"],
            }],
            "NSMicrophoneUsageDescription":
                "Sayso uses your microphone to turn your voice into text on this iPhone.",
        })
    with app_info_path.open("wb") as handle:
        plistlib.dump(app_info, handle, sort_keys=False)

    tests: list[tuple[str, str]] = []
    for name, product_type in [
        ("SaysoTests", "com.apple.product-type.bundle.unit-test"),
        ("SaysoUITests", "com.apple.product-type.bundle.ui-testing"),
    ]:
        (ROOT / name).mkdir(exist_ok=True)
        target_id = identifier(name + "/target")
        tests.append((name, target_id))
        group_id = identifier(name + "/group")
        product_id = identifier(name + "/product")
        config_list_id = identifier(name + "/configurations")
        proxy_id = identifier(name + "/proxy")
        dependency_id = identifier(name + "/dependency")
        objects[group_id] = {
            "isa": "PBXFileSystemSynchronizedRootGroup", "path": name, "sourceTree": "<group>"
        }
        objects[product_id] = {
            "isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle",
            "includeInIndex": "0", "path": name + ".xctest", "sourceTree": "BUILT_PRODUCTS_DIR"
        }
        phases = []
        for phase in ["Sources", "Frameworks", "Resources"]:
            phase_id = identifier(name + "/" + phase)
            phases.append(phase_id)
            objects[phase_id] = {
                "isa": "PBX" + phase + "BuildPhase", "buildActionMask": "2147483647",
                "files": [], "runOnlyForDeploymentPostprocessing": "0"
            }
        configurations = []
        for configuration in ["Debug", "Release"]:
            config_id = identifier(name + "/" + configuration)
            configurations.append(config_id)
            settings = {
                **app_versions(objects, app, configuration),
                "CODE_SIGN_STYLE": "Automatic",
                "GENERATE_INFOPLIST_FILE": "YES", "IPHONEOS_DEPLOYMENT_TARGET": MINIMUM_IOS_VERSION,
                "PRODUCT_BUNDLE_IDENTIFIER": "solimanali." + name,
                "PRODUCT_NAME": "$(TARGET_NAME)", "SWIFT_VERSION": "5.0",
                "SWIFT_EMIT_LOC_STRINGS": "NO", "TARGETED_DEVICE_FAMILY": "1",
                "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
                "SUPPORTS_MACCATALYST": "NO", "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
            }
            if name == "SaysoTests":
                settings.update({
                    "BUNDLE_LOADER": "$(TEST_HOST)",
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Sayso.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Sayso",
                })
            else:
                settings["TEST_TARGET_NAME"] = "Sayso"
            objects[config_id] = {
                "isa": "XCBuildConfiguration", "buildSettings": settings, "name": configuration
            }
        objects[config_list_id] = {
            "isa": "XCConfigurationList", "buildConfigurations": configurations,
            "defaultConfigurationIsVisible": "0", "defaultConfigurationName": "Release"
        }
        objects[proxy_id] = {
            "isa": "PBXContainerItemProxy", "containerPortal": data["rootObject"],
            "proxyType": "1", "remoteGlobalIDString": app_id, "remoteInfo": "Sayso"
        }
        objects[dependency_id] = {
            "isa": "PBXTargetDependency", "target": app_id, "targetProxy": proxy_id
        }
        objects[target_id] = {
            "isa": "PBXNativeTarget", "buildConfigurationList": config_list_id,
            "buildPhases": phases, "buildRules": [], "dependencies": [dependency_id],
            "fileSystemSynchronizedGroups": [group_id], "name": name,
            "packageProductDependencies": [], "productName": name,
            "productReference": product_id, "productType": product_type
        }
        append_once(main_group["children"], group_id)
        append_once(products["children"], product_id)
        append_once(project["targets"], target_id)
        project["attributes"]["TargetAttributes"][target_id] = {
            "CreatedOnToolsVersion": "26.6", "TestTargetID": app_id
        }

    PBXPROJ.write_text("// !$*UTF8*$!\n" + openstep(data) + "\n")

    def reference(parent: ET.Element, name: str, target_id: str) -> None:
        ET.SubElement(parent, "BuildableReference", {
            "BuildableIdentifier": "primary", "BlueprintIdentifier": target_id,
            "BuildableName": name + (".app" if name == "Sayso" else ".xctest"),
            "BlueprintName": name, "ReferencedContainer": "container:Sayso.xcodeproj"
        })

    scheme = ET.Element("Scheme", {"LastUpgradeVersion": "2660", "version": "1.7"})
    build = ET.SubElement(scheme, "BuildAction", {"parallelizeBuildables": "YES", "buildImplicitDependencies": "YES"})
    entries = ET.SubElement(build, "BuildActionEntries")
    for name, target_id in [("Sayso", app_id), *tests]:
        is_app = name == "Sayso"
        entry = ET.SubElement(entries, "BuildActionEntry", {
            "buildForTesting": "YES", "buildForRunning": "YES" if is_app else "NO",
            "buildForProfiling": "YES" if is_app else "NO", "buildForArchiving": "YES" if is_app else "NO",
            "buildForAnalyzing": "YES"
        })
        reference(entry, name, target_id)
    test_action = ET.SubElement(scheme, "TestAction", {
        "buildConfiguration": "Debug", "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
        "selectedLauncherIdentifier": "Xcode.IDEFoundation.Launcher.LLDB", "shouldUseLaunchSchemeArgsEnv": "YES"
    })
    testables = ET.SubElement(test_action, "Testables")
    for name, target_id in tests:
        testable = ET.SubElement(testables, "TestableReference", {"skipped": "NO", "parallelizable": "NO"})
        reference(testable, name, target_id)
    launch = ET.SubElement(scheme, "LaunchAction", {
        "buildConfiguration": "Debug", "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
        "selectedLauncherIdentifier": "Xcode.IDEFoundation.Launcher.LLDB", "launchStyle": "0",
        "useCustomWorkingDirectory": "NO", "ignoresPersistentStateOnLaunch": "NO",
        "debugDocumentVersioning": "YES", "debugServiceExtension": "internal", "allowLocationSimulation": "YES"
    })
    reference(ET.SubElement(launch, "BuildableProductRunnable", {"runnableDebuggingMode": "0"}), "Sayso", app_id)
    profile = ET.SubElement(scheme, "ProfileAction", {
        "buildConfiguration": "Release", "shouldUseLaunchSchemeArgsEnv": "YES", "savedToolIdentifier": "",
        "useCustomWorkingDirectory": "NO", "debugDocumentVersioning": "YES"
    })
    reference(ET.SubElement(profile, "BuildableProductRunnable", {"runnableDebuggingMode": "0"}), "Sayso", app_id)
    ET.SubElement(scheme, "AnalyzeAction", {"buildConfiguration": "Debug"})
    ET.SubElement(scheme, "ArchiveAction", {"buildConfiguration": "Release", "revealArchiveInOrganizer": "YES"})
    ET.indent(scheme, space="   ")
    schemes = PROJECT / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(scheme).write(schemes / "Sayso.xcscheme", encoding="UTF-8", xml_declaration=True)
    print("Configured Sayso, XCTest targets and shared scheme.")


if __name__ == "__main__":
    main()

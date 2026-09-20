#!/bin/zsh
# Verify the app and system appearances.
# --preflight-only records provenance without building or changing the simulator.
# Require iOS 27 by default for both SDKs and the selected simulator runtime.
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
cd "$TASK_ROOT"
SAYSO_PREFLIGHT_ONLY=0
if (( $# > 0 )); then
    if (( $# == 1 )) && [[ "$1" == "--preflight-only" ]]; then
        SAYSO_PREFLIGHT_ONLY=1
    else
        print -u2 "Usage: $0 [--preflight-only]"
        exit 64
    fi
fi
SAYSO_DEVICE="${SAYSO_SIMULATOR_ID:-358BDEE9-19AE-49BA-BC91-975523C2B8E7}"
export SAYSO_REQUIRED_IOS_MAJOR="${SAYSO_REQUIRED_IOS_MAJOR:-27}"
SAYSO_DERIVED_DATA=".build/ios27"
SAYSO_RUN="$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p .build
python3 - "$SAYSO_DEVICE" ".build/verification-$SAYSO_RUN-provenance.json" <<'PY'
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

device_id, output_path = sys.argv[1:]
report = {
    "recordedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "requiredIOSMajor": os.environ.get("SAYSO_REQUIRED_IOS_MAJOR") or None,
    "requestedSimulatorID": device_id,
    "developerDirectoryOverride": os.environ.get("DEVELOPER_DIR"),
    "validationErrors": [],
}

def read(*arguments):
    result = subprocess.run(arguments, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError("{}: {}".format(" ".join(arguments), result.stderr.strip()))
    return result.stdout.strip()

try:
    # xcrun and xcodebuild inherit DEVELOPER_DIR, just as the verification below does.
    report["xcode"] = {
        "version": read("xcodebuild", "-version"),
        "executable": read("xcrun", "--find", "xcodebuild"),
        "selectedDeveloperDirectory": read("xcode-select", "--print-path"),
    }
    report["host"] = {
        "version": read("sw_vers", "-productVersion"),
        "build": read("sw_vers", "-buildVersion"),
        "architecture": platform.machine(),
    }
    report["sdks"] = {
        sdk: {
            "version": read("xcrun", "--sdk", sdk, "--show-sdk-version"),
            "build": read("xcrun", "--sdk", sdk, "--show-sdk-build-version"),
            "path": read("xcrun", "--sdk", sdk, "--show-sdk-path"),
        } for sdk in ("iphonesimulator", "iphoneos")
    }
    devices = json.loads(read("xcrun", "simctl", "list", "devices", "--json"))["devices"]
    matches = [(runtime_id, device) for runtime_id, entries in devices.items()
               for device in entries if device.get("udid") == device_id]
    if len(matches) != 1:
        raise RuntimeError("The selected simulator UUID does not identify one installed device.")
    runtime_id, device = matches[0]
    runtimes = json.loads(read("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
    runtime = next((item for item in runtimes if item.get("identifier") == runtime_id), None)
    report["simulator"] = {key: device.get(key) for key in
                           ("udid", "name", "state", "isAvailable", "deviceTypeIdentifier")}
    report["runtime"] = ({key: runtime.get(key) for key in
                           ("identifier", "name", "version", "buildversion", "isAvailable")}
                         if runtime else {"identifier": runtime_id})
    if not runtime or not runtime_id.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
        report["validationErrors"].append("The selected device needs an installed iOS runtime.")
    if not device.get("isAvailable") or not runtime or not runtime.get("isAvailable"):
        report["validationErrors"].append("The selected simulator/runtime is unavailable.")

    files = {}
    for directory in ("Sayso", "SaysoTests", "SaysoUITests", "Sayso.xcodeproj", "scripts"):
        for path in sorted(Path(directory).rglob("*")):
            if path.is_file() and not ({"__pycache__", "xcuserdata", ".DS_Store"} & set(path.parts)):
                files[path.as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    report["source"] = {
        "root": str(Path.cwd()),
        "fileSHA256": files,
        "manifestSHA256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest(),
    }
    git = subprocess.run(["git", "rev-parse", "--is-inside-work-tree"], text=True, capture_output=True)
    if git.returncode == 0 and git.stdout.strip() == "true":
        report["source"]["gitHEAD"] = read("git", "rev-parse", "HEAD")
        report["source"]["gitStatus"] = read("git", "status", "--porcelain")

    required = report["requiredIOSMajor"]
    if required is not None:
        if not re.fullmatch(r"[1-9][0-9]*", required):
            report["validationErrors"].append("SAYSO_REQUIRED_IOS_MAJOR must be a positive integer.")
        else:
            versions = {name + " SDK": value["version"] for name, value in report["sdks"].items()}
            versions["selected simulator runtime"] = report["runtime"].get("version", "unavailable")
            for name, version in versions.items():
                if version.split(".")[0] != required:
                    report["validationErrors"].append("{} is {}; required iOS major {}.".format(name, version, required))
except Exception as error:
    report["validationErrors"].append(str(error))

report["preflightPassed"] = not report["validationErrors"]
Path(output_path).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print("Verification provenance: " + output_path)
for error in report["validationErrors"]:
    print("Preflight failed: " + error, file=sys.stderr)
sys.exit(0 if report["preflightPassed"] else 1)
PY
if (( SAYSO_PREFLIGHT_ONLY )); then
    print "Preflight passed. No build or simulator settings changes performed."
    exit 0
fi
xcrun simctl bootstatus "$SAYSO_DEVICE" -b
SAYSO_ORIGINAL_APPEARANCE="$(xcrun simctl ui "$SAYSO_DEVICE" appearance)"
SAYSO_ORIGINAL_TEXT_SIZE="$(xcrun simctl ui "$SAYSO_DEVICE" content_size)"
restore_environment() {
    xcrun simctl ui "$SAYSO_DEVICE" appearance "$SAYSO_ORIGINAL_APPEARANCE" >/dev/null 2>&1 || true
    xcrun simctl ui "$SAYSO_DEVICE" content_size "$SAYSO_ORIGINAL_TEXT_SIZE" >/dev/null 2>&1 || true
}
trap restore_environment EXIT INT TERM

xcrun simctl ui "$SAYSO_DEVICE" content_size large
xcrun simctl ui "$SAYSO_DEVICE" appearance light
xcrun simctl privacy "$SAYSO_DEVICE" revoke microphone solimanali.Sayso
xcodebuild test -project Sayso.xcodeproj -scheme Sayso \
    -destination "platform=iOS Simulator,id=$SAYSO_DEVICE" \
    -derivedDataPath "$SAYSO_DERIVED_DATA" -resultBundlePath ".build/Verification-$SAYSO_RUN-Light.xcresult" \
    -parallel-testing-enabled NO -jobs 2 -collect-test-diagnostics never \
    -skip-testing:SaysoUITests/SaysoUITests/testDarkAppearanceKeepsRecordingActionAccessible \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- > ".build/verification-$SAYSO_RUN-light.log" 2>&1

xcrun simctl ui "$SAYSO_DEVICE" appearance dark
xcodebuild test-without-building -project Sayso.xcodeproj -scheme Sayso \
    -destination "platform=iOS Simulator,id=$SAYSO_DEVICE" \
    -derivedDataPath "$SAYSO_DERIVED_DATA" -resultBundlePath ".build/Verification-$SAYSO_RUN-Dark.xcresult" \
    -parallel-testing-enabled NO -jobs 2 -collect-test-diagnostics never \
    -only-testing:SaysoUITests/SaysoUITests/testDarkAppearanceKeepsRecordingActionAccessible \
    -only-testing:SaysoUITests/DesignLanguageUITests \
    -only-testing:SaysoUITests/ReimaginedAppUITests \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- > ".build/verification-$SAYSO_RUN-dark.log" 2>&1
restore_environment

xcodebuild build -project Sayso.xcodeproj -scheme Sayso \
    -destination 'generic/platform=iOS' -configuration Release -derivedDataPath "$SAYSO_DERIVED_DATA" -jobs 2 \
    CODE_SIGNING_ALLOWED=NO > ".build/verification-$SAYSO_RUN-release.log" 2>&1
print "Verification passed. Result bundles and logs: .build/Verification-$SAYSO_RUN-*"

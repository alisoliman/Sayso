#!/bin/bash
set -euo pipefail

# These runners execute production macOS 27 APIs on the Mac host.
# Selecting Xcode 27 does not upgrade the host runtime.
if ! sayso_host_version="$(/usr/bin/sw_vers -productVersion)"; then
  printf '%s\n' 'Cannot determine the Mac host version; macOS 27 or later is required.' >&2
  exit 2
fi
sayso_host_major="${sayso_host_version%%.*}"
if [[ ! "$sayso_host_major" =~ ^[0-9]+$ ]] || (( 10#$sayso_host_major < 27 )); then
  printf 'macOS 27 or later is required to run this production harness; this Mac is running %s. No compilation or evaluation was started.\n' "$sayso_host_version" >&2
  exit 2
fi
if ! sayso_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"; then
  printf '%s\n' 'Cannot resolve the selected macOS SDK; select a completed Xcode installation with macOS SDK 27 or later.' >&2
  exit 2
fi
sayso_sdk_major="${sayso_sdk_version%%.*}"
if [[ ! "$sayso_sdk_major" =~ ^[0-9]+$ ]] || (( 10#$sayso_sdk_major < 27 )); then
  printf 'macOS SDK 27 or later is required; the selected SDK is %s. No compilation or evaluation was started.\n' "$sayso_sdk_version" >&2
  exit 2
fi

sayso_root="$(cd "$(dirname "$0")/.." && pwd)"
sayso_build_dir="$(mktemp -d "${TMPDIR:-/tmp}/sayso-intelligence.XXXXXX")"
trap 'rm -rf "$sayso_build_dir"' EXIT

export SAYSO_EVALUATION_SDK="$sayso_sdk_version"
export SAYSO_EVALUATION_XCODE="$(xcodebuild -version)"
export SAYSO_EVALUATION_SOURCE_SHA256="$(shasum -a 256 "$sayso_root/Sayso/Services/IntelligenceService.swift" | awk '{print $1}')"
sayso_sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
sayso_arch="$(uname -m)"

# This exercises the same service on a Mac with a real local Apple Intelligence model.
# It is separate from the simulator unit tests and does not validate the iPhone model.
xcrun swiftc \
  -sdk "$sayso_sdk_path" \
  -target "$sayso_arch-apple-macos27.0" \
  -swift-version 5 \
  -default-isolation MainActor \
  "$sayso_root/Sayso/Services/IntelligenceService.swift" \
  "$sayso_root/scripts/IntelligenceEvaluation.swift" \
  -o "$sayso_build_dir/evaluate"

"$sayso_build_dir/evaluate" "$@"

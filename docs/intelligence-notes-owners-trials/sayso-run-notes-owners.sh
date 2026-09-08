#!/bin/bash
set -euo pipefail
trial_source="$1"
trial_output="$2"
trial_repeats="${3:-1}"
trial_root="/Users/ali/Dev/pet-projects/Sayso"
trial_build="$(mktemp -d /tmp/sayso-notes-owners.XXXXXX)"
trap 'rm -rf "$trial_build"' EXIT
export SAYSO_EVALUATION_SDK="$(xcrun --sdk macosx --show-sdk-version)"
export SAYSO_EVALUATION_XCODE="$(xcodebuild -version)"
export SAYSO_EVALUATION_SOURCE_SHA256="$(shasum -a 256 "$trial_source" | awk '{print $1}')"
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target arm64-apple-macos26.5 -swift-version 5 -default-isolation MainActor "$trial_source" "$trial_root/scripts/IntelligenceEvaluation.swift" -o "$trial_build/evaluate"
"$trial_build/evaluate" --fixtures /tmp/sayso-notes-owners-fixtures.json --repeat "$trial_repeats" --output "$trial_output"

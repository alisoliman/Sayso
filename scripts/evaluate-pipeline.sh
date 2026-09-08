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
sayso_pipeline_build="$(mktemp -d "${TMPDIR:-/tmp}/sayso-pipeline-build.XXXXXX")"
trap 'rm -rf "$sayso_pipeline_build"' EXIT

export SAYSO_EVALUATION_SDK="$sayso_sdk_version"
export SAYSO_EVALUATION_XCODE="$(xcodebuild -version)"
export SAYSO_EVALUATION_ARCH="$(uname -m)"
export SAYSO_INTELLIGENCE_SHA256="$(shasum -a 256 "$sayso_root/Sayso/Services/IntelligenceService.swift" | cut -d ' ' -f 1)"
sayso_pipeline_sdk="$(xcrun --sdk macosx --show-sdk-path)"

# Use the production accumulator without importing the iOS microphone service.
python3 - "$sayso_root" "$sayso_pipeline_build" <<'PY'
from pathlib import Path
import sys

repo, output = map(Path, sys.argv[1:])
source = (repo / 'Sayso/Services/SpeechService.swift').read_text()
start = source.index('nonisolated struct SpeechTranscriptAccumulator')
end = source.index('nonisolated enum SpeechServiceError', start)
(output / 'TranscriptAccumulator.swift').write_text(
    'import Foundation\nimport Speech\nimport CoreMedia\n\n' + source[start:end]
)
PY

xcrun swiftc \
  -sdk "$sayso_pipeline_sdk" \
  -target "$SAYSO_EVALUATION_ARCH-apple-macos27.0" \
  -swift-version 5 \
  -default-isolation MainActor \
  "$sayso_root/Sayso/Services/IntelligenceService.swift" \
  "$sayso_pipeline_build/TranscriptAccumulator.swift" \
  "$sayso_root/scripts/PipelineEvaluation.swift" \
  -o "$sayso_pipeline_build/evaluate"

"$sayso_pipeline_build/evaluate" "$@"

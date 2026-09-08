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

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
validation_dir="$(mktemp -d -t sayso-speech-checks)"
trap 'rm -rf "$validation_dir"' EXIT

# Compile the actual production accumulator without the iOS-only microphone
# service. This keeps the fast macOS checks on exactly the app's implementation.
python3 - "$repo_dir" "$validation_dir" <<'PY'
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

xcrun swiftc -swift-version 6 -strict-concurrency=complete \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -target "$(uname -m)-apple-macos27.0" \
    "$repo_dir/Sayso/Services/SpeechAudioConverter.swift" \
    "$validation_dir/TranscriptAccumulator.swift" \
    "$repo_dir/scripts/SpeechHelperChecks.swift" \
    -o "$validation_dir/checks"
"$validation_dir/checks"

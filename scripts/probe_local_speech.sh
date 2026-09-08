#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
probe_dir="$(mktemp -d -t sayso-local-speech)"
trap 'rm -rf "$probe_dir"' EXIT

python3 - "$repo_dir" "$probe_dir" <<'PY'
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
    -target "$(uname -m)-apple-macos26.0" \
    "$probe_dir/TranscriptAccumulator.swift" \
    "$repo_dir/scripts/LocalSpeechProbe.swift" \
    -o "$probe_dir/probe"

fixture_text="Please send the meeting notes tomorrow morning. Keep the message clear and friendly."
say -v Samantha -o "$probe_dir/fixture.caf" "$fixture_text"
"$probe_dir/probe" "$probe_dir/fixture.caf" "$fixture_text"

#!/bin/zsh
# Record native simulator UI transitions with the DEBUG-only scripted speech fixture.
# This is interaction evidence, not recognition or model-quality evidence.
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
cd "$TASK_ROOT"
SAYSO_DEVICE="${SAYSO_SIMULATOR_ID:-358BDEE9-19AE-49BA-BC91-975523C2B8E7}"
SAYSO_DERIVED_DATA=".build/ios27"
SAYSO_RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
SAYSO_VIDEO="docs/demos/recording-interaction-ios27-$SAYSO_RUN_ID.mp4"
SAYSO_RESULT_BUNDLE="$SAYSO_DERIVED_DATA/Recording-Interaction-iOS27-$SAYSO_RUN_ID.xcresult"
SAYSO_VIDEO_LOG="$SAYSO_DERIVED_DATA/demo-ios27-$SAYSO_RUN_ID-video.log"
SAYSO_TEST_LOG="$SAYSO_DERIVED_DATA/demo-ios27-$SAYSO_RUN_ID-test.log"
mkdir -p docs/demos "$SAYSO_DERIVED_DATA"

# Select Xcode 27 or later through DEVELOPER_DIR and build-for-testing into
# .build/ios27 first. test-without-building uses those verified app/test binaries.
# Each run gets separate iOS 27 evidence paths, preserving earlier recordings.
printf 'Video: %s\nResult bundle: %s\nVideo log: %s\nTest log: %s\n' \
    "$SAYSO_VIDEO" "$SAYSO_RESULT_BUNDLE" "$SAYSO_VIDEO_LOG" "$SAYSO_TEST_LOG"
xcrun simctl io "$SAYSO_DEVICE" recordVideo --codec=h264 "$SAYSO_VIDEO" > "$SAYSO_VIDEO_LOG" 2>&1 &
SAYSO_VIDEO_PID=$!
finish_video() {
    kill -INT "$SAYSO_VIDEO_PID" 2>/dev/null || true
    wait "$SAYSO_VIDEO_PID" 2>/dev/null || true
}
trap finish_video EXIT INT TERM
xcodebuild test-without-building -project Sayso.xcodeproj -scheme Sayso \
    -destination "platform=iOS Simulator,id=$SAYSO_DEVICE" \
    -derivedDataPath "$SAYSO_DERIVED_DATA" -parallel-testing-enabled NO \
    -resultBundlePath "$SAYSO_RESULT_BUNDLE" \
    -only-testing:SaysoUITests/SaysoUITests/testScriptedRecordingFinishingRefinementAndResult \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- > "$SAYSO_TEST_LOG" 2>&1

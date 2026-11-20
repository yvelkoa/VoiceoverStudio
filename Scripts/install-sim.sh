#!/bin/zsh
# Reinstall the last debug build on the booted simulator and launch it.
# Pass a video path to load it and open the recorder straight away (DEBUG builds only).
set -e
# Ask Xcode where this checkout builds to: another checkout or worktree of the project has its own
# DerivedData folder, and picking "the first one found" installs that one's app instead.
cd "$(dirname "$0")/.."
APP="$(xcodebuild -project VoiceoverStudio.xcodeproj -scheme VoiceoverStudio -sdk iphonesimulator \
  -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')/VoiceoverStudio.app"
[ -d "$APP" ] || { echo "No build at $APP; build first."; exit 1; }
BUNDLE=beav.dev.VoiceoverStudio
# Installs what is already built: build first (Xcode, or `xcodebuild build`), or this launches a stale app.
xcrun simctl terminate booted $BUNDLE 2>/dev/null || true
xcrun simctl install booted "$APP"
xcrun simctl privacy booted grant microphone $BUNDLE >/dev/null
if [ -n "$1" ]; then
  SIMCTL_CHILD_VOICEOVER_DEBUG_VIDEO="$1" xcrun simctl launch booted $BUNDLE >/dev/null
else
  xcrun simctl launch booted $BUNDLE >/dev/null
fi
echo "launched"

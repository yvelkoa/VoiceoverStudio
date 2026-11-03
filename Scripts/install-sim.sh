#!/bin/zsh
# Reinstall the last debug build on the booted simulator and launch it.
# Pass a video path to load it and open the recorder straight away (DEBUG builds only).
set -e
APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*VoiceoverStudio*' -name 'VoiceoverStudio.app' \
  -path '*Build/Products/Debug-iphonesimulator*' -not -path '*Index.noindex*' | head -1)
BUNDLE=beav.dev.VoiceoverStudio
xcrun simctl terminate booted $BUNDLE 2>/dev/null || true
xcrun simctl install booted "$APP"
xcrun simctl privacy booted grant microphone $BUNDLE >/dev/null
if [ -n "$1" ]; then
  SIMCTL_CHILD_VOICEOVER_DEBUG_VIDEO="$1" xcrun simctl launch booted $BUNDLE >/dev/null
else
  xcrun simctl launch booted $BUNDLE >/dev/null
fi
echo "launched"

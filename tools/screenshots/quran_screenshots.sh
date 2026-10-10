#!/bin/bash
# Screenshots of the Quran mushaf pages (and the launch animation) from the iOS Simulator, for
# a visual review in CI (artifact `quran-screenshots`). Simulator captures, not a device test.
#
# Usage: quran_screenshots.sh <path to the simulator .app> <output directory>
set -euo pipefail
APP="$1"
OUT="$2"
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
mkdir -p "$OUT"

# The newest available iPhone simulator.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
phones = [(runtime, d) for runtime, ds in devices.items() if "iOS" in runtime for d in ds if d["name"].startswith("iPhone")]
phones.sort(key=lambda p: (p[0], "Pro" in p[1]["name"] and "Max" not in p[1]["name"]))
print(phones[-1][1]["udid"])')
echo "Simulator: $(xcrun simctl list devices | grep "$UDID")"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"

# A saved reading position (the JSON QuranReadingPosition stores), as hex for `defaults -data`.
position() {
  printf '{"ayah":%d,"savedAt":800000000,"surah":%d,"version":1}' "$2" "$1" | xxd -p | tr -d '\n'
}

shot() { # name appearance surah ayah style [full]
  local name=$1 appearance=$2 surah=$3 ayah=$4 style=$5 full=${6:-false}
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE" quran.readingMode mushaf
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE" quran.mushafStyle "$style"
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE" quran.mushafFullScreen -bool "$full"
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE" quran.position.v1 -data "$(position "$surah" "$ayah")"
  xcrun simctl openurl "$UDID" "azkarapp://quran"
  sleep 9
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
  echo "wrote $name.png"
}

# The launch animation, part way through.
xcrun simctl ui "$UDID" appearance light
xcrun simctl launch "$UDID" "$BUNDLE"
sleep 1.2
xcrun simctl io "$UDID" screenshot "$OUT/00-launch-animation-light.png"
sleep 5

shot 01-page-001-fatiha-light light 1 1 printed
shot 02-page-042-light light 2 255 printed
shot 03-page-305-maryam-light light 19 1 printed
shot 04-page-305-maryam-dark dark 19 1 printed
shot 05-page-604-dark dark 112 1 printed
shot 06-page-305-flowing-light light 19 1 flowing
shot 07-page-042-full-screen-light light 2 255 printed true
shot 08-page-305-full-screen-dark dark 19 1 printed true
ls -l "$OUT"

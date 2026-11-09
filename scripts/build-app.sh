#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
swift build -c release --product MFish
BIN=$(swift build -c release --show-bin-path)
mkdir -p dist
STAGE=$(mktemp -d "$ROOT/dist/.MFish.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/MFish.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/MFish" "$APP/Contents/MacOS/MFish"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleExecutable</key><string>MFish</string>
<key>CFBundleIdentifier</key><string>local.mfish.MFish</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>MFish</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
# Only replace the generated bundle after a successful build and signature check.
rm -rf "$ROOT/dist/MFish.app"
mv "$APP" "$ROOT/dist/MFish.app"
printf '已生成 %s/dist/MFish.app\n' "$ROOT"
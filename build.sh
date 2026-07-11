#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
SCRATCH_PATH="${SCRATCH_PATH:-$ROOT/.build}"
SCRATCH_PATH="${SCRATCH_PATH:A}"
APP_PATH="$ROOT/OrbitSwitch.app"
CONFIGURATION="${CONFIGURATION:-release}"
BUILD_ARCH="${BUILD_ARCH:-native}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
APP_VERSION="${APP_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

case "$SCRATCH_PATH" in
  "$ROOT"/*) ;;
  *) print -u2 "SCRATCH_PATH must stay inside the repository: $ROOT"; exit 2 ;;
esac

export CLANG_MODULE_CACHE_PATH="$SCRATCH_PATH/module-cache/clang"
export SWIFT_MODULE_CACHE_PATH="$SCRATCH_PATH/module-cache/swift"
export SWIFTPM_MODULECACHE_OVERRIDE="$SCRATCH_PATH/module-cache/swiftpm"
export HOME="$SCRATCH_PATH/home"
export TMPDIR="$SCRATCH_PATH/tmp"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" "$HOME" "$TMPDIR"

ARCH_ARGS=()
case "$BUILD_ARCH" in
  native) ;;
  arm64|x86_64) ARCH_ARGS=(--arch "$BUILD_ARCH") ;;
  universal) ARCH_ARGS=(--arch arm64 --arch x86_64) ;;
  *) print -u2 "BUILD_ARCH must be native, arm64, x86_64, or universal"; exit 2 ;;
esac

swift build \
  --disable-sandbox \
  --package-path "$ROOT" \
  --scratch-path "$SCRATCH_PATH" \
  --cache-path "$SCRATCH_PATH/swiftpm-cache" \
  --config-path "$SCRATCH_PATH/swiftpm-config" \
  --security-path "$SCRATCH_PATH/swiftpm-security" \
  "${ARCH_ARGS[@]}" \
  --configuration "$CONFIGURATION" \
  --product OrbitSwitch

BIN_PATH="$(swift build --disable-sandbox --package-path "$ROOT" --scratch-path "$SCRATCH_PATH" --cache-path "$SCRATCH_PATH/swiftpm-cache" --config-path "$SCRATCH_PATH/swiftpm-config" --security-path "$SCRATCH_PATH/swiftpm-security" "${ARCH_ARGS[@]}" --configuration "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/OrbitSwitch" "$APP_PATH/Contents/MacOS/OrbitSwitch"
cp "$ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
chmod +x "$APP_PATH/Contents/MacOS/OrbitSwitch"
/usr/bin/strip -S "$APP_PATH/Contents/MacOS/OrbitSwitch"

plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP_PATH/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

CODESIGN_ARGS=(--force --sign "$SIGNING_IDENTITY" --timestamp=none)
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  plutil -replace OrbitSwitchSigningMode -string ad-hoc "$APP_PATH/Contents/Info.plist"
else
  CODESIGN_ARGS+=(--options runtime)
  plutil -replace OrbitSwitchSigningMode -string stable-identity "$APP_PATH/Contents/Info.plist"
fi
codesign "${CODESIGN_ARGS[@]}" "$APP_PATH"
plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP_PATH"
print "Built $APP_PATH"

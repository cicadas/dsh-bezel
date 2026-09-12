#!/bin/sh
# Build the SwiftPM executable and assemble it into a .app bundle.
#
# The bundle is what makes ATS exceptions, the bundle identifier, and a stable
# WebKit data store apply; `swift run` alone launches a bare executable.
set -eu

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/DSH Bezel.app"

# --disable-sandbox: the DSH harness cannot nest a sandbox of its own, and the
# flag only skips SwiftPM's build sandbox, so it is harmless in a plain
# terminal as well.
swift build -c "$CONFIG" --disable-sandbox
BIN_DIR="$(swift build -c "$CONFIG" --disable-sandbox --show-bin-path)"

[ -f Resources/AppIcon.icns ] || {
    echo "make-app: Resources/AppIcon.icns is missing; it is a committed artifact, restore it from the repository" >&2
    exit 1
}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/dsh-bezel" "$APP/Contents/MacOS/dsh-bezel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# One .lproj per supported language: their presence is what lets macOS render
# the standard menus in the app's chosen language (see
# mirrorLanguageIntoAppleLanguages in BezelApp.swift).
for lproj in Resources/localizations/*.lproj; do
    name="$(basename "$lproj")"
    mkdir -p "$APP/Contents/Resources/$name"
    cp "$lproj"/*.strings "$APP/Contents/Resources/$name/"
done

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed; the bundle still runs locally"
echo "built $APP"

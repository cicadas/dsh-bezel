#!/bin/sh
# Assemble the distributable release: a universal .app bundle, a DMG, and a
# zip, all stamped with the version from Resources/Info.plist.
#
# Signing: with no Developer ID certificate installed the bundle is signed
# ad-hoc (--options runtime keeps the notarizable shape). Gatekeeper on
# another machine will ask for a right-click > Open the first launch. Once a
# real identity exists, run with
#   CODESIGN_IDENTITY="Developer ID Application: ..." scripts/make-release.sh
# and the same script produces a properly signed build ready for notarization.
set -eu

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/DSH Bezel.app"
OUT="build/release"
VOL="DSH Bezel"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="$OUT/DSH-Bezel-$VERSION.dmg"
ZIP="$OUT/DSH-Bezel-$VERSION.zip"
IDENTITY="${CODESIGN_IDENTITY:--}"

# --disable-sandbox: the DSH harness cannot nest a sandbox of its own, and the
# flag only skips SwiftPM's build sandbox, so it is harmless in a plain
# terminal as well.
#
# The two arches are built as separate --triple invocations and merged with
# lipo: the multi-arch --arch route drives the Xcode build system, whose
# out-of-process macro plugin server cannot run in this environment. Note
# that .build/release is a symlink that follows whichever triple was built
# last, so the per-triple paths below are the only stable ones to read from.
swift build -c "$CONFIG" --triple arm64-apple-macosx --disable-sandbox
swift build -c "$CONFIG" --triple x86_64-apple-macosx --disable-sandbox
BIN_ARM=".build/arm64-apple-macosx/$CONFIG/dsh-bezel"
BIN_X86=".build/x86_64-apple-macosx/$CONFIG/dsh-bezel"

[ -f Resources/AppIcon.icns ] || {
    echo "make-release: Resources/AppIcon.icns is missing; it is a committed artifact, restore it from the repository" >&2
    exit 1
}

# ---- .app bundle ---------------------------------------------------------

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$BIN_ARM" "$BIN_X86" -output "$APP/Contents/MacOS/dsh-bezel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$IDENTITY" --options runtime "$APP"
codesign --verify --strict "$APP"

# ---- DMG and zip ---------------------------------------------------------

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/DSH Bezel.app"
ln -s /Applications "$STAGE/Applications"
# Strip local extended attributes (provenance etc.) from the payload; the
# code signature lives inside the Mach-O and is unaffected.
xattr -cr "$STAGE/DSH Bezel.app"

mkdir -p "$OUT"
rm -f "$DMG" "$ZIP" "$OUT/DSH-Bezel-$VERSION.sha256"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$STAGE/DSH Bezel.app" "$ZIP"

# ---- verify the DMG payload matches the bundle byte for byte -------------

MNT="$STAGE/mount"
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" >/dev/null
codesign --verify --strict "$MNT/DSH Bezel.app"
cmp -s "$MNT/DSH Bezel.app/Contents/MacOS/dsh-bezel" "$APP/Contents/MacOS/dsh-bezel"
[ -L "$MNT/Applications" ]
hdiutil detach "$MNT" >/dev/null

# ---- checksums -----------------------------------------------------------

(
    cd "$OUT"
    shasum -a 256 "DSH-Bezel-$VERSION.dmg" "DSH-Bezel-$VERSION.zip" > "DSH-Bezel-$VERSION.sha256"
)

echo "release $VERSION:"
ls -lh "$DMG" "$ZIP" "$OUT/DSH-Bezel-$VERSION.sha256" | awk '{print "  " $NF " (" $5 ")"}'
echo "built $APP (universal), $DMG, $ZIP"

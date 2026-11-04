#!/usr/bin/env bash
# Construit « build/KEF Remote.app » : compilation release, bundle, icône, signature ad hoc.
#
#   ./build-app.sh            # architecture native
#   UNIVERSAL=1 ./build-app.sh  # binaire universel arm64 + x86_64
#
# L'app n'est PAS copiée dans /Applications (glisser-déposer manuel, cf. README).
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="KEF Remote"
EXEC_NAME="KEFRemote"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Compilation (release)"
swift build -c release --product "$EXEC_NAME" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release --show-bin-path ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})"

mkdir -p "$BUILD_DIR"
ICNS="$BUILD_DIR/AppIcon.icns"
if [[ ! -f "$ICNS" || scripts/make-icon.swift -nt "$ICNS" ]]; then
  echo "==> Génération de l'icône"
  swift scripts/make-icon.swift "$BUILD_DIR"
fi

echo "==> Assemblage du bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXEC_NAME" "$APP/Contents/MacOS/$EXEC_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Numéro de build : date, pour distinguer les versions successives.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M)" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Signature ad hoc"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> OK : $APP"

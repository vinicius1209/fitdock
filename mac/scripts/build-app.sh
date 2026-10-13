#!/usr/bin/env bash
# Gera Build/FitDock.app (assinatura ad-hoc). Uso: ./scripts/build-app.sh [--install]
# --install copia para /Applications.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="FitDock"
BUNDLE_ID="dev.vinimachado.fitdock"
BUILD_DIR="$ROOT_DIR/Build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

cd "$ROOT_DIR"
swift build -c release --product "$APP_NAME"
BIN="$ROOT_DIR/.build/release/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Ícone do app (o app vive na barra de menus, sem ícone no Dock).
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
"$BIN" --render-icon "$BUILD_DIR/icon-1024.png" 1024
for size in 16 32 128 256 512; do
    sips -z $size $size "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$BUILD_DIR/icon-1024.png"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>pt_BR</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>O FitDock recebe seus passos e batimentos do celular pela rede de casa.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_fitdock._tcp</string>
    </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
echo "App gerado em: $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_DIR" /Applications/
    echo "Instalado em /Applications/$APP_NAME.app"
fi

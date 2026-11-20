#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
VERSION="0.1.0"
BUILD_NUMBER="1"
BUNDLE_ID="com.gorkemsay.Titiz"
SKIP_BUILD=false
RUN_CODESIGN=true
CREATE_ZIP=true
CREATE_DMG=true

usage() {
  cat <<'EOF'
Usage: scripts/bundle-app.sh [options]

Options:
  --version <ver>    Bundle marketing version (default: 0.1.0)
  --build <num>      Bundle build number (default: 1)
  --skip-build       Skip `swift build -c release --product TitizApp`
  --no-codesign      Skip ad-hoc `codesign --force --deep --sign -`
  --no-zip           Skip .zip archive creation
  --no-dmg           Skip .dmg image creation
  -h, --help         Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --no-codesign)
      RUN_CODESIGN=false
      shift
      ;;
    --no-zip)
      CREATE_ZIP=false
      shift
      ;;
    --no-dmg)
      CREATE_DMG=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cd "${ROOT_DIR}"

if [[ "${SKIP_BUILD}" != true ]]; then
  echo "==> Building TitizApp (Release)..."
  swift build -c release --product TitizApp
fi

BIN_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="${BIN_DIR}/TitizApp"
RESOURCE_BUNDLE_PATH="${BIN_DIR}/Titiz_TitizCore.bundle"

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "Error: Release executable not found at ${EXECUTABLE_PATH}" >&2
  exit 1
fi

if [[ ! -d "${RESOURCE_BUNDLE_PATH}" ]]; then
  echo "Error: Resource bundle not found at ${RESOURCE_BUNDLE_PATH}" >&2
  exit 1
fi

APP_PATH="${DIST_DIR}/Titiz.app"
CONTENTS_DIR="${APP_PATH}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Assembling ${APP_PATH}..."
rm -rf "${APP_PATH}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/TitizApp"
chmod +x "${MACOS_DIR}/TitizApp"
ditto "${RESOURCE_BUNDLE_PATH}" "${RESOURCES_DIR}/Titiz_TitizCore.bundle"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>tr</string>
    <key>CFBundleDisplayName</key>
    <string>Titiz</string>
    <key>CFBundleExecutable</key>
    <string>TitizApp</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Titiz</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Görkem Say. MIT License.</string>
</dict>
</plist>
EOF

printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"
plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null

if [[ "${RUN_CODESIGN}" == true ]]; then
  echo "==> Ad-hoc signing ${APP_PATH}..."
  codesign --force --deep --sign - "${APP_PATH}"
  codesign --verify --deep --strict "${APP_PATH}"
fi

ZIP_PATH="${DIST_DIR}/Titiz-${VERSION}-macOS.zip"
DMG_PATH="${DIST_DIR}/Titiz-${VERSION}-macOS.dmg"

if [[ "${CREATE_ZIP}" == true ]]; then
  echo "==> Creating ${ZIP_PATH}..."
  rm -f "${ZIP_PATH}"
  ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
fi

if [[ "${CREATE_DMG}" == true ]]; then
  echo "==> Creating ${DMG_PATH}..."
  rm -f "${DMG_PATH}"
  DMG_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/titiz-dmg.XXXXXX")"
  trap 'rm -rf "${DMG_STAGING}"' EXIT
  ditto "${APP_PATH}" "${DMG_STAGING}/Titiz.app"
  ln -s /Applications "${DMG_STAGING}/Applications"
  hdiutil create \
    -volname "Titiz" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null
fi

echo "==> Done! Packaged release artifacts:"
ls -lh "${DIST_DIR}"
if [[ -f "${ZIP_PATH}" ]]; then
  shasum -a 256 "${ZIP_PATH}"
fi
if [[ -f "${DMG_PATH}" ]]; then
  shasum -a 256 "${DMG_PATH}"
fi

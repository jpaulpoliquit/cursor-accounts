#!/usr/bin/env bash
# Build Cursor Accounts (Release) and write dist/Cursor-Accounts-0.0.1.dmg
# with the .app, an /Applications symlink, and a short Read Me.
# Set APP_PATH to an existing Cursor Accounts.app to skip xcodebuild.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT_DISPLAY="Cursor Accounts"
APP_NAME="Cursor Accounts.app"
EXECUTABLE="Cursor Accounts"
SCHEME="Cursor Accounts"
CONFIGURATION="Release"
VERSION="${VERSION:-0.0.1}"
VOL_NAME="Cursor Accounts"
DIST_DIR="${ROOT}/dist"
DMG_NAME="Cursor-Accounts-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
DERIVED="${ROOT}/.build/package-DerivedData"
LOG="${DERIVED}/xcodebuild-release.log"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/cursor-accounts-dmg.XXXXXX")"
CONTENT="${WORK}/content"
RW_DMG="${WORK}/rw.dmg"
MOUNT=""

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${MOUNT}" && -d "${MOUNT}" ]]; then
    hdiutil detach "${MOUNT}" -quiet || true
  fi
  if [[ -d "/Volumes/${VOL_NAME}" ]]; then
    hdiutil detach "/Volumes/${VOL_NAME}" -quiet || true
  fi
  rm -rf "${WORK}"
}
trap cleanup EXIT

if [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

need_xcodegen() {
  if [[ ! -f "${ROOT}/project.yml" ]]; then
    return 1
  fi
  if [[ ! -f "${ROOT}/CursorBar.xcodeproj/project.pbxproj" ]]; then
    return 0
  fi
  if [[ -n "$(find Sources Tests project.yml -type f -newer CursorBar.xcodeproj/project.pbxproj 2>/dev/null | head -1)" ]]; then
    return 0
  fi
  return 1
}

plist_string() {
  /usr/libexec/PlistBuddy -c "Print :${2}" "${1}/Contents/Info.plist" 2>/dev/null || true
}

verify_product_app() {
  local app="$1"
  [[ -d "${app}" ]] || fail "missing ${app}"
  [[ -x "${app}/Contents/MacOS/${EXECUTABLE}" ]] || fail "${EXECUTABLE} binary missing in ${app}"
  local name display bid
  name="$(plist_string "${app}" CFBundleName)"
  display="$(plist_string "${app}" CFBundleDisplayName)"
  bid="$(plist_string "${app}" CFBundleIdentifier)"
  [[ "${name}" == "${PRODUCT_DISPLAY}" ]] || fail "CFBundleName is '${name}', expected ${PRODUCT_DISPLAY}"
  [[ "${display}" == "${PRODUCT_DISPLAY}" ]] || fail "CFBundleDisplayName is '${display}', expected ${PRODUCT_DISPLAY}"
  [[ "${bid}" == "app.cursorbar" ]] || fail "bundle id is '${bid}'; must stay app.cursorbar"
}

resolve_app() {
  if [[ -n "${APP_PATH:-}" ]]; then
    [[ -d "${APP_PATH}" ]] || fail "APP_PATH is not a directory: ${APP_PATH}"
    echo "${APP_PATH}"
    return
  fi

  if need_xcodegen; then
    command -v xcodegen >/dev/null || fail "xcodegen required (brew install xcodegen)"
    xcodegen generate >&2
  fi

  mkdir -p "${DERIVED}"
  echo "+ xcodebuild -scheme ${SCHEME} -configuration ${CONFIGURATION} build" >&2
  set +e
  xcodebuild \
    -scheme "${SCHEME}" \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED}" \
    -configuration "${CONFIGURATION}" \
    build \
    >"${LOG}" 2>&1
  status=$?
  set -e
  if [[ "${status}" -ne 0 ]]; then
    tail -n 40 "${LOG}" >&2 || true
    fail "xcodebuild ${CONFIGURATION} failed (see ${LOG})"
  fi

  local app
  app="$(find "${DERIVED}/Build/Products/${CONFIGURATION}" -name "${APP_NAME}" -type d | head -1)"
  [[ -n "${app}" && -d "${app}" ]] || fail "${APP_NAME} not found after build (see ${LOG})"
  echo "${app}"
}

write_readme() {
  cat >"${1}" <<'EOF'
Cursor Accounts
===============

1. Drag Cursor Accounts to Applications.
2. Open Cursor Accounts from Applications.
   It lives in the menu bar. The Dock icon appears
   while the dashboard is open.
3. First launch is blocked until you allow it:
   System Settings → Privacy & Security →
   Open Anyway → Open Anyway again.

Unofficial. Not affiliated with Cursor or Anysphere.
EOF
}

layout_volume() {
  local mount="$1"
  osascript >/dev/null <<EOF || return 1
tell application "Finder"
  tell disk "${VOL_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {240, 160, 800, 520}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 80
    set position of item "${APP_NAME}" of container window to {140, 160}
    set position of item "Applications" of container window to {420, 160}
    set position of item "Read Me.txt" of container window to {280, 320}
    update without registering applications
    close
  end tell
end tell
EOF
}

verify_dmg() {
  local mount
  mount="$(hdiutil attach -nobrowse -readonly "${DMG_PATH}" | awk -F'\t' '/\/Volumes\// { print $NF; exit }')"
  [[ -n "${mount}" && -d "${mount}" ]] || fail "could not mount ${DMG_PATH}"
  MOUNT="${mount}"
  [[ -d "${mount}/${APP_NAME}" ]] || fail "DMG is missing ${APP_NAME}"
  [[ -L "${mount}/Applications" ]] || fail "DMG is missing Applications symlink"
  [[ -f "${mount}/Read Me.txt" ]] || fail "DMG is missing Read Me.txt"
  verify_product_app "${mount}/${APP_NAME}"
  hdiutil detach "${mount}" -quiet || fail "could not detach ${mount}"
  MOUNT=""
}

APP="$(resolve_app)"
verify_product_app "${APP}"

echo "+ stage ${APP_NAME}, Applications symlink, Read Me.txt"
mkdir -p "${CONTENT}"
ditto "${APP}" "${CONTENT}/${APP_NAME}" || fail "ditto into staging failed"
xattr -cr "${CONTENT}/${APP_NAME}" || true
ln -s /Applications "${CONTENT}/Applications"
write_readme "${CONTENT}/Read Me.txt"

mkdir -p "${DIST_DIR}"
rm -f "${DMG_PATH}"
if [[ -d "/Volumes/${VOL_NAME}" ]]; then
  hdiutil detach "/Volumes/${VOL_NAME}" -quiet || true
fi

echo "+ hdiutil create writable image"
hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${CONTENT}" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "${RW_DMG}" \
  >/dev/null || fail "hdiutil create (UDRW) failed"

echo "+ attach for Finder layout"
ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG}")"
MOUNT="$(printf '%s\n' "${ATTACH_OUT}" | awk -F'\t' '/\/Volumes\// { print $NF; exit }')"
[[ -n "${MOUNT}" && -d "${MOUNT}" ]] || fail "could not attach writable image"

sleep 1
if layout_volume "${MOUNT}"; then
  echo "+ Finder icon layout applied"
else
  echo "warning: Finder layout skipped (volume is still installable)" >&2
fi
sync
hdiutil detach "${MOUNT}" -quiet || fail "could not detach writable image"
MOUNT=""

echo "+ convert ${DMG_PATH}"
hdiutil convert \
  "${RW_DMG}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "${DMG_PATH}" \
  >/dev/null || fail "hdiutil convert failed"

[[ -f "${DMG_PATH}" ]] || fail "DMG was not written to ${DMG_PATH}"
verify_dmg
echo "Wrote ${DMG_PATH} ($(du -h "${DMG_PATH}" | awk '{print $1}'))"

#!/usr/bin/env bash
# Build Cursor Accounts (Release) and copy it into /Applications (or $INSTALL_DIR).
# Does not leave the user in DerivedData.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT_DISPLAY="Cursor Accounts"
APP_NAME="Cursor Accounts.app"
EXECUTABLE="Cursor Accounts"
SCHEME="CursorBar"
CONFIGURATION="Release"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
DERIVED="${ROOT}/.build/install-DerivedData"
LOG="${DERIVED}/xcodebuild-release.log"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

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

quit_matching() {
  local pattern="$1"
  local apple_name="$2"
  if pgrep -f "${pattern}" >/dev/null; then
    echo "+ quitting ${apple_name}"
    osascript -e "tell application \"${apple_name}\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8; do
      pgrep -f "${pattern}" >/dev/null || return 0
      sleep 0.25
    done
    pkill -f "${pattern}" 2>/dev/null || true
  fi
}

quit_if_running() {
  quit_matching "${INSTALL_DIR}/${APP_NAME}/Contents/MacOS/${EXECUTABLE}" "${PRODUCT_DISPLAY}"
  quit_matching "${INSTALL_DIR}/MultiCursor.app/Contents/MacOS/MultiCursor" 'MultiCursor'
}

retire_legacy_app() {
  local name
  for name in "MultiCursor.app" "CursorBar.app"; do
    local legacy="${INSTALL_DIR}/${name}"
    [[ -d "${legacy}" ]] || continue
    local bid
    bid="$(plist_string "${legacy}" CFBundleIdentifier)"
    if [[ "${bid}" == "app.cursorbar" ]]; then
      echo "+ removing leftover ${legacy} (same bundle id as ${PRODUCT_DISPLAY})"
      rm -rf "${legacy}"
    fi
  done
}

if need_xcodegen; then
  command -v xcodegen >/dev/null || fail "xcodegen required (brew install xcodegen)"
  xcodegen generate
fi

mkdir -p "${DERIVED}"
echo "+ xcodebuild -scheme ${SCHEME} -configuration ${CONFIGURATION} build"
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

APP="$(find "${DERIVED}/Build/Products/${CONFIGURATION}" -name "${APP_NAME}" -type d | head -1)"
[[ -n "${APP}" && -d "${APP}" ]] || fail "${APP_NAME} not found after build (see ${LOG})"
verify_product_app "${APP}"

quit_if_running
retire_legacy_app

DEST="${INSTALL_DIR}/${APP_NAME}"
mkdir -p "${INSTALL_DIR}" || fail "cannot create ${INSTALL_DIR}"
echo "+ ditto ${APP} ${DEST}"
ditto "${APP}" "${DEST}" || fail "ditto into ${DEST} failed"
xattr -cr "${DEST}" || fail "xattr -cr ${DEST} failed"

verify_product_app "${DEST}"
echo "Installed ${DEST}"
echo "  name: $(plist_string "${DEST}" CFBundleName)"
echo "  display: $(plist_string "${DEST}" CFBundleDisplayName)"
echo "  id: $(plist_string "${DEST}" CFBundleIdentifier)"
echo "  version: $(plist_string "${DEST}" CFBundleShortVersionString)"

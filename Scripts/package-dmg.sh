#!/usr/bin/env bash
# Build MultiCursor (Release) and write dist/MultiCursor-0.1.0.dmg
# with the .app plus an /Applications symlink (drag-to-install).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MultiCursor.app"
SCHEME="CursorBar"
CONFIGURATION="Release"
VERSION="${VERSION:-0.1.0}"
VOL_NAME="MultiCursor"
DIST_DIR="${ROOT}/dist"
DMG_NAME="MultiCursor-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
DERIVED="${ROOT}/.build/package-DerivedData"
LOG="${DERIVED}/xcodebuild-release.log"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/multicursor-dmg.XXXXXX")"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  rm -rf "${STAGE}"
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

APP="$(find "${DERIVED}/Build/Products" -name "${APP_NAME}" -type d | head -1)"
[[ -n "${APP}" && -d "${APP}" ]] || fail "${APP_NAME} not found after build (see ${LOG})"

mkdir -p "${STAGE}"
echo "+ stage ${APP_NAME} and Applications symlink"
ditto "${APP}" "${STAGE}/${APP_NAME}" || fail "ditto into staging failed"
xattr -cr "${STAGE}/${APP_NAME}" || true
ln -s /Applications "${STAGE}/Applications"

mkdir -p "${DIST_DIR}"
rm -f "${DMG_PATH}"
if [[ -d "/Volumes/${VOL_NAME}" ]]; then
  hdiutil detach "/Volumes/${VOL_NAME}" -quiet || true
fi

echo "+ hdiutil create ${DMG_PATH}"
hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGE}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" \
  >/dev/null || fail "hdiutil create failed"

[[ -f "${DMG_PATH}" ]] || fail "DMG was not written to ${DMG_PATH}"
echo "Wrote ${DMG_PATH} ($(du -h "${DMG_PATH}" | awk '{print $1}'))"

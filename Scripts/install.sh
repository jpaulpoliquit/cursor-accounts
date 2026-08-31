#!/usr/bin/env bash
# Build MultiCursor (Release) and copy it into /Applications (or $INSTALL_DIR).
# Does not leave the user in DerivedData.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MultiCursor.app"
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

DEST="${INSTALL_DIR}/${APP_NAME}"
mkdir -p "${INSTALL_DIR}" || fail "cannot create ${INSTALL_DIR}"
echo "+ ditto ${APP} ${DEST}"
ditto "${APP}" "${DEST}" || fail "ditto into ${DEST} failed"
xattr -cr "${DEST}" || fail "xattr -cr ${DEST} failed"

[[ -d "${DEST}" ]] || fail "install did not produce ${DEST}"
echo "Installed ${DEST}"

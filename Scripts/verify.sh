#!/usr/bin/env bash
# CursorBar verification harness.
# Modes: unit (default) | adapters | smoke | live-ro | usage-restart
# live-write is intentionally omitted (requires dual gates + exact revert).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:-unit}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${ROOT}/.verify/${MODE}-${STAMP}"
mkdir -p "${OUT_DIR}"

if [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

log() { printf '%s\n' "$*" | tee -a "${OUT_DIR}/verify.log"; }
run() {
  log "+ $*"
  "$@"
}

fail() {
  log "FAIL: $*"
  exit 1
}

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

ensure_project() {
  if need_xcodegen; then
    command -v xcodegen >/dev/null || fail "xcodegen required (brew install xcodegen)"
    run xcodegen generate
  else
    log "xcodegen skipped (project up to date)"
  fi
}

run_unit_tests() {
  ensure_project
  run xcodebuild \
    -scheme CursorBar \
    -destination 'platform=macOS' \
    -derivedDataPath "${OUT_DIR}/DerivedData" \
    test \
    >"${OUT_DIR}/xcodebuild-test.log" 2>&1 \
    || fail "xcodebuild test failed (see ${OUT_DIR}/xcodebuild-test.log)"
  log "unit tests ok"
}

static_secret_checks() {
  log "static secret / Keychain write checks"
  local leaks=0
  if command -v rg >/dev/null; then
    if rg -n 'cursor-access-token|cursor-refresh-token|Cursor Safe Storage' Sources --glob '*.swift' \
      | rg -v 'forbiddenCursorServiceNames|KeychainServicePolicy|KeychainServicePolicyTests'; then
      log "FAIL: forbidden Cursor Keychain names referenced outside policy"
      leaks=1
    fi
    if rg -n 'accessToken|refreshToken|Authorization' \
      Sources/Adapters/CursorProcessAdapter.swift \
      Sources/Adapters/IDESwitchEngine.swift \
      Sources/Domain/IDEProfilePaths.swift \
      Sources/Domain/IDESwitchPhase.swift 2>/dev/null; then
      log "FAIL: token material referenced in IDE launcher paths"
      leaks=1
    fi
  else
    log "rg missing; skipped ripgrep secret checks"
  fi
  [[ "${leaks}" -eq 0 ]] || fail "static secret checks failed"
  log "static checks ok"
}

static_architecture_checks() {
  log "static architecture invariant checks"
  local bad=0
  if command -v rg >/dev/null; then
    if rg -n 'ConfirmedOnDemandChange|ConfirmedLocalSignOut' Sources --glob '*.swift'; then
      log "FAIL: forgeable Domain confirmation tokens must stay deleted"
      bad=1
    fi
    if rg -n 'GlassEffectContainer' Sources --glob '*.swift' \
      | rg -v 'Sources/App/Design/StatusCapsule.swift'; then
      log "FAIL: GlassEffectContainer only allowed inside StatusCapsule owner"
      bad=1
    fi
    if rg -n 'func setOnDemandMode\(confirmed:|func signOutLocally\(confirmed:' Sources/App --glob '*.swift'; then
      log "FAIL: App entry points must take intents, not confirmation tokens"
      bad=1
    fi
    if ! rg -n 'func requestSignOutLocally\(seatID:|func requestSetOnDemand\(seatID:' Sources/App --glob '*.swift' >/dev/null; then
      log "FAIL: AppModel must expose confirmation-owned intent entry points"
      bad=1
    fi
    if rg -n 'SeatKeychainStore\(\)' Tests --glob '*.swift'; then
      log "FAIL: tests must not construct SeatKeychainStore() against production app.cursorbar"
      bad=1
    fi
    if rg -n 'account slot' Sources --glob '*.swift'; then
      log "FAIL: user-facing copy must not say account slot"
      bad=1
    fi
    for chart in \
      Sources/App/Dashboard/UsageChartPlotView.swift \
      Sources/App/Dashboard/UsageInsightsChartsView.swift
    do
      if ! rg -n 'onChange\(of: accountLabels\)' "${chart}" >/dev/null; then
        log "FAIL: ${chart} must rebuild inspection when accountLabels change"
        bad=1
      fi
    done
    while IFS= read -r file; do
      lines="$(wc -l <"$file" | tr -d ' ')"
      if [[ "${lines}" -gt 400 ]]; then
        log "FAIL: ${file} has ${lines} lines (>400)"
        bad=1
      fi
    done < <(find Sources -name '*.swift' -type f)
  else
    log "rg missing; skipped architecture checks"
  fi
  [[ "${bad}" -eq 0 ]] || fail "static architecture checks failed"
  log "architecture checks ok"
}

build_app() {
  ensure_project
  run xcodebuild \
    -scheme CursorBar \
    -destination 'platform=macOS' \
    -derivedDataPath "${OUT_DIR}/DerivedData" \
    -configuration Debug \
    build \
    >"${OUT_DIR}/xcodebuild-build.log" 2>&1 \
    || fail "xcodebuild build failed (see ${OUT_DIR}/xcodebuild-build.log)"
  APP="$(find "${OUT_DIR}/DerivedData/Build/Products" -name 'CursorBar.app' -type d | head -1)"
  [[ -n "${APP}" ]] || fail "CursorBar.app not found under DerivedData"
  printf '%s' "${APP}" >"${OUT_DIR}/app-path.txt"
  log "APP=${APP}"
}

detect_keychain_dialog() {
  if osascript -e 'tell application "System Events" to get name of every window of every process' 2>/dev/null \
    | tee "${OUT_DIR}/windows.txt" \
    | rg -i 'keychain|wants to use your confidential information|app\.cursorbar' >/dev/null; then
    return 0
  fi
  return 1
}

assert_stable_signing() {
  local app="$1"
  codesign -dv --verbose=4 "${app}" >"${OUT_DIR}/codesign.txt" 2>&1 || fail "codesign -dv failed"
  if rg -q 'Signature=adhoc' "${OUT_DIR}/codesign.txt"; then
    fail "CursorBar.app is ad-hoc signed; Keychain ACL will re-prompt every rebuild"
  fi
  if ! rg -q 'TeamIdentifier=8DF2GCMHK5' "${OUT_DIR}/codesign.txt"; then
    fail "CursorBar.app missing TeamIdentifier=8DF2GCMHK5 (see ${OUT_DIR}/codesign.txt)"
  fi
  codesign -d -r- "${app}" >"${OUT_DIR}/designated-requirement.txt" 2>&1 \
    || fail "failed to read designated requirement"
  if rg -q 'cdhash H"' "${OUT_DIR}/designated-requirement.txt"; then
    # cdhash-only DR is unstable across rebuilds.
    if ! rg -q 'certificate|anchor apple' "${OUT_DIR}/designated-requirement.txt"; then
      fail "designated requirement is cdhash-only (unstable for Keychain ACL)"
    fi
  fi
  log "signing ok team=8DF2GCMHK5"
  log "DR=$(tr '\n' ' ' <"${OUT_DIR}/designated-requirement.txt")"
}

run_smoke() {
  build_app
  APP="$(cat "${OUT_DIR}/app-path.txt")"
  assert_stable_signing "${APP}"
  DUMP_PATH="${OUT_DIR}/presentation-dump.txt"
  rm -f /tmp/cursorbar-presentation-dumped /tmp/cursorbar-presentation-dump-error
  log "launching ${APP}"
  # Do not restart the user's Cursor IDE session.
  rm -f /tmp/cursorbar-dashboard-opened /tmp/cursorbar-dashboard-key
  open -n "${APP}" --args --open-dashboard --dashboard-dark --mask-email \
    "--dump-presentation=${DUMP_PATH}" \
    || fail "open CursorBar.app failed"
  sleep 4
  osascript -e 'tell application "CursorBar" to activate' >/dev/null 2>&1 || true
  if detect_keychain_dialog; then
    fail "Keychain password/ACL dialog present after launch (see ${OUT_DIR}/windows.txt)"
  fi
  if ! pgrep -f 'CursorBar.app/Contents/MacOS/CursorBar' >/dev/null; then
    fail "CursorBar process not found after launch"
  fi
  log "process ok"
  # Dashboard must exist and become key/front via DashboardWindowPresenter.
  # Retry: launch open uses a delayed present, and LSUIElement activation needs a runloop.
  if ! python3 - <<'PY' >"${OUT_DIR}/dashboard-front.txt" 2>"${OUT_DIR}/dashboard-front.err"
import subprocess, sys, time, pathlib
marker = pathlib.Path("/tmp/cursorbar-dashboard-opened")
key_marker = pathlib.Path("/tmp/cursorbar-dashboard-key")
ok = False
for i in range(40):
    if i in (4, 12, 24):
        subprocess.run(["osascript", "-e", 'tell application "CursorBar" to activate'], check=False)
    count = "0"
    front = "?"
    try:
        front = subprocess.check_output([
            "osascript", "-e",
            'tell application "System Events" to get name of first application process whose frontmost is true'
        ], text=True).strip()
        count = subprocess.check_output([
            "osascript", "-e",
            'tell application "System Events" to count windows of process "CursorBar"'
        ], text=True).strip()
    except subprocess.CalledProcessError as exc:
        print(f"attempt={i} osascript_error={exc}")
        time.sleep(0.25)
        continue
    key_state = key_marker.read_text().strip() if key_marker.exists() else "missing"
    print(f"attempt={i} frontmost={front} window_count={count} key_marker={key_state} opened={marker.exists()}")
    if int(count or "0") >= 1 and (front == "CursorBar" or key_state == "key"):
        ok = True
        break
    time.sleep(0.25)
if not ok:
    sys.exit(2)
print("dashboard_front_ok")
PY
  then
    log "FAIL: Dashboard not key/front after open (see ${OUT_DIR}/dashboard-front.txt ${OUT_DIR}/dashboard-front.err)"
    fail "Dashboard window not key after --open-dashboard"
  fi
  log "dashboard front ok"

  # Wait for scheduled presentation dump (includes usage graph markers).
  graph_ok=0
  for _ in $(seq 1 40); do
    if [[ -f "${DUMP_PATH}" ]] && rg -q 'usage_graph=present' "${DUMP_PATH}"; then
      graph_ok=1
      break
    fi
    if [[ -f /tmp/cursorbar-presentation-dumped ]] && [[ -f "${DUMP_PATH}" ]] && rg -q 'usage_graph=present' "${DUMP_PATH}"; then
      graph_ok=1
      break
    fi
    sleep 0.25
  done
  if [[ "${graph_ok}" -ne 1 ]]; then
    if [[ -f "${DUMP_PATH}" ]]; then
      log "presentation dump (graph missing):"
      while IFS= read -r line; do log "  ${line}"; done <"${DUMP_PATH}"
    else
      log "presentation dump missing at ${DUMP_PATH}"
    fi
    # AX fallback: confirm Daily tokens exists in the dashboard UI tree.
    if osascript <<'APPLESCRIPT' >"${OUT_DIR}/graph-ax.txt" 2>"${OUT_DIR}/graph-ax.err"
tell application "System Events"
  tell process "CursorBar"
    set texts to value of every static text of every window
    return texts as string
  end tell
end tell
APPLESCRIPT
    then
      if rg -qi 'Daily tokens|usage chart|All Accounts' "${OUT_DIR}/graph-ax.txt"; then
        log "graph confirmed via AX fallback"
        graph_ok=1
      fi
    fi
  fi
  [[ "${graph_ok}" -eq 1 ]] || fail "smoke could not confirm usage graph via dump or AX"
  if [[ -f "${DUMP_PATH}" ]]; then
    cp "${DUMP_PATH}" "${OUT_DIR}/presentation-dump.final.txt" 2>/dev/null || true
    rg -n 'usage_|VERIFY_PRESENTATION|connectedCount|addAccount' "${DUMP_PATH}" \
      >"${OUT_DIR}/graph-evidence.txt" || true
    log "graph evidence from dump:"
    while IFS= read -r line; do log "  ${line}"; done <"${OUT_DIR}/graph-evidence.txt"
  fi

  if ! osascript <<'APPLESCRIPT' >"${OUT_DIR}/menu-ax.txt" 2>"${OUT_DIR}/menu-ax.err"
tell application "System Events"
  get name of every process
end tell
APPLESCRIPT
  then
    log "INCONCLUSIVE: AX/System Events unavailable (TCC?). See menu-ax.err"
    echo "inconclusive-ax" >"${OUT_DIR}/smoke-status.txt"
  else
    log "AX probe wrote process names only (redacted surface)"
    echo "ok" >"${OUT_DIR}/smoke-status.txt"
  fi
  if detect_keychain_dialog; then
    fail "Keychain password/ACL dialog appeared during smoke (see ${OUT_DIR}/windows.txt)"
  fi
  pkill -f 'CursorBar.app/Contents/MacOS/CursorBar' 2>/dev/null || true
  sleep 1
  if pgrep -f 'CursorBar.app/Contents/MacOS/CursorBar' >/dev/null; then
    fail "CursorBar still running after quit"
  fi
  log "smoke finished status=$(cat "${OUT_DIR}/smoke-status.txt")"
}

run_live_ro() {
  [[ "${CURSORBAR_LIVE:-}" == "1" ]] || fail "live-ro requires CURSORBAR_LIVE=1 (documented: CURSORBAR_LIVE=1 ./Scripts/verify.sh live-ro)"
  ensure_project
  # XCTest often drops custom env; absolute /tmp flag is the reliable enablement path.
  # Absolute paths (not locals) so the EXIT trap cannot trip `set -u`.
  LIVE_RO_FLAG_DOCUMENTED="/tmp/cursorbar-live-dashboard-verify"
  LIVE_RO_FLAG_TMPDIR="${TMPDIR:-/tmp/}cursorbar-live-dashboard-verify"
  touch "${LIVE_RO_FLAG_DOCUMENTED}" "${LIVE_RO_FLAG_TMPDIR}"
  cleanup_live_flags() {
    rm -f "${LIVE_RO_FLAG_DOCUMENTED}" "${LIVE_RO_FLAG_TMPDIR}"
  }
  trap cleanup_live_flags EXIT
  log "live-ro flags: ${LIVE_RO_FLAG_DOCUMENTED} ${LIVE_RO_FLAG_TMPDIR}"
  run env LIVE_DASHBOARD_VERIFY=1 TEST_RUNNER_LIVE_DASHBOARD_VERIFY=1 CURSORBAR_LIVE=1 xcodebuild \
    -scheme CursorBar \
    -destination 'platform=macOS' \
    -derivedDataPath "${OUT_DIR}/DerivedData" \
    -only-testing:CursorBarAdaptersTests/LiveDashboardReadVerifyTests \
    test \
    >"${OUT_DIR}/live-ro.log" 2>&1 \
    || fail "live-ro failed (see ${OUT_DIR}/live-ro.log)"
  if ! rg -q "LiveDashboardReadVerifyTests" "${OUT_DIR}/live-ro.log"; then
    fail "live-ro did not execute LiveDashboardReadVerifyTests (see ${OUT_DIR}/live-ro.log)"
  fi
  if rg -qi "Test skipped|test skipped|with [1-9][0-9]* test skipped" "${OUT_DIR}/live-ro.log"; then
    fail "live-ro skipped instead of executing (see ${OUT_DIR}/live-ro.log)"
  fi
  if ! rg -q 'LIVE plan_name=' "${OUT_DIR}/live-ro.log"; then
    fail "live-ro produced no LIVE plan evidence (see ${OUT_DIR}/live-ro.log)"
  fi
  if ! rg -q 'LIVE auto_percent=' "${OUT_DIR}/live-ro.log"; then
    fail "live-ro produced no LIVE pool percent evidence (see ${OUT_DIR}/live-ro.log)"
  fi
  if ! rg -q 'LIVE hard_limit_mode=' "${OUT_DIR}/live-ro.log"; then
    fail "live-ro produced no LIVE hard-limit evidence (see ${OUT_DIR}/live-ro.log)"
  fi
  if ! rg -q 'LIVE individual_used_cents=' "${OUT_DIR}/live-ro.log"; then
    fail "live-ro produced no LIVE individual_used_cents evidence (see ${OUT_DIR}/live-ro.log)"
  fi
  if ! rg -q 'LIVE cycle_start_ms=' "${OUT_DIR}/live-ro.log"; then
    fail "live-ro produced no LIVE billing cycle evidence (see ${OUT_DIR}/live-ro.log)"
  fi
  if ! rg -q 'LIVE graph_row_count=' "${OUT_DIR}/live-ro.log"; then
    fail "live-ro produced no LIVE graph row evidence (see ${OUT_DIR}/live-ro.log)"
  fi
  if ! rg -q 'LIVE graph_non_empty_points=' "${OUT_DIR}/live-ro.log"; then
    fail "live-ro produced no LIVE graph non_empty_points evidence (see ${OUT_DIR}/live-ro.log)"
  fi
  if rg -qi "Test skipped|test skipped|with [1-9][0-9]* test skipped" "${OUT_DIR}/live-ro.log"; then
    fail "live-ro skipped instead of executing (see ${OUT_DIR}/live-ro.log)"
  fi
  rg -n '^LIVE (cycle_|graph_|plan_|auto_percent|hard_limit|individual_used)' "${OUT_DIR}/live-ro.log" \
    >"${OUT_DIR}/live-evidence.txt" \
    || fail "failed to extract LIVE evidence lines"
  # Fail closed if graph probe was empty / zero.
  row_count="$(rg -o 'LIVE graph_row_count=[0-9]+' "${OUT_DIR}/live-ro.log" | rg -o '[0-9]+$' | tail -1 || true)"
  token_sum="$(rg -o 'LIVE graph_token_sum=[0-9]+' "${OUT_DIR}/live-ro.log" | rg -o '[0-9]+$' | tail -1 || true)"
  non_empty="$(rg -o 'LIVE graph_non_empty_points=[0-9]+' "${OUT_DIR}/live-ro.log" | rg -o '[0-9]+$' | tail -1 || true)"
  [[ -n "${row_count}" && "${row_count}" -gt 0 ]] || fail "live-ro graph_row_count missing or zero"
  [[ -n "${token_sum}" && "${token_sum}" -gt 0 ]] || fail "live-ro graph_token_sum missing or zero"
  [[ -n "${non_empty}" && "${non_empty}" -gt 0 ]] || fail "live-ro graph_non_empty_points missing or zero"
  log "live evidence (redacted):"
  while IFS= read -r line; do log "  ${line}"; done <"${OUT_DIR}/live-evidence.txt"
  log "live-ro ok (read-only Dashboard RPCs only; no SetHardLimit)"
}

stop_pid() {
  local pid="$1"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
    sleep 0.2
    kill -9 "${pid}" 2>/dev/null || true
  fi
}

run_usage_restart() {
  build_app
  APP="$(cat "${OUT_DIR}/app-path.txt")"
  BIN="${APP}/Contents/MacOS/CursorBar"
  [[ -x "${BIN}" ]] || fail "CursorBar binary missing at ${BIN}"

  CACHE="${OUT_DIR}/cache"
  DUMP="${OUT_DIR}/presentation.txt"
  IMMEDIATE="${OUT_DIR}/immediate.txt"
  HIDDEN="${OUT_DIR}/hidden.txt"
  mkdir -p "${CACHE}"
  rm -f /tmp/cursorbar-usage-cache-seeded /tmp/cursorbar-presentation-dumped

  log "seeding isolated usage cache"
  "${BIN}" --seed-usage-cache="${CACHE}" >/dev/null 2>"${OUT_DIR}/seed.err" &
  SEED_PID=$!
  seeded=0
  for _ in $(seq 1 40); do
    if [[ -f /tmp/cursorbar-usage-cache-seeded ]] && [[ -f "${CACHE}/usage-cards.json" ]] && [[ -f "${CACHE}/usage-chart.json" ]]; then
      seeded=1
      break
    fi
    sleep 0.1
  done
  stop_pid "${SEED_PID}"
  [[ "${seeded}" -eq 1 ]] || fail "usage-cache seed did not write files (see ${OUT_DIR}/seed.err)"

  log "launching hidden process against seeded cache"
  CURSORBAR_APPLICATION_SUPPORT="${CACHE}" \
    "${BIN}" --mask-email "--dump-presentation=${DUMP}" \
    >"${OUT_DIR}/hidden.out" 2>"${OUT_DIR}/hidden.err" &
  HIDDEN_PID=$!
  trap 'stop_pid "${HIDDEN_PID}"' EXIT

  appeared=0
  for _ in $(seq 1 50); do
    if [[ -f "${DUMP}" ]] && rg -q 'usage_token_sum=424242' "${DUMP}"; then
      cp "${DUMP}" "${IMMEDIATE}"
      appeared=1
      break
    fi
    sleep 0.1
  done
  [[ "${appeared}" -eq 1 ]] || fail "immediate dump missing seeded chart (see ${DUMP} ${OUT_DIR}/hidden.err)"

  rg -q 'usage_graph=present' "${IMMEDIATE}" || fail "restart dump missing usage_graph=present"
  rg -q 'usage_cards_count=1' "${IMMEDIATE}" || fail "restart dump missing hydrated card"
  rg -q 'usage_card_plans=verify-cache-ultra' "${IMMEDIATE}" || fail "restart dump missing card sentinel"
  rg -q 'dashboard_visible=false' "${IMMEDIATE}" || fail "hidden launch set dashboard_visible"
  if rg -q 'history_warm=warming' "${IMMEDIATE}"; then
    fail "hidden launch started history warm"
  fi
  log "immediate restart paint ok"

  sleep 2.2
  [[ -f "${DUMP}" ]] || fail "2s dump missing"
  cp "${DUMP}" "${HIDDEN}"
  rg -q 'usage_token_sum=424242' "${HIDDEN}" || fail "hidden dump lost seeded chart"
  rg -q 'dashboard_visible=false' "${HIDDEN}" || fail "hidden dump set dashboard_visible"
  if rg -q 'history_warm=warming' "${HIDDEN}"; then
    fail "hidden process warmed history after 2s"
  fi
  if rg -q 'usage_refresh_phase=refreshing' "${HIDDEN}"; then
    fail "hidden process refreshed cards after last-known hydrate"
  fi
  log "hidden pause warm ok"

  stop_pid "${HIDDEN_PID}"
  trap - EXIT
  log "usage-restart ok"
}

case "${MODE}" in
  unit)
    static_secret_checks
    static_architecture_checks
    run_unit_tests
    ;;
  adapters)
    static_secret_checks
    static_architecture_checks
    run_unit_tests
    ;;
  smoke)
    run_smoke
    ;;
  live-ro)
    run_live_ro
    ;;
  live-write)
    fail "live-write is not implemented. Requires pre-state capture, dual env gates, trap revert, post-revert equality."
    ;;
  usage-restart)
    run_usage_restart
    ;;
  *)
    fail "unknown mode '${MODE}' (unit|adapters|smoke|live-ro|usage-restart)"
    ;;
esac

log "OK mode=${MODE} out=${OUT_DIR}"

#!/usr/bin/env bash
# The CVE drill (docs/demo-script.md, Act 6), run against the local registry.
#
#   drill.sh stage     hold OpenSSL 3 and libxml2 at vulnerable builds, publish
#                      the held platform images, and move every app onto them
#                      (the "before" state)
#   drill.sh respond   release the holds, publish, and run the fleet:
#                      rebase --push --update-lock for every app. checkout and
#                      storefront rebase; catalog's rebase is refused. Then
#                      check F3 (what the refused app's lock and rebuild do)
#                      and rebuild catalog on the new build image.
#   drill.sh status    what each app runs on and what the scanner says
#   drill.sh f6 [APP]  reproduce factory#15: rebuilding from the lock the app
#                      had before its pin moved the tag back (default checkout)
#
# Every step is timed; logs go to evidence/logs/drill-*.log and a summary to
# evidence/drill-<step>.txt. Run scripts/up.sh and scripts/build-all.sh first.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
export PATH=${CC_BIN:-/tmp/cc-bin}:$PATH
export COSIGN_PASSWORD=${COSIGN_PASSWORD:-}
reg=localhost:5001
apps=(checkout storefront catalog)
mkdir -p evidence/logs .state/drill

summary=/dev/null
log() { printf '%s\n' "$*" | tee -a "$summary"; }
t0=$(date +%s)
step() { # name command... : run, log, time; never aborts the drill
  local name=$1 s rc; shift
  s=$(date +%s)
  set +e; "$@" >"evidence/logs/drill-$name.log" 2>&1; rc=$?; set -e
  log "$(printf '[t+%4ss] %-34s exit=%d %3ss' $(( $(date +%s) - t0 )) "$name" $rc $(( $(date +%s) - s )))"
  return 0
}
show() { # name pattern : interesting lines of a step's log
  grep -E "$2" "evidence/logs/drill-$1.log" | grep -vE 'Flag --tlog|Signing artifact|Using payload|Pushing signature' | sed 's/^/    /' | tee -a "$summary" || true
}
digest() { crane digest "$1" 2>/dev/null || echo "(none)"; }

publish_platform() { # prefix
  local p=$1 img
  for img in run-go run-python run-node build-python; do
    step "$p-lock-$img" clearcutt-factory lock -f "platform/images/$img/image.yaml"
    show "$p-lock-$img" 'libcrypto3|libssl3|libxml2|error'
    step "$p-build-$img" clearcutt-factory build -f "platform/images/$img/image.yaml" --push --out out
    show "$p-build-$img" '^built|^pushed|already published|high|critical|^error|blocked'
  done
}

scan() { # ref : fixable High/Critical, as the gate counts them
  grype -q "registry:$1" --platform linux/amd64 --only-fixed -o table 2>/dev/null |
    awk 'NR==1 || /High|Critical/' | sed 's/^/    /' | tee -a "$summary" || true
}

packages() { # ref : the held packages, from the image itself
  syft -q "registry:$1" --platform linux/amd64 -o json 2>/dev/null |
    python3 -I -c 'import json,sys; d=json.load(sys.stdin); print("    " + ", ".join(sorted({a["name"]+"="+a["version"] for a in d["artifacts"] if a["name"].startswith(("libcrypto3","libssl3","libxml2"))})) or "    (none)")' |
    tee -a "$summary" || true
}

status() {
  log "holds in platform/: $(python3 -I scripts/drill-holds.py show platform)"
  local img
  for img in platform/run-go:1 platform/run-python:3.14 platform/run-node:24 platform/build-python:3.14; do
    log "$reg/$img → $(digest "$reg/$img")"
    packages "$reg/$img"
  done
  local app
  for app in "${apps[@]}"; do
    log "$reg/apps/$app:latest → $(digest "$reg/apps/$app:latest")"
    log "    lock: base $(awk '/^base:/{f=1} f&&/digest:/{print substr($2,8,12); exit}' "$app/app.lock.yaml"), build image $(awk '/^  build:/{f=1} f&&/digest:/{print substr($2,8,12); exit}' "$app/app.lock.yaml")"
    packages "$reg/apps/$app:latest"
    scan "$reg/apps/$app:latest"
  done
}

case ${1:-} in
stage)
  summary=evidence/drill-stage.txt; : >"$summary"
  log "== drill stage $(date -u +%FT%TZ)"
  python3 -I scripts/drill-holds.py apply platform
  git --no-pager diff --stat -- platform | sed 's/^/    /' | tee -a "$summary"
  publish_platform stage
  for app in checkout storefront; do
    cp "$app/app.lock.yaml" ".state/drill/$app.lock.before-stage"
    step "stage-rebase-$app" clearcutt-factory rebase -f "$app/app.yaml" --push --update-lock --out out
    show "stage-rebase-$app" 'safe to rebase|incompatible|refused|^rebased|^pushed|^error|base '
  done
  # catalog was built against libxml2.so.16; the held run image has only
  # libxml2.so.2, so the fleet's rebase is refused (the drill in reverse) and
  # catalog is rebuilt on the held build image.
  cp catalog/app.lock.yaml .state/drill/catalog.lock.before-stage
  step stage-rebase-catalog clearcutt-factory rebase -f catalog/app.yaml --push --update-lock --out out
  show stage-rebase-catalog 'safe to rebase|incompatible|refused|^error|base |build image'
  step stage-lock-catalog clearcutt-factory lock -f catalog/app.yaml --update
  show stage-lock-catalog 'base |build image|stack'
  step stage-build-catalog clearcutt-factory build -f catalog/app.yaml --push --out out
  show stage-build-catalog '^built|smoke|^pushed|already published|high|critical|^error'
  log "== before"
  status
  log "== staged in $(( $(date +%s) - t0 ))s"
  ;;

respond)
  summary=evidence/drill-respond.txt; : >"$summary"
  log "== drill respond $(date -u +%FT%TZ)"
  for app in "${apps[@]}"; do cp "$app/app.lock.yaml" ".state/drill/$app.lock.before-respond"; done
  python3 -I scripts/drill-holds.py release platform
  git --no-pager diff --stat -- platform | sed 's/^/    /' | tee -a "$summary"
  publish_platform respond
  log "-- fleet: rebase --push --update-lock"
  for app in "${apps[@]}"; do
    step "respond-rebase-$app" clearcutt-factory rebase -f "$app/app.yaml" --push --update-lock --out out
    show "respond-rebase-$app" 'safe to rebase|incompatible|violation|^rebased|^pushed|^error|now pins|base |build image|smoke'
  done
  log "-- F3: catalog's lock after the refused rebase (base moved; build image?)"
  diff <(grep -A2 -E '^base:|^  build:' .state/drill/catalog.lock.before-respond) \
       <(grep -A2 -E '^base:|^  build:' catalog/app.lock.yaml) | sed 's/^/    /' | tee -a "$summary" || true
  log "-- F3: rebuild catalog from that lock (what merging the rebuild PR does today)"
  step respond-f3-build-catalog clearcutt-factory build -f catalog/app.yaml --out out/f3
  show respond-f3-build-catalog '^built|smoke|libxml2|Error|error'
  log "-- fix: re-resolve the build image too (lock --update), rebuild, publish"
  step respond-lock-catalog clearcutt-factory lock -f catalog/app.yaml --update
  show respond-lock-catalog 'base |build image|stack'
  step respond-build-catalog clearcutt-factory build -f catalog/app.yaml --push --out out
  show respond-build-catalog '^built|smoke|^pushed|already published|high|critical|^error'
  log "-- verify the rebased apps (repeat the recorded rebase)"
  for app in checkout storefront; do
    img=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"])' "out/$app-rebase/result.json")
    step "respond-verify-$app" sh -c "cd $app && clearcutt-factory verify --image $img --out ../out/verify"
    show "respond-verify-$app" 'reproducible|NOT'
  done
  log "== after"
  status
  log "== responded in $(( $(date +%s) - t0 ))s"
  ;;

status)
  summary=evidence/drill-status.txt; : >"$summary"
  status
  ;;

f6)
  app=${2:-checkout}
  summary=evidence/drill-f6.txt; : >"$summary"
  before=.state/drill/$app.lock.before-respond
  [[ -f $before ]] || { echo "run drill.sh respond first (needs $before)"; exit 1; }
  log "== factory#15 (F6): a push to $app's main before its pin PR merges"
  log "latest now (patched, rebased): $(digest "$reg/apps/$app:latest")"
  cp "$app/app.lock.yaml" ".state/drill/$app.lock.pinned"
  cp "$before" "$app/app.lock.yaml"          # main still has the old lock
  step "f6-render-$app" clearcutt-factory render -f "$app/app.yaml"
  step "f6-build-$app" clearcutt-factory build -f "$app/app.yaml" --push --out out/f6
  show "f6-build-$app" '^built|^pushed|already published|^error'
  log "latest after the push: $(digest "$reg/apps/$app:latest")"
  cp ".state/drill/$app.lock.pinned" "$app/app.lock.yaml"
  step "f6-render-back-$app" clearcutt-factory render -f "$app/app.yaml"
  log "-- recover: the fleet's next run rebases it again"
  step "f6-rebase-$app" clearcutt-factory rebase -f "$app/app.yaml" --push --out out
  show "f6-rebase-$app" 'safe to rebase|^rebased|already published|^pushed|^error'
  log "latest after the rebase: $(digest "$reg/apps/$app:latest")"
  ;;

*)
  sed -n '2,16p' "$0"; exit 2 ;;
esac

#!/usr/bin/env bash
# Build, smoke-test, scan, push, and sign everything, in dependency order:
#   platform images → stacks → apps.
# Locks are kept as committed (lock pins what to build); pass --update to
# re-resolve every input first, as the weekly update-locks job would.
#
# Each step's output goes to evidence/logs/<step>.log and a one-line summary
# (exit code, seconds, digest) to stdout. Run scripts/up.sh first.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
export PATH=${CC_BIN:-/tmp/cc-bin}:$PATH
export COSIGN_PASSWORD=${COSIGN_PASSWORD:-}
reg=localhost:5001
update=()
[[ ${1:-} == --update ]] && update=(--update)
mkdir -p evidence/logs out

step() { # name command...
  local name=$1 s rc; shift
  s=$(date +%s)
  set +e; "$@" >"evidence/logs/$name.log" 2>&1; rc=$?; set -e
  printf '%-28s exit=%d %4ss  %s\n' "$name" $rc $(( $(date +%s) - s )) \
    "$(grep -hE '^(built|pushed|rebuilt|signed|error)|is already published|is up to date' "evidence/logs/$name.log" | grep -v '^signed' | tail -1 | cut -c1-110)"
  return $rc
}

# The stacks are signed with the stacks key: regenerate their profile from the
# platform profile (factory has one signing key per profile; FINDINGS.md P-4).
{
  echo "# GENERATED from ../factory.org.yaml by scripts/build-all.sh; do not edit."
  echo "# Identical except that \`stack push\` signs with the stacks key: factory signs"
  echo "# everything with signing.key and has no per-role signing key (FINDINGS.md P-4)."
  sed -e 's#key: \.\./keys/images\.key#key: ../../keys/stacks.key#' -e 's#key: \.\./keys/#key: ../../keys/#' \
    platform/factory.org.yaml | grep -v '^# yaml-language-server'
} > platform/stacks/factory.org.yaml

for img in run-go build-go run-python build-python run-node build-node; do
  m=platform/images/$img/image.yaml
  step "lock-$img" clearcutt-factory lock -f "$m" "${update[@]}"
  step "build-$img" clearcutt-factory build -f "$m" --push --out out
done

for s in go python node; do
  step "stack-push-$s" clearcutt-factory stack push -f "platform/stacks/$s.yaml" --ref "$reg/stacks/$s:1"
done

for app in checkout catalog storefront; do
  step "lock-$app" clearcutt-factory lock -f "$app/app.yaml" "${update[@]}"
  step "build-$app" clearcutt-factory build -f "$app/app.yaml" --push --out out
done
